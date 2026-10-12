import Foundation
import SwiftData
import SceneKit
import UIKit

// MARK: - Animal kinds (the "Zoo" shop tier — bought for coins, roam the map)

enum AnimalKind: String, Codable, CaseIterable, Identifiable {
    // rawValues `dog` and `cow` are kept from the old roster so an already
    // owned pet survives the switch (dog now shows as a Shiba).
    case dog, husky, fox, wolf, deer, cow, horse, alpaca
    var id: String { rawValue }

    // Tolerant decode: an animal saved under a removed species (old roster) maps
    // to the dog instead of crashing SwiftData on an unknown raw value.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AnimalKind(rawValue: raw) ?? .dog
    }

    @MainActor
    var displayName: String {
        switch self {
        case .dog:    L(T(cs: "Pes", sk: "Pes", en: "Dog"))
        case .husky:  L(T(cs: "Husky", sk: "Husky", en: "Husky"))
        case .fox:    L(T(cs: "Liška", sk: "Líška", en: "Fox"))
        case .wolf:   L(T(cs: "Vlk", sk: "Vlk", en: "Wolf"))
        case .deer:   L(T(cs: "Srnec", sk: "Srnec", en: "Deer"))
        case .cow:    L(T(cs: "Kráva", sk: "Krava", en: "Cow"))
        case .horse:  L(T(cs: "Kůň", sk: "Kôň", en: "Horse"))
        case .alpaca: L(T(cs: "Alpaka", sk: "Alpaka", en: "Alpaca"))
        }
    }

    /// Coin price — the zoo is a premium reward for a well-run town.
    var cost: Int {
        switch self {
        case .dog:    250
        case .husky:  280
        case .fox:    320
        case .alpaca: 300
        case .deer:   340
        case .wolf:   360
        case .cow:    380
        case .horse:  450
        }
    }

    @MainActor
    var shopDescription: String {
        switch self {
        case .dog:
            L(T(cs: "Věrný parťák, občas vyběhne a dovádí",
                sk: "Verný parťák, občas vybehne a dovádi",
                en: "A loyal friend who breaks into the odd sprint"))
        case .husky:
            L(T(cs: "Neposedný severský pes plný energie",
                sk: "Neposedný severský pes plný energie",
                en: "A restless northern dog, full of energy"))
        case .fox:
            L(T(cs: "Zvědavá liška, čmuchá a klusá kolem",
                sk: "Zvedavá líška, ňuchá a klusá okolo",
                en: "A curious fox, sniffing and trotting about"))
        case .wolf:
            L(T(cs: "Tichý vlk, obchází svoje území",
                sk: "Tichý vlk, obchádza svoje územie",
                en: "A quiet wolf walking its territory"))
        case .deer:
            L(T(cs: "Plachý srnec, popásá se na louce",
                sk: "Plachý srnec, pasie sa na lúke",
                en: "A shy deer grazing in the meadow"))
        case .cow:
            L(T(cs: "V klidu přežvykuje na louce",
                sk: "Pokojne prežúva na lúke",
                en: "Chewing away peacefully in the grass"))
        case .horse:
            L(T(cs: "Klidný kůň, prochází se mezi domy",
                sk: "Pokojný kôň, prechádza sa medzi domami",
                en: "A calm horse wandering between the houses"))
        case .alpaca:
            L(T(cs: "Rozvážná alpaka, pořád v pohodě",
                sk: "Rozvážna alpaka, stále v pohode",
                en: "An unhurried alpaca, always at ease"))
        }
    }

    /// SF Symbol for the shop row (only dogs have a real symbol).
    var symbolName: String {
        switch self {
        case .dog, .husky: "dog.fill"
        default:           "pawprint.fill"
        }
    }

    /// UI tint for the shop icon — echoes the animal's coat.
    var tint: (r: Double, g: Double, b: Double) {
        switch self {
        case .dog:    (0.72, 0.52, 0.30)
        case .husky:  (0.55, 0.60, 0.66)
        case .fox:    (0.85, 0.48, 0.24)
        case .wolf:   (0.50, 0.52, 0.56)
        case .deer:   (0.66, 0.47, 0.30)
        case .cow:    (0.30, 0.30, 0.32)
        case .horse:  (0.46, 0.32, 0.22)
        case .alpaca: (0.84, 0.76, 0.64)
        }
    }

    /// Filename (without extension) of the optional rigged USDZ asset.
    var assetName: String {
        switch self {
        case .dog: "shiba"
        default:   rawValue
        }
    }

    /// Target footprint (longest horizontal side) in tiles. Scaling by footprint
    /// instead of height keeps bodies a consistent size regardless of neck/antler
    /// height, so a horse and a dog read as similarly sized.
    var targetSize: CGFloat {
        switch self {
        case .cow, .horse: 0.8
        case .fox:         0.58
        default:           0.7    // dog, husky, wolf, deer, alpaca — one calm size
        }
    }

    /// Correction so an imported model ends up facing +Z (our movement forward).
    /// The Quaternius glTF models already face +Z, so no rotation is needed.
    /// (Flip to `.pi` if a model walks backwards, or ±`.pi/2` if it walks sideways.)
    var assetFacingYaw: Float {
        0
    }

    // MARK: Behaviour tuning

    /// Seconds to cross one tile at a walk (smaller = faster).
    var walkSecondsPerTile: Double {
        switch self {
        case .dog:    0.85
        case .husky:  0.8
        case .fox:    0.75
        case .wolf:   0.9
        case .deer:   0.8
        case .cow:    1.5
        case .horse:  1.0
        case .alpaca: 1.2
        }
    }

    var swimSecondsPerTile: Double { walkSecondsPerTile * 1.6 }

    /// How often a "turn" ends in movement vs. an idle behaviour.
    var moveChance: Double {
        switch self {
        case .dog:    0.60
        case .husky:  0.65
        case .fox:    0.65
        case .wolf:   0.55
        case .deer:   0.5
        case .cow:    0.30
        case .horse:  0.45
        case .alpaca: 0.4
        }
    }

    /// Which species break into an occasional sprint (dog zoomies etc.).
    var canDash: Bool { self == .dog || self == .husky || self == .fox }

    /// Night owls stay awake after dark while everyone else sleeps.
    var isNocturnal: Bool { self == .wolf || self == .fox }

    /// Only dogs move into a doghouse (and eat from its bowl). Other species
    /// will get their own shelters later.
    var usesDoghouse: Bool { self == .dog || self == .husky }

    var shadowRadius: CGFloat {
        switch self {
        case .cow, .horse:  0.30
        case .fox:          0.18
        default:            0.24
        }
    }
}

// MARK: - Persisted ownership

@Model
final class OwnedAnimal {
    var kind: AnimalKind
    var boughtDate: Date
    /// Tucked into the doghouse: kept in the collection but not roaming the map.
    var isTucked: Bool = false
    /// Player-given name (empty → shown as the species name).
    var name: String = ""

    init(kind: AnimalKind, boughtDate: Date = .now) {
        self.kind = kind
        self.boughtDate = boughtDate
    }

    /// Name to show — the given one, or the species as a fallback.
    @MainActor
    var displayName: String { name.isEmpty ? kind.displayName : name }
}

// MARK: - AnimalNode (roams the grid, never through buildings)

/// A living pet. Position sits on integer grid cells; it only ever moves onto a
/// cell the scene reports as walkable, so it can approach buildings and walk on
/// roads but never clips through them. `poseNode` carries local poses (crouch,
/// hop, bob) so the parent node stays clean for facing + grid movement.
final class AnimalNode: SCNNode {
    let kind: AnimalKind
    private(set) var col = 0
    private(set) var row = 0
    weak var associatedAnimal: OwnedAnimal?

    private let poseNode = SCNNode()
    private var lastDir: (dx: Int, dy: Int)?
    private let calm: Bool                       // Reduce Motion → gentle, mostly still

    /// Skeletal animation clips from an imported glTF, keyed lowercased. Empty
    /// while we show the built-in procedural model (a rig may load in later).
    private var clips: [String: SCNAnimationPlayer]
    private var rigged: Bool { !clips.isEmpty }
    private var currentClipKey: String?

    private let isWalkable: (Int, Int) -> Bool
    private let isWater:    (Int, Int) -> Bool
    private let worldFor:   (Int, Int) -> SCNVector3
    private let isNight:    () -> Bool

    /// Somewhere the pet wants to get to (its doghouse at night, or a full bowl).
    /// The scene supplies these; nil means "just wander".
    var findBed:  ((AnimalNode) -> (cell: (col: Int, row: Int), world: SCNVector3, yaw: Float)?)?
    var findBowl: ((AnimalNode) -> (cell: (col: Int, row: Int), world: SCNVector3)?)?
    var onAteFromBowl: ((AnimalNode) -> Void)?
    private var inKennel = false
    private var commandedNap = false
    /// Blocks targeted trips (bowl, kennel) for a while after one fails, so an
    /// unreachable target can't be retried in a tight loop.
    private var targetCooldownUntil = Date.distantPast

    private(set) var isSleeping = false
    private var forcedAwake = false          // set for a while after the player wakes it

    init(kind: AnimalKind,
         calm: Bool,
         isWalkable: @escaping (Int, Int) -> Bool,
         isWater: @escaping (Int, Int) -> Bool,
         worldFor: @escaping (Int, Int) -> SCNVector3,
         isNight: @escaping () -> Bool = { false }) {
        self.kind = kind
        self.calm = calm
        self.clips = [:]
        self.isWalkable = isWalkable
        self.isWater = isWater
        self.worldFor = worldFor
        self.isNight = isNight
        super.init()
        addChildNode(poseNode)
        addChildNode(contactShadowNode(radius: kind.shadowRadius))
        // The visual is the downloaded glTF only — it's added by adoptRig once
        // it finishes loading. No procedural placeholder.
    }
    required init?(coder: NSCoder) { nil }

    /// Skinned shadow casting is the single most expensive thing an animated
    /// glTF adds to the frame; a flat contact disc grounds them far cheaper.
    static func disableShadows(_ node: SCNNode) {
        node.enumerateHierarchy { n, _ in n.castsShadow = false }
    }

    // MARK: Clip playback (rigged models)

    /// Play the best-matching clip for the given keywords, looping. Exact matches
    /// win, then the shortest matching key, so plain "idle"/"walk" beat twitchy
    /// variants like "idle_hitreact" or "idle_2_headlow".
    private func play(_ keywords: [String]) {
        guard rigged, !clips.isEmpty else { return }
        var picked: String?
        for kw in keywords {
            if clips[kw] != nil { picked = kw; break }
            let matches = clips.keys.filter { $0.hasPrefix(kw) || $0.contains(kw) }
            if let best = matches.min(by: { $0.count < $1.count }) { picked = best; break }
        }
        guard let key = picked, key != currentClipKey, let player = clips[key] else { return }
        // Make sure nothing else is still playing (SceneKit blends simultaneous
        // players, which looks like the animal spasming), then play just this one.
        for (k, p) in clips where k != key {
            if k == currentClipKey { p.stop(withBlendOutDuration: 0.25) } else { p.stop() }
        }
        player.play()
        currentClipKey = key
    }

    /// Install the loaded glTF model and start the animal living. Called on the
    /// main thread once the asset finished parsing.
    func adoptRig(visual: SCNNode, clips: [String: SCNAnimationPlayer]) {
        guard parent != nil else { return }
        poseNode.removeAllActions()
        poseNode.eulerAngles = SCNVector3Zero
        poseNode.position = SCNVector3Zero
        poseNode.childNodes.forEach { $0.removeFromParentNode() }
        poseNode.addChildNode(visual)
        Self.disableShadows(visual)
        self.clips = clips
        currentClipKey = nil
        play(["idle", "rest"])
        startLiving()
    }

    func place(col: Int, row: Int) {
        self.col = col
        self.row = row
        position = worldFor(col, row)
    }

    /// Keep world position when the island grows: shift the grid coords so the
    /// current in-flight move still lands where the pet already stands.
    func shiftGrid(by delta: Int) {
        col += delta
        row += delta
    }

    /// SceneKit calls action completions on its render thread, but everything
    /// an animal decides reads the town — buildings, decorations, kennels,
    /// bowls — which the main thread edits whenever you build, move or tidy
    /// something away. Two threads on one array crashed the game, so every
    /// completion that leads back into thinking hops to the main thread first.
    private func after(_ action: SCNAction, _ then: @escaping @MainActor () -> Void) {
        runAction(action) {
            Task { @MainActor in then() }
        }
    }

    /// Kick off the endless think-act loop after a small random delay so a herd
    /// doesn't move in lockstep.
    func startLiving() {
        after(.wait(duration: Double.random(in: 0.4...3.0))) { [weak self] in
            self?.behave()
        }
    }

    // MARK: Decision loop

    /// One "turn" is either a whole walking journey (several tiles in a mostly
    /// straight line) or a rest. Deciding per-journey — not per-tile — keeps the
    /// motion calm instead of twitchy.
    private func behave() {
        guard parent != nil, !isCarried else { return }
        let canSeekTarget = Date() >= targetCooldownUntil

        // A full bowl beats everything else — go eat.
        if canSeekTarget, let bowl = findBowl?(self) {
            headTo(bowl.cell, then: { [weak self] in self?.eatFromBowl(at: bowl.world) })
            return
        }

        // After dark, everyone but the night owls turns in. Pets with a doghouse
        // walk home and curl up inside it.
        if isNight(), !kind.isNocturnal, !forcedAwake {
            if canSeekTarget, let bed = findBed?(self) {
                headTo(bed.cell, then: { [weak self] in
                    self?.enterKennel(world: bed.world, yaw: bed.yaw)
                })
            } else {
                sleep()
            }
            return
        }

        if Double.random(in: 0..<1) < effectiveMoveChance {
            startJourney()
        } else {
            idle()
        }
    }

    /// Couldn't reach where it was heading — wait a bit before trying anything
    /// targeted again. Crucially this defers through an action instead of calling
    /// `behave()` straight back, which would recurse until the thread locked up.
    private func abandonTarget() {
        targetCooldownUntil = Date().addingTimeInterval(20)
        after(.wait(duration: 0.5)) { [weak self] in self?.behave() }
    }

    // MARK: Going somewhere on purpose

    /// Walk greedily towards `target`, one tile at a time, then run `arrive`.
    /// Greedy is plenty on an open island and never gets stuck for long: if it
    /// can't get closer it gives up and goes back to wandering.
    private func headTo(_ target: (col: Int, row: Int), steps: Int = 26,
                        then arrive: @escaping () -> Void) {
        guard parent != nil, !isCarried else { return }
        let dist = abs(col - target.col) + abs(row - target.row)
        if dist <= 1 { arrive(); return }
        guard steps > 0 else { abandonTarget(); return }

        let options = walkableDirs().filter { !isWater(col + $0.dx, row + $0.dy) }
        guard let step = options.min(by: {
            abs(col + $0.dx - target.col) + abs(row + $0.dy - target.row)
                < abs(col + $1.dx - target.col) + abs(row + $1.dy - target.row)
        }) else { abandonTarget(); return }

        // Can't get any closer (blocked) → back off instead of retrying forever.
        guard abs(col + step.dx - target.col) + abs(row + step.dy - target.row) < dist else {
            abandonTarget(); return
        }

        play(["walk", "trot"])
        let turned = step.dx != lastDir?.dx || step.dy != lastDir?.dy
        stepTile(step, sprint: false, turned: turned) { [weak self] in
            self?.headTo(target, steps: steps - 1, then: arrive)
        }
    }

    /// Nose into the bowl, munch, then let the scene empty it.
    private func eatFromBowl(at world: SCNVector3) {
        let approach = SCNAction.move(to: SCNVector3(world.x, 0, world.z + 0.35), duration: 0.5)
        approach.timingMode = .easeInEaseOut
        after(.sequence([
            .rotateTo(x: 0, y: CGFloat(atan2(world.x - position.x, world.z - position.z)),
                      z: 0, duration: 0.25, usesShortestUnitArc: true),
            approach,
        ])) { [weak self] in
            guard let self else { return }
            self.play(["eat", "eating", "idle"])
            self.after(.wait(duration: 4.0)) { [weak self] in
                guard let self else { return }
                self.onAteFromBowl?(self)
                self.play(["idle", "rest"])
                self.after(.wait(duration: 0.6)) { [weak self] in self?.behave() }
            }
        }
    }

    /// Settle into the doghouse: slide into the opening, face out, and sleep.
    private func enterKennel(world: SCNVector3, yaw: Float) {
        inKennel = true
        isSleeping = true
        for (_, p) in clips { p.stop(withBlendOutDuration: 0.3) }
        currentClipKey = nil

        let slide = SCNAction.move(to: SCNVector3(world.x, 0, world.z), duration: 0.7)
        slide.timingMode = .easeInEaseOut
        runAction(.sequence([
            .rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.3, usesShortestUnitArc: true),
            slide,
        ])) { [weak self] in
            guard let self else { return }
            // Curl up: settle onto the floor, tuck the legs under by sinking a
            // little, and shrink slightly the way a curled dog actually does.
            let curl = SCNAction.group([
                .move(to: SCNVector3(0, -0.10, 0), duration: 0.55),
                .rotateTo(x: 0.14, y: 0, z: 0, duration: 0.55, usesShortestUnitArc: true),
                .scale(to: 0.88, duration: 0.55),
            ])
            curl.timingMode = .easeInEaseOut
            self.poseNode.runAction(curl)
            self.scheduleWakeCheck()
        }
    }

    // MARK: Sleeping

    private func sleep() {
        isSleeping = true
        // Freeze the rig (cheap) and drop into a low, head-down resting pose.
        for (_, p) in clips { p.stop(withBlendOutDuration: 0.3) }
        currentClipKey = nil
        removeAllActions()
        poseNode.removeAllActions()
        let settle = SCNAction.group([
            .move(to: SCNVector3(0, -0.05, 0), duration: 0.6),
            .rotateTo(x: 0.35, y: 0, z: 0, duration: 0.6, usesShortestUnitArc: true),
        ])
        settle.timingMode = .easeInEaseOut
        poseNode.runAction(settle)
        scheduleWakeCheck()
    }

    /// Re-check now and then: wake naturally when morning comes. A pet sent to
    /// its kennel by hand naps a little longer, then lets itself out — it can
    /// never end up parked in there forever.
    private func scheduleWakeCheck() {
        let delay = commandedNap ? Double.random(in: 60...90) : Double.random(in: 15...30)
        commandedNap = false
        after(.wait(duration: delay)) { [weak self] in
            guard let self else { return }
            if self.isNight(), !self.kind.isNocturnal, !self.forcedAwake {
                self.scheduleWakeCheck()   // still dark — stay put
                return
            }
            self.isSleeping = false
            self.inKennel = false
            self.poseNode.runAction(.group([
                .move(to: SCNVector3Zero, duration: 0.4),
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true),
                .scale(to: 1, duration: 0.4),      // stand back up to full size
            ]))
            self.behave()
        }
    }

    // MARK: Player commands

    /// True while the player is carrying the pet around the map.
    private(set) var isCarried = false

    /// Whether a doghouse is available to be sent to.
    var hasKennel: Bool { findBed?(self) != nil }

    /// "Go to your kennel." During the day it's a nap the pet ends on its own,
    /// so it never gets stuck in there; at night it just turns in early.
    func sendToKennel() {
        guard let bed = findBed?(self) else { Haptics.warning(); return }
        Haptics.tap()
        forcedAwake = false
        commandedNap = true
        removeAllActions()
        poseNode.removeAllActions()
        headTo(bed.cell) { [weak self] in
            self?.enterKennel(world: bed.world, yaw: bed.yaw)
        }
    }

    /// Lifted by the player: freeze in place and hover.
    func beginCarry() {
        isCarried = true
        isSleeping = false
        inKennel = false
        removeAllActions()
        poseNode.removeAllActions()
        poseNode.runAction(.group([
            .move(to: SCNVector3Zero, duration: 0.2),
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.2, usesShortestUnitArc: true),
            .scale(to: 1, duration: 0.2),
        ]))
        play(["idle", "rest"])
        Haptics.pickup()
    }

    /// Put down on a cell and carry on living from there.
    func endCarry(col: Int, row: Int) {
        isCarried = false
        lastDir = nil
        place(col: col, row: row)
        let land = SCNAction.move(to: worldFor(col, row), duration: 0.2)
        land.timingMode = .easeOut
        after(land) { [weak self] in
            self?.after(.wait(duration: 0.3)) { [weak self] in self?.behave() }
        }
        Haptics.drop()
    }

    /// Player tapped a sleeping pet: rouse it and keep it up for a while.
    func wake() {
        guard isSleeping else { return }
        isSleeping = false
        inKennel = false
        forcedAwake = true
        removeAllActions()
        poseNode.removeAllActions()
        let up = SCNAction.group([
            .move(to: SCNVector3Zero, duration: 0.4),
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true),
            .scale(to: 1, duration: 0.4),
        ])
        up.timingMode = .easeOut
        poseNode.runAction(up)
        Haptics.tap()
        play(["idle", "rest"])
        after(.wait(duration: 0.5)) { [weak self] in self?.behave() }
        // Let it doze off again after a minute of being awake.
        runAction(.sequence([.wait(duration: 60), .run { [weak self] _ in
            Task { @MainActor [weak self] in self?.forcedAwake = false }
        }]), forKey: "wakeWindow")
    }

    private var effectiveMoveChance: Double {
        calm ? kind.moveChance * 0.5 : kind.moveChance
    }

    private func walkableDirs() -> [(dx: Int, dy: Int)] {
        [(1, 0), (-1, 0), (0, 1), (0, -1)]
            .filter { isWalkable(col + $0.0, row + $0.1) }
            .map { (dx: $0.0, dy: $0.1) }
    }

    // MARK: Movement (journeys)

    private func startJourney() {
        // Prefer carrying on the way we were headed; otherwise pick a new way.
        var dir: (dx: Int, dy: Int)?
        if let last = lastDir, isWalkable(col + last.dx, row + last.dy),
           Double.random(in: 0..<1) < 0.6 {
            dir = last
        } else {
            var opts = walkableDirs()
            if let last = lastDir, opts.count > 1 {
                opts.removeAll { $0.dx == -last.dx && $0.dy == -last.dy }
            }
            dir = opts.randomElement()
        }
        guard let start = dir else { idle(); return }

        let sprint = !calm && kind.canDash && Double.random(in: 0..<1) < 0.22
        play(sprint ? ["gallop", "run", "sprint", "walk"] : ["walk", "trot"])
        let budget = Int.random(in: sprint ? 4...9 : 3...7)

        // Face the direction once, then stride tile by tile without re-turning.
        lastDir = start
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(yaw(start)), z: 0,
                                      duration: 0.22, usesShortestUnitArc: true)
        after(turn) { [weak self] in self?.advance(dir: start, remaining: budget, sprint: sprint) }
    }

    private func advance(dir: (dx: Int, dy: Int), remaining: Int, sprint: Bool) {
        guard parent != nil, remaining > 0 else { idle(); return }
        guard let step = nextStep(from: dir) else { idle(); return }
        let turned = step.dx != dir.dx || step.dy != dir.dy
        stepTile(step, sprint: sprint, turned: turned) { [weak self] in
            self?.advance(dir: step, remaining: remaining - 1, sprint: sprint)
        }
    }

    /// Mostly keep going straight; turn only when blocked or on the occasional whim.
    private func nextStep(from dir: (dx: Int, dy: Int)) -> (dx: Int, dy: Int)? {
        let straightOK = isWalkable(col + dir.dx, row + dir.dy)
        if straightOK, Double.random(in: 0..<1) > 0.16 { return dir }

        var opts = walkableDirs()
        guard !opts.isEmpty else { return nil }
        // Don't spin around unless it's a dead end.
        if opts.count > 1 { opts.removeAll { $0.dx == -dir.dx && $0.dy == -dir.dy } }
        if straightOK, opts.contains(where: { $0 == dir }), Bool.random() { return dir }
        return opts.randomElement()
    }

    private func stepTile(_ dir: (dx: Int, dy: Int), sprint: Bool, turned: Bool,
                          done: @escaping @MainActor () -> Void) {
        let nc = col + dir.dx, nr = row + dir.dy
        let water = isWater(nc, nr)
        var dur = water ? kind.swimSecondsPerTile : kind.walkSecondsPerTile
        if sprint { dur *= 0.6 }
        let target = worldFor(nc, nr)
        let targetY: Float = water ? -0.12 : 0

        var seq: [SCNAction] = []
        if turned {
            seq.append(.rotateTo(x: 0, y: CGFloat(yaw(dir)), z: 0,
                                 duration: min(0.2, dur * 0.4), usesShortestUnitArc: true))
        }
        let mv = SCNAction.move(to: SCNVector3(target.x, targetY, target.z), duration: dur)
        // Linear when striding straight so consecutive tiles read as one smooth
        // walk; a gentle ease only when we just turned.
        mv.timingMode = turned ? .easeInEaseOut : .linear
        seq.append(mv)

        // The rig plays its own walk cycle, so no procedural bob is needed.
        lastDir = dir
        col = nc; row = nr
        after(.sequence(seq), done)
    }

    /// y-rotation so the model's +Z (its nose) points along the move direction.
    /// Imported models are pre-oriented to +Z inside the loader.
    private func yaw(_ dir: (dx: Int, dy: Int)) -> Float {
        atan2(Float(dir.dx), Float(dir.dy))
    }

    // MARK: Idle behaviours

    /// Settle on a calm idle clip (grazers sometimes eat) and hold it a good
    /// while, so the animal isn't constantly switching poses.
    private func idle() {
        let grazers: Set<AnimalKind> = [.deer, .cow, .horse, .alpaca]
        if grazers.contains(kind), Double.random(in: 0..<1) < 0.4 {
            play(["eat", "graze", "idle"])
        } else {
            play(["idle", "rest"])
        }
        finishIdle(after: Double.random(in: 5...10))
    }

    private func finishIdle(after dur: Double) {
        after(.wait(duration: dur)) { [weak self] in
            self?.after(.wait(duration: 0.3)) { [weak self] in self?.behave() }
        }
    }
}

// MARK: - AnimalModelLoader (rigged glTF assets via GLTFKit2)

#if canImport(GLTFKit2)
import GLTFKit2
#endif

/// Loads a rigged glTF for a kind (bundled as `<assetName>.gltf`, e.g. `shiba.gltf`)
/// and hands back a scaled, grounded, forward-facing node plus its animation clips.
/// Falls back silently to the procedural model when GLTFKit2 or the asset is absent.
enum AnimalModelLoader {

    #if canImport(GLTFKit2)
    /// Parsed assets kept around so a second dog doesn't re-decode shiba.gltf.
    /// Touched only on the main thread.
    private static var assetCache: [AnimalKind: GLTFAsset] = [:]
    #endif

    /// Async because glTF parsing is heavy — the animal shows its procedural
    /// placeholder until the rig is ready, then swaps in.
    static func loadRig(_ kind: AnimalKind,
                        completion: @escaping (_ visual: SCNNode,
                                               _ clips: [String: SCNAnimationPlayer]) -> Void) {
        #if canImport(GLTFKit2)
        if let asset = assetCache[kind] {
            let built = buildScene(from: asset, kind: kind)
            completion(built.0, built.1)
            return
        }
        guard let url = assetURL(for: kind) else { return }
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
            guard status == .complete, let asset = maybeAsset else { return }
            DispatchQueue.main.async {
                assetCache[kind] = asset
                let built = buildScene(from: asset, kind: kind)
                completion(built.0, built.1)
            }
        }
        #endif
    }

    #if canImport(GLTFKit2)
    /// Build a fresh SceneKit node + clips from an already-parsed asset (main thread).
    private static func buildScene(from asset: GLTFAsset, kind: AnimalKind)
        -> (SCNNode, [String: SCNAnimationPlayer]) {
        let source = GLTFSCNSceneSource(asset: asset)
        let container = SCNNode()
        if let scene = source.defaultScene {
            for child in scene.rootNode.childNodes { container.addChildNode(child) }
        }

        // Only genuinely cyclic clips loop; one-shots (death, attack, jump,
        // hit-reacts) stay single-play so they can never breakdance.
        let cyclic: Set<String> = ["idle", "idle_2", "walk", "trot", "gallop", "run", "eating"]
        var clips: [String: SCNAnimationPlayer] = [:]
        for anim in source.animations {
            let key = anim.name.lowercased()
            let player = anim.animationPlayer
            player.animation.repeatCount = cyclic.contains(key) ? .greatestFiniteMagnitude : 1
            container.addAnimationPlayer(player, forKey: anim.name)
            player.stop()
            clips[key] = player
        }

        normalize(container, targetSize: kind.targetSize)
        container.eulerAngles.y = kind.assetFacingYaw
        flatten(container)   // PBR → lambert: much cheaper + matches the town
        return (container, clips)
    }
    #endif

    private static func assetURL(for kind: AnimalKind) -> URL? {
        let name = kind.assetName
        return Bundle.main.url(forResource: name, withExtension: "gltf", subdirectory: "Animals3D")
            ?? Bundle.main.url(forResource: name, withExtension: "gltf")
            ?? Bundle.main.url(forResource: name, withExtension: "glb", subdirectory: "Animals3D")
            ?? Bundle.main.url(forResource: name, withExtension: "glb")
    }

    /// Swap the imported PBR materials for cheap Lambert shading. Quaternius
    /// models are flat-coloured anyway, so we keep the diffuse tint and drop the
    /// costly metalness/roughness/normal work — big GPU saving with 8 animals.
    private static func flatten(_ node: SCNNode) {
        node.enumerateHierarchy { n, _ in
            guard let geo = n.geometry else { return }
            for m in geo.materials {
                m.lightingModel = .lambert
                m.metalness.contents = nil
                m.roughness.contents = nil
                m.normal.contents = nil
                m.emission.contents = nil
                m.clearCoat.contents = nil
            }
        }
    }

    /// Scale the model so its longest horizontal side equals `targetSize` tiles,
    /// then rest its feet on y = 0. Skinned meshes report nothing through
    /// `flattenedClone`, so we union the bind-pose bounds of every geometry node.
    private static func normalize(_ node: SCNNode, targetSize: CGFloat) {
        var lo = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var hi = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        node.enumerateHierarchy { child, _ in
            guard child.geometry != nil else { return }
            let (a, b) = child.boundingBox
            for cx in [a.x, b.x] {
                for cy in [a.y, b.y] {
                    for cz in [a.z, b.z] {
                        let p = node.convertPosition(SCNVector3(cx, cy, cz), from: child)
                        lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); lo.z = min(lo.z, p.z)
                        hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y); hi.z = max(hi.z, p.z)
                    }
                }
            }
        }
        let footprint = CGFloat(max(hi.x - lo.x, hi.z - lo.z))
        guard footprint.isFinite, footprint > 0.0001 else {
            node.scale = SCNVector3(0.12, 0.12, 0.12)   // safe fallback
            return
        }
        let s = Float(targetSize / footprint)
        node.scale = SCNVector3(s, s, s)
        node.position.y = -lo.y * s
    }
}
