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
            case .birds, .crickets: 0.55
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
    private var padTask: Task<Void, Never>?
    private var padPlayer: AVAudioPlayer?
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
                try? await Task.sleep(for: .seconds(Double.random(in: 9...26)))
                guard !Task.isCancelled, let self else { return }
                self.playRandom("chirp_", volume: Float.random(in: 0.28...0.5) * self.chirpStrength,
                                pan: Float.random(in: -0.85...0.85), rate: Float.random(in: 0.92...1.1))
            }
        }
    }
    private var chirpStrength: Float = 1

    /// Soft tones under the birds. Tracks follow each other with long
    /// crossfades, never the same one twice in a row, each at a slightly
    /// different level.
    private func setPad(on: Bool) {
        if !on {
            padTask?.cancel(); padTask = nil
            if let old = padPlayer { old.setVolume(0, fadeDuration: 2); stop(old, after: 2.2) }
            padPlayer = nil
            return
        }
        guard padTask == nil else { return }
        padTask = Task { [weak self] in
            var last: URL?
            while !Task.isCancelled {
                guard let self, self.activateSession(),
                      let url = self.pickVariant("pad_", avoiding: last),
                      let next = try? AVAudioPlayer(contentsOf: url) else { return }
                last = url
                let fade = min(7.0, max(2.0, next.duration / 4))
                // Enter anywhere in the first half, so even a single track
                // never lines up the same way twice.
                next.currentTime = Double.random(in: 0...(next.duration * 0.5))
                next.volume = 0
                next.prepareToPlay()
                next.play()
                next.setVolume(Float.random(in: 0.38...0.62), fadeDuration: fade)
                if let old = self.padPlayer { old.setVolume(0, fadeDuration: fade); self.stop(old, after: fade + 0.2) }
                self.padPlayer = next
                try? await Task.sleep(for: .seconds(max(next.duration - next.currentTime - fade, 4)))
            }
        }
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
                  let player = self.playRandom("flyby_", volume: 0.5, pan: -0.7, rate: 1) else { return }
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
