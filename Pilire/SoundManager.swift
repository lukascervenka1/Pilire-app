import AVFoundation
import Foundation

// MARK: - Sound
//
// Quiet, optional and polite. The audio session is `.ambient`: it mixes with
// whatever the player is already listening to (music, a podcast), never
// interrupts it, and is silenced by the ring/silent switch. Ambience only plays
// while the town is on screen; effects are short feedback that pairs with the
// haptics the app already has. Both can be turned off in Settings.

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    // MARK: Settings (read straight from UserDefaults so Settings' @AppStorage and this agree)

    static let ambientKey = "soundAmbientEnabled"
    static let effectsKey = "soundEffectsEnabled"

    private var ambientEnabled: Bool { Self.flag(Self.ambientKey) }
    private var effectsEnabled: Bool { Self.flag(Self.effectsKey) }

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    // MARK: Sounds

    enum Effect: String, CaseIterable {
        case pillarDone = "sfx_pillar_done"
        case coin       = "sfx_coin"
        case chest      = "sfx_chest_open"
        case build      = "sfx_build_place"
        case badge      = "sfx_badge"
    }

    enum Bed: String, CaseIterable {
        case birds    = "amb_day_birds"
        case crickets = "amb_night_crickets"
        case rain     = "amb_rain"
        case fog      = "amb_fog"
        case fire     = "amb_fire"

        /// How loud the bed sits when fully present. The files are levelled to
        /// the same loudness, so this is the mix: everything stays well under
        /// the effects.
        var level: Float {
            switch self {
            case .birds:            0.35   // birdsong sits well back
            case .crickets:         0.55
            case .rain:             0.60
            case .fog:              0.45
            case .fire:             0.50
            }
        }
    }

    /// What the town currently sounds like.
    struct Atmosphere: Equatable {
        var weather: TownWeather
        var daylight: DaylightPhase
        var fireLit: Bool
    }

    private var sessionReady = false
    private var beds: [Bed: AVAudioPlayer] = [:]
    private var effectPlayers: [Effect: [AVAudioPlayer]] = [:]
    private var stopTasks: [Bed: Task<Void, Never>] = [:]

    private var atmosphere: Atmosphere?
    /// The map is on screen and the app is in the foreground.
    private var listening = false

    /// Beds drift a little around their level so a long visit never settles
    /// into one flat texture.
    private var wander: [Bed: Float] = [:]
    private var currentTargets: [Bed: Float] = [:]
    private var wanderTask: Task<Void, Never>?
    private var chirpTask: Task<Void, Never>?
    /// Soft tones under everything calm, and long birdsong recordings: each
    /// a playlist that crossfades between tracks instead of one short loop.
    private lazy var pads = Rotation(prefix: "pad_", jitter: 0.38...0.62,
                                     pick: { [unowned self] in self.pickVariant($0, avoiding: $1) },
                                     activate: { [unowned self] in self.activateSession() })
    private lazy var birdsong = Rotation(prefix: "birdbed_", jitter: 0.7...1.0,
                                         pick: { [unowned self] in self.pickVariant($0, avoiding: $1) },
                                         activate: { [unowned self] in self.activateSession() })
    private var hasBirdsong: Bool { pickVariant("birdbed_", avoiding: nil) != nil }
    /// Short one-offs (chirps, fly-bys, turns) kept alive until they finish.
    private var liveShots: [AVAudioPlayer] = []
    private var lastVariant: [String: URL] = [:]

    private init() {}

    // MARK: Ambience

    /// Called whenever the weather, time of day or fire changes.
    func setAtmosphere(_ value: Atmosphere) {
        atmosphere = value
        refreshAmbience()
    }

    /// The map tab came on screen / went away, or the app moved to the background.
    func setListening(_ value: Bool) {
        listening = value
        refreshAmbience()
    }

    /// Settings changed.
    func settingsChanged() { refreshAmbience() }

    private func refreshAmbience() {
        guard let atmosphere, listening, ambientEnabled else {
            apply(targets: [:], fade: 1.2)
            return
        }
        apply(targets: Self.targets(for: atmosphere), fade: 2.5)
    }

    /// Which beds are present for a given moment, each 0...1.
    static func targets(for a: Atmosphere) -> [Bed: Float] {
        var t: [Bed: Float] = [:]
        let evening = a.daylight == .dusk || a.daylight == .night
        switch a.weather {
        case .rain:
            t[.rain] = 1                       // birds and crickets keep quiet in the rain
        case .fog:
            t[.fog] = 1
            t[evening ? .crickets : .birds] = 0.5
        case .sunny:
            t[evening ? .crickets : .birds] = 1
        }
        if a.fireLit { t[.fire] = 1 }
        return t
    }

    private func apply(targets: [Bed: Float], fade: TimeInterval) {
        currentTargets = targets
        setLiveLayers(targets: targets)
        for bed in Bed.allCases {
            let target = (targets[bed] ?? 0) * bed.level * (wander[bed] ?? 1)
            if bed == .birds, hasBirdsong {
                birdsong.set(level: target, fade: fade)
                continue
            }
            if target > 0 {
                stopTasks[bed]?.cancel()
                stopTasks[bed] = nil
                guard let player = bedPlayer(bed) else { continue }
                if !player.isPlaying {
                    player.volume = 0
                    player.play()
                }
                player.setVolume(target, fadeDuration: fade)
            } else if let player = beds[bed], player.isPlaying {
                player.setVolume(0, fadeDuration: fade)
                stopTasks[bed]?.cancel()
                stopTasks[bed] = Task { [weak player] in
                    try? await Task.sleep(for: .seconds(fade + 0.1))
                    guard !Task.isCancelled else { return }
                    player?.stop()
                }
            }
        }
        if targets.isEmpty { releaseSessionWhenSilent(after: fade + 0.3) }
    }

    private func bedPlayer(_ bed: Bed) -> AVAudioPlayer? {
        if let existing = beds[bed] { return existing }
        guard activateSession(), let url = Self.url(bed.rawValue, "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1          // CAF loops are cut on packet boundaries: no gap at the seam
        player.prepareToPlay()
        beds[bed] = player
        return player
    }

    // MARK: Living layers (soft tones, chirps, drifting levels)

    /// Starts or stops the layers that make the ambience change over time.
    private func setLiveLayers(targets: [Bed: Float]) {
        let birds = targets[.birds] ?? 0
        let calm = !targets.isEmpty && targets[.rain] == nil
        setPad(on: calm)
        setChirping(strength: birds)
        setWandering(on: !targets.isEmpty)
    }

    private func setWandering(on: Bool) {
        guard on else { wanderTask?.cancel(); wanderTask = nil; wander = [:]; return }
        guard wanderTask == nil else { return }
        wanderTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 14...24)))
                guard !Task.isCancelled, let self else { return }
                for bed in [Bed.birds, .crickets, .fog, .rain] { self.wander[bed] = Float.random(in: 0.62...1.0) }
                self.apply(targets: self.currentTargets, fade: 9)
            }
        }
    }

    /// Single bird calls at random moments, from random sides, a little
    /// different in pitch each time.
    private func setChirping(strength: Float) {
        guard strength > 0 else { chirpTask?.cancel(); chirpTask = nil; return }
        chirpStrength = strength
        guard chirpTask == nil else { return }
        chirpTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 14...36)))
                guard !Task.isCancelled, let self else { return }
                self.playRandom("chirp_", volume: Float.random(in: 0.12...0.22) * self.chirpStrength,
                                pan: Float.random(in: -0.85...0.85), rate: Float.random(in: 0.92...1.1))
            }
        }
    }
    private var chirpStrength: Float = 1

    private func setPad(on: Bool) {
        pads.set(level: on ? 1 : 0, fade: on ? 4 : 2)
    }

    private func stop(_ player: AVAudioPlayer, after delay: TimeInterval) {
        Task { [weak player] in
            try? await Task.sleep(for: .seconds(delay))
            player?.stop()
        }
    }

    /// A bird crossing the town: heard a few seconds into its flight, sweeping
    /// from one side to the other.
    func playBirdFlyby() {
        guard listening, ambientEnabled else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard let self, self.listening, self.ambientEnabled,
                  let player = self.playRandom("flyby_", volume: 0.3, pan: -0.7, rate: 1) else { return }
            let steps = 24
            for i in 1...steps {
                try? await Task.sleep(for: .seconds(player.duration / Double(steps)))
                guard player.isPlaying else { return }
                player.pan = -0.7 + 1.4 * Float(i) / Float(steps)
            }
        }
    }

    /// The soft turn of a building.
    func playRotate() {
        guard effectsEnabled else { return }
        playRandom("rotate_", volume: 0.8, rate: Float.random(in: 0.96...1.06))
    }

    /// Plays one randomly chosen file whose name starts with `prefix`.
    @discardableResult
    private func playRandom(_ prefix: String, volume: Float, pan: Float = 0, rate: Float = 1) -> AVAudioPlayer? {
        guard activateSession(), let url = pickVariant(prefix, avoiding: lastVariant[prefix]),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        lastVariant[prefix] = url
        player.enableRate = rate != 1
        if rate != 1 { player.rate = rate }
        player.volume = volume
        player.pan = pan
        player.prepareToPlay()
        player.play()
        liveShots.append(player)
        let life = player.duration / Double(max(rate, 0.5)) + 0.4
        Task { [weak self, weak player] in
            try? await Task.sleep(for: .seconds(life))
            self?.liveShots.removeAll { $0 === player }
        }
        return player
    }

    /// Any bundled m4a named `prefix…`, preferring one that isn't `avoiding`.
    private func pickVariant(_ prefix: String, avoiding: URL?) -> URL? {
        let all = (Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: "Sounds") ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: nil) ?? [])
        let matches = Array(Set(all.filter { $0.lastPathComponent.hasPrefix(prefix) }))
        let fresh = matches.filter { $0 != avoiding }
        return (fresh.isEmpty ? matches : fresh).randomElement()
    }

    // MARK: Effects

    func play(_ effect: Effect, volume: Float = 1) {
        guard effectsEnabled, activateSession() else { return }
        var pool = effectPlayers[effect] ?? []
        let player: AVAudioPlayer
        if let idle = pool.first(where: { !$0.isPlaying }) {
            player = idle
        } else if pool.count < 3, let url = Self.url(effect.rawValue, "m4a"),
                  let fresh = try? AVAudioPlayer(contentsOf: url) {
            fresh.prepareToPlay()
            pool.append(fresh)
            effectPlayers[effect] = pool
            player = fresh
        } else {
            return
        }
        player.currentTime = 0
        player.volume = volume
        player.play()
    }

    // MARK: Session

    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        if !sessionReady {
            do {
                try session.setCategory(.ambient, mode: .default)
                sessionReady = true
            } catch { return false }
        }
        do { try session.setActive(true) } catch { return false }
        return true
    }

    /// With nothing playing, give the session back so other apps' audio can
    /// return to full volume.
    private func releaseSessionWhenSilent(after delay: TimeInterval) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            let anyPlaying = beds.values.contains { $0.isPlaying }
                || effectPlayers.values.joined().contains { $0.isPlaying }
                || pads.isPlaying || birdsong.isPlaying
            if !anyPlaying {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}

// MARK: - Playlist that crossfades

/// Plays bundled tracks named `prefix…` one after another, picking at random
/// (never the same twice in a row), entering each at a random point and
/// crossfading over several seconds, so a long stay never hears a loop.
@MainActor
private final class Rotation {
    private let prefix: String
    private let jitter: ClosedRange<Float>
    private let pick: (String, URL?) -> URL?
    private let activate: () -> Bool

    private var player: AVAudioPlayer?
    private var trackGain: Float = 1
    private var level: Float = 0
    private var last: URL?
    private var task: Task<Void, Never>?

    var isPlaying: Bool { player?.isPlaying ?? false }

    init(prefix: String, jitter: ClosedRange<Float>,
         pick: @escaping (String, URL?) -> URL?, activate: @escaping () -> Bool) {
        self.prefix = prefix; self.jitter = jitter; self.pick = pick; self.activate = activate
    }

    func set(level: Float, fade: TimeInterval) {
        self.level = level
        guard level > 0 else {
            task?.cancel(); task = nil
            if let old = player { old.setVolume(0, fadeDuration: fade); retire(old, after: fade + 0.2) }
            player = nil
            return
        }
        player?.setVolume(level * trackGain, fadeDuration: fade)
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.advance() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// Starts the next track over the current one; returns how long to wait.
    private func advance() -> TimeInterval? {
        guard level > 0, activate(), let url = pick(prefix, last),
              let next = try? AVAudioPlayer(contentsOf: url) else { return nil }
        last = url
        let fade = min(7.0, max(2.0, next.duration / 4))
        next.currentTime = Double.random(in: 0...(next.duration * 0.5))
        trackGain = Float.random(in: jitter)
        next.volume = 0
        next.prepareToPlay()
        next.play()
        next.setVolume(level * trackGain, fadeDuration: fade)
        if let old = player { old.setVolume(0, fadeDuration: fade); retire(old, after: fade + 0.2) }
        player = next
        return max(next.duration - next.currentTime - fade, 4)
    }

    private func retire(_ old: AVAudioPlayer, after delay: TimeInterval) {
        Task { [weak old] in
            try? await Task.sleep(for: .seconds(delay))
            old?.stop()
        }
    }
}
