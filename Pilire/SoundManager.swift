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

        /// Sounds that sit in the town itself, so they fade as the camera pulls back.
        var followsZoom: Bool { self == .birds || self == .crickets || self == .fire }

        /// How loud the bed sits when fully present. The files are levelled to
        /// the same loudness, so this is the mix: everything stays well under
        /// the effects.
        var level: Float {
            switch self {
            case .birds:            0.35   // birdsong sits well back
            case .crickets:         0.55
            case .rain:             0.60
            case .fog:              0.45
            case .fire:             0.32   // a quiet crackle in the background
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

    /// How close the camera is: 1 fully zoomed in, falling as it pulls back.
    /// Birds, crickets and the fire are "in" the town and fade with distance;
    /// music, rain and fog fill the whole scene and stay put.
    private var proximity: Float = 1
    private static func proximity(forScale scale: Double) -> Float {
        let t = Float((scale - 3.5) / (16 - 3.5)).clamped(0, 1)   // 0 = closest
        return 1 - 0.85 * t * t.squareRoot()                        // 1 → 0.15
    }

    /// The map camera zoomed; called on every pinch step.
    func setZoom(orthographicScale scale: Double) {
        let p = Self.proximity(forScale: scale)
        guard abs(p - proximity) > 0.01 else { return }
        proximity = p
        guard listening, ambientEnabled, atmosphere != nil else { return }
        apply(targets: currentTargets, fade: 0.25)
    }
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
    private lazy var pads = Rotation(prefix: "pad_", jitter: 0.45...0.6, crossfade: 16,
                                     pick: { [unowned self] in self.pickVariant($0, avoiding: $1) },
                                     activate: { [unowned self] in self.activateSession() })
    private lazy var birdsong = Rotation(prefix: "birdbed_", jitter: 0.8...1.0, crossfade: 18,
                                         pick: { [unowned self] in self.pickVariant($0, avoiding: $1) },
                                         activate: { [unowned self] in self.activateSession() })
    private var hasBirdsong: Bool { pickVariant("birdbed_", avoiding: nil) != nil }
    /// Heavier rain with wind for storms, as long crossfading recordings.
    private lazy var stormRain = Rotation(prefix: "stormrain_", jitter: 0.85...1.0, crossfade: 16,
                                          pick: { [unowned self] in self.pickVariant($0, avoiding: $1) },
                                          activate: { [unowned self] in self.activateSession() })
    private var hasStormRain: Bool { pickVariant("stormrain_", avoiding: nil) != nil }
    /// Gentle everyday rain, also as long crossfading recordings.
    private lazy var gentleRain = Rotation(prefix: "rainbed_", jitter: 0.85...1.0, crossfade: 16,
                                           pick: { [unowned self] in self.pickVariant($0, avoiding: $1) },
                                           activate: { [unowned self] in self.activateSession() })
    private var hasGentleRain: Bool { pickVariant("rainbed_", avoiding: nil) != nil }
    private var owlTask: Task<Void, Never>?
    /// Short one-offs (chirps, fly-bys, turns) kept alive until they finish.
    private var liveShots: [AVAudioPlayer] = []
    private var lastVariant: [String: URL] = [:]
    private var thunderTask: Task<Void, Never>?
    private var thunderPlayer: AVAudioPlayer?

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
        if !canHearThunder {
            thunderTask?.cancel(); thunderTask = nil
            thunderPlayer?.stop(); thunderPlayer = nil
        }
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
        case .rain, .storm:
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
            let distance: Float = bed.followsZoom ? proximity : 1
            var target = (targets[bed] ?? 0) * bed.level * (wander[bed] ?? 1) * distance
            if bed == .birds, hasBirdsong {
                birdsong.set(level: target, fade: fade)
                continue
            }
            if bed == .rain {
                // A storm swaps the gentle rain loop for its heavier recordings.
                let storm = atmosphere?.weather == .storm && hasStormRain && target > 0
                let gentle = !storm && hasGentleRain && target > 0
                stormRain.set(level: storm ? target : 0, fade: fade)
                gentleRain.set(level: gentle ? target : 0, fade: fade)
                if storm || gentle { target = 0 }
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
        // Full soft tones in calm weather, a faint trace of them under gentle
        // rain, none in a storm.
        let storm = atmosphere?.weather == .storm
        let padLevel: Float = targets.isEmpty || storm ? 0 : (targets[.rain] == nil ? 1 : 0.35)
        setPad(level: padLevel)
        setChirping(strength: birds)
        let evening = atmosphere.map { $0.daylight == .dusk || $0.daylight == .night } ?? false
        setOwls(on: !targets.isEmpty && evening)
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
                self.playRandom("chirp_", volume: Float.random(in: 0.12...0.22) * self.chirpStrength * self.proximity,
                                pan: Float.random(in: -0.85...0.85), rate: Float.random(in: 0.92...1.1))
            }
        }
    }
    private var chirpStrength: Float = 1

    private func setPad(level: Float) {
        pads.set(level: level, fade: level > 0 ? 4 : 2)
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
                  self.atmosphere?.weather.hasPrecipitation != true,
                  let player = self.playRandom("flyby_", volume: 0.3 * self.proximity, pan: -0.7, rate: 1) else { return }
            let steps = 24
            for i in 1...steps {
                try? await Task.sleep(for: .seconds(player.duration / Double(steps)))
                guard player.isPlaying else { return }
                player.pan = -0.7 + 1.4 * Float(i) / Float(steps)
            }
        }
    }

    private var canHearThunder: Bool {
        listening && ambientEnabled && atmosphere?.weather == .storm
    }

    /// Distant, low rumble arrives after the light. Belongs to ambience and is
    /// cancelled immediately when the map is hidden, muted or the weather clears.
    func playDistantThunder() {
        guard canHearThunder, thunderTask == nil else { return }
        thunderTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double.random(in: 1.5...2.7)))
            guard !Task.isCancelled, let self else { return }
            self.thunderTask = nil
            guard self.canHearThunder, self.activateSession(),
                  let url = self.pickThunder(),
                  let player = try? AVAudioPlayer(contentsOf: url) else { return }
            self.thunderPlayer?.stop()
            self.thunderPlayer = player
            player.volume = Float.random(in: 0.2...0.34)   // nearer and farther strikes
            player.pan = Float.random(in: -0.3...0.3)
            player.prepareToPlay()
            player.play()
        }
    }

    /// A recorded roll most of the time, the original synthesized rumble now and then.
    private func pickThunder() -> URL? {
        let recorded = pickVariant("thunder_", avoiding: lastVariant["thunder_"])
        if let recorded, Int.random(in: 0..<5) > 0 {
            lastVariant["thunder_"] = recorded
            return recorded
        }
        return Self.url("amb_distant_thunder", "m4a") ?? recorded
    }

    /// An owl somewhere in the dark, now and then — never often.
    private func setOwls(on: Bool) {
        guard on else { owlTask?.cancel(); owlTask = nil; return }
        guard owlTask == nil else { return }
        owlTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double.random(in: 20...60)))
            while !Task.isCancelled {
                guard let self else { return }
                let rainy = self.atmosphere?.weather.hasPrecipitation ?? false
                self.playRandom("owl_", volume: Float.random(in: 0.16...0.28) * self.proximity * (rainy ? 0.7 : 1),
                                pan: Float.random(in: -0.8...0.8), rate: Float.random(in: 0.96...1.04))
                try? await Task.sleep(for: .seconds(Double.random(in: 70...170)))
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
                || pads.isPlaying || birdsong.isPlaying || stormRain.isPlaying || gentleRain.isPlaying || thunderPlayer?.isPlaying == true
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
/// (never the same twice in a row) and entering each at a random point.
/// Tracks overlap by a long equal-power crossfade driven by its own ticker,
/// so the overall loudness never dips and no track is heard ending.
@MainActor
private final class Rotation {
    private let prefix: String
    private let jitter: ClosedRange<Float>
    private let crossfade: TimeInterval
    private let pick: (String, URL?) -> URL?
    private let activate: () -> Bool

    private var current: AVAudioPlayer?
    private var currentGain: Float = 1
    private var outgoing: AVAudioPlayer?
    private var outgoingGain: Float = 1
    private var blendStart: Date?
    private var last: URL?

    /// Overall level, ramped linearly from `from` to `to`.
    private var from: Float = 0, to: Float = 0
    private var rampStart = Date(), rampLength: TimeInterval = 0.01
    private var ticker: Task<Void, Never>?

    var isPlaying: Bool { current?.isPlaying ?? false }

    init(prefix: String, jitter: ClosedRange<Float>, crossfade: TimeInterval,
         pick: @escaping (String, URL?) -> URL?, activate: @escaping () -> Bool) {
        self.prefix = prefix; self.jitter = jitter; self.crossfade = crossfade
        self.pick = pick; self.activate = activate
    }

    func set(level: Float, fade: TimeInterval) {
        guard abs(level - to) > 0.001 else { return }
        from = levelNow(); to = level
        rampStart = .now; rampLength = max(fade, 0.01)
        if level > 0, current == nil { startTrack(blending: false) }
        if ticker == nil, current != nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard let self, self.tick() else { return }
                }
            }
        }
        tick()
    }

    private func levelNow() -> Float {
        let t = Float(min(1, Date.now.timeIntervalSince(rampStart) / rampLength))
        return from + (to - from) * t
    }

    /// Applies the current volumes; returns false once everything has stopped.
    @discardableResult
    private func tick() -> Bool {
        let level = levelNow()
        if level <= 0.0005, to == 0 {
            current?.stop(); outgoing?.stop()
            current = nil; outgoing = nil; blendStart = nil
            ticker?.cancel(); ticker = nil
            return false
        }
        guard let cur = current else { return false }

        // Begin the next track while this one still has a crossfade to go.
        if blendStart == nil, cur.duration - cur.currentTime < crossfade + 0.5 {
            startTrack(blending: true)
        }
        if let start = blendStart {
            let p = min(1, Date.now.timeIntervalSince(start) / crossfade)
            let inGain = Float(sin(p * .pi / 2)), outGain = Float(cos(p * .pi / 2))
            current?.volume = level * currentGain * inGain
            outgoing?.volume = level * outgoingGain * outGain
            if p >= 1 { outgoing?.stop(); outgoing = nil; blendStart = nil }
        } else {
            cur.volume = level * currentGain
        }
        return true
    }

    private func startTrack(blending: Bool) {
        guard activate(), let url = pick(prefix, last),
              let next = try? AVAudioPlayer(contentsOf: url) else { return }
        last = url
        // Enter early enough that the track plays a good while before the next blend.
        next.currentTime = Double.random(in: 0...max(0, next.duration * 0.25))
        next.volume = 0
        next.prepareToPlay()
        next.play()
        if blending, let cur = current {
            outgoing?.stop()
            outgoing = cur; outgoingGain = currentGain
            blendStart = .now
        }
        current = next
        currentGain = Float.random(in: jitter)
    }
}

private extension Float {
    func clamped(_ lo: Float, _ hi: Float) -> Float { Swift.min(hi, Swift.max(lo, self)) }
}
