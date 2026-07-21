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

    var displayName: String {
        switch self {
        case .dog:    "Pes"
        case .husky:  "Husky"
        case .fox:    "Liška"
        case .wolf:   "Vlk"
        case .deer:   "Srnec"
        case .cow:    "Kráva"
        case .horse:  "Kůň"
        case .alpaca: "Alpaka"
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

    var shopDescription: String {
        switch self {
        case .dog:    "Věrný parťák, občas vyběhne a dovádí"
        case .husky:  "Neposedný severský pes plný energie"
        case .fox:    "Zvědavá liška, čmuchá a klusá kolem"
        case .wolf:   "Tichý vlk, obchází svoje území"
        case .deer:   "Plachý srnec, popásá se na louce"
        case .cow:    "V klidu přežvykuje na louce"
        case .horse:  "Klidný kůň, prochází se mezi domy"
        case .alpaca: "Rozvážná alpaka, pořád v pohodě"
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

    /// No pond-loving species in the current roster.
    var lovesWater: Bool { false }

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

    private(set) var isSleeping = false
    private var forcedAwake = false          // set for a while after the player wakes it

    init(kind: AnimalKind,
         calm: Bool,
         visual: SCNNode,
         clips: [String: SCNAnimationPlayer],
         isWalkable: @escaping (Int, Int) -> Bool,
         isWater: @escaping (Int, Int) -> Bool,
         worldFor: @escaping (Int, Int) -> SCNVector3,
         isNight: @escaping () -> Bool = { false }) {
        self.kind = kind
        self.calm = calm
        self.clips = clips
        self.isWalkable = isWalkable
        self.isWater = isWater
        self.worldFor = worldFor
        self.isNight = isNight
        super.init()
        addChildNode(poseNode)
        poseNode.addChildNode(visual)
        Self.disableShadows(visual)
        addChildNode(contactShadowNode(radius: kind.shadowRadius))
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

    /// Swap the procedural placeholder for a loaded rigged model once its glTF
    /// finished parsing. Called on the main thread.
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

    /// Kick off the endless think-act loop after a small random delay so a herd
    /// doesn't move in lockstep.
    func startLiving() {
        runAction(.wait(duration: Double.random(in: 0.4...3.0))) { [weak self] in
            self?.behave()
        }
    }

    // MARK: Decision loop

    /// One "turn" is either a whole walking journey (several tiles in a mostly
    /// straight line) or a rest. Deciding per-journey — not per-tile — keeps the
    /// motion calm instead of twitchy.
    private func behave() {
        guard parent != nil else { return }
        // After dark, everyone but the night owls curls up — unless the player
        // just woke them.
        if isNight(), !kind.isNocturnal, !forcedAwake {
            sleep()
            return
        }
        if Double.random(in: 0..<1) < effectiveMoveChance {
            startJourney()
        } else {
            idle()
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
        // Re-check occasionally: wake naturally when morning comes.
        runAction(.wait(duration: Double.random(in: 15...30))) { [weak self] in
            self?.isSleeping = false
            self?.behave()
        }
    }

    /// Player tapped a sleeping pet: rouse it and keep it up for a while.
    func wake() {
        guard isSleeping else { return }
        isSleeping = false
        forcedAwake = true
        removeAllActions()
        poseNode.removeAllActions()
        let up = SCNAction.group([
            .move(to: SCNVector3Zero, duration: 0.4),
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true),
        ])
        up.timingMode = .easeOut
        poseNode.runAction(up)
        Haptics.tap()
        play(["idle", "rest"])
        runAction(.wait(duration: 0.5)) { [weak self] in self?.behave() }
        // Let it doze off again after a minute of being awake.
        runAction(.sequence([.wait(duration: 60), .run { [weak self] _ in self?.forcedAwake = false }]),
                  forKey: "wakeWindow")
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
        runAction(turn) { [weak self] in self?.advance(dir: start, remaining: budget, sprint: sprint) }
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
                          done: @escaping () -> Void) {
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

        applyGait(dur: dur, water: water)
        lastDir = dir
        col = nc; row = nr
        runAction(.sequence(seq), completionHandler: done)
    }

    private func applyGait(dur: Double, water: Bool) {
        // The rig plays its own walk cycle; only the procedural model needs a bob.
        guard !rigged else { return }
        let amp: CGFloat = water ? 0.04 : 0.03
        let up = SCNAction.moveBy(x: 0, y: amp, z: 0, duration: dur / 2); up.timingMode = .easeInEaseOut
        let dn = SCNAction.moveBy(x: 0, y: -amp, z: 0, duration: dur / 2); dn.timingMode = .easeInEaseOut
        poseNode.runAction(.sequence([up, dn]))
    }

    /// y-rotation so the model's +Z (its nose) points along the move direction.
    /// Imported models are pre-oriented to +Z inside the loader.
    private func yaw(_ dir: (dx: Int, dy: Int)) -> Float {
        atan2(Float(dir.dx), Float(dir.dy))
    }

    // MARK: Idle behaviours

    private func idle() {
        if rigged {
            riggedIdle()
            return
        }
        if calm {
            [{ self.bRest() }, { self.bGraze() }].randomElement()!()
            return
        }
        let repertoire: [() -> Void]
        switch kind {
        case .dog, .husky: repertoire = [bPlay, bSit, bSniff, bRest]
        case .fox:         repertoire = [bSniff, bSit, bPlay, bRest]
        case .wolf:        repertoire = [bSit, bSniff, bRest, bSleep]
        case .deer:        repertoire = [bGraze, bRest, bSniff, bGraze]
        case .cow:         repertoire = [bGraze, bRest, bChew, bSleep]
        case .horse:       repertoire = [bGraze, bRest, bChew, bSniff]
        case .alpaca:      repertoire = [bGraze, bRest, bChew, bRest]
        }
        repertoire.randomElement()!()
    }

    /// For imported models: settle on a calm idle (grazers sometimes eat) and
    /// hold it a good while, so the animal isn't constantly switching poses.
    private func riggedIdle() {
        let grazers: Set<AnimalKind> = [.deer, .cow, .horse, .alpaca]
        if grazers.contains(kind), Double.random(in: 0..<1) < 0.4 {
            play(["eat", "graze", "idle"])
        } else {
            play(["idle", "rest"])
        }
        finishIdle(after: Double.random(in: 5...10))
    }

    private func finishIdle(after dur: Double, restore: @escaping () -> Void = {}) {
        runAction(.wait(duration: dur)) { [weak self] in
            restore()
            self?.runAction(.wait(duration: 0.3)) { [weak self] in self?.behave() }
        }
    }

    private func resetPose(_ d: Double = 0.4) {
        poseNode.removeAllActions()
        poseNode.runAction(.group([
            .rotateTo(x: 0, y: 0, z: 0, duration: d, usesShortestUnitArc: true),
            .move(to: SCNVector3Zero, duration: d),
        ]))
    }

    private func bSleep() {
        poseNode.runAction(.rotateTo(x: 0.55, y: 0, z: 0, duration: 0.6, usesShortestUnitArc: true))
        poseNode.runAction(.moveBy(x: 0, y: -0.05, z: 0.04, duration: 0.6))
        finishIdle(after: Double.random(in: 6...11)) { [weak self] in self?.resetPose(0.5) }
    }

    private func bRest() {
        poseNode.runAction(.rotateTo(x: 0.28, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true))
        poseNode.runAction(.moveBy(x: 0, y: -0.03, z: 0, duration: 0.4))
        finishIdle(after: Double.random(in: 3...6)) { [weak self] in self?.resetPose() }
    }

    private func bChew() {
        let chew = SCNAction.sequence([
            .rotateBy(x: 0.06, y: 0, z: 0, duration: 0.25),
            .rotateBy(x: -0.06, y: 0, z: 0, duration: 0.25),
        ])
        poseNode.runAction(.repeatForever(chew))
        finishIdle(after: Double.random(in: 4...7)) { [weak self] in self?.resetPose(0.3) }
    }

    private func bGraze() {
        let dip = SCNAction.sequence([
            .rotateTo(x: 0.62, y: 0, z: 0, duration: 0.5, usesShortestUnitArc: true),
            .wait(duration: 0.7),
            .rotateTo(x: 0.25, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true),
            .wait(duration: 0.35),
        ])
        poseNode.runAction(.repeatForever(dip))
        finishIdle(after: Double.random(in: 4...8)) { [weak self] in self?.resetPose(0.3) }
    }

    private func bSniff() {
        let sniff = SCNAction.sequence([
            .rotateTo(x: 0.38, y: 0, z: 0, duration: 0.3, usesShortestUnitArc: true),
            .rotateTo(x: 0.15, y: 0, z: 0, duration: 0.3, usesShortestUnitArc: true),
        ])
        poseNode.runAction(.repeat(sniff, count: 4))
        finishIdle(after: 2.5) { [weak self] in self?.resetPose(0.3) }
    }

    private func bGroom() {
        poseNode.runAction(.rotateTo(x: -0.12, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true))
        let lick = SCNAction.sequence([
            .rotateBy(x: 0, y: 0.18, z: 0, duration: 0.18),
            .rotateBy(x: 0, y: -0.36, z: 0, duration: 0.36),
            .rotateBy(x: 0, y: 0.18, z: 0, duration: 0.18),
        ])
        poseNode.runAction(.repeat(lick, count: 3))
        finishIdle(after: 2.6) { [weak self] in self?.resetPose(0.3) }
    }

    private func bPlay() {
        // A happy spin plus a couple of bounces.
        runAction(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.7))
        let up = SCNAction.moveBy(x: 0, y: 0.14, z: 0, duration: 0.2); up.timingMode = .easeOut
        let dn = SCNAction.moveBy(x: 0, y: -0.14, z: 0, duration: 0.2); dn.timingMode = .easeIn
        poseNode.runAction(.repeat(.sequence([up, dn]), count: 2))
        finishIdle(after: 1.1)
    }

    private func bHop() {
        let up = SCNAction.moveBy(x: 0, y: 0.16, z: 0, duration: 0.22); up.timingMode = .easeOut
        let dn = SCNAction.moveBy(x: 0, y: -0.16, z: 0, duration: 0.22); dn.timingMode = .easeIn
        poseNode.runAction(.repeat(.sequence([up, dn]), count: 2))
        finishIdle(after: 1.2)
    }

    private func bNudge() {
        let jab = SCNAction.sequence([
            .rotateTo(x: 0.42, y: 0, z: 0, duration: 0.14, usesShortestUnitArc: true),
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.14, usesShortestUnitArc: true),
        ])
        poseNode.runAction(.repeat(jab, count: 2))
        finishIdle(after: 1.0)
    }

    private func bFreeze() {
        // Ears up, dead still — classic rabbit alert.
        poseNode.runAction(.moveBy(x: 0, y: 0.03, z: 0, duration: 0.2))
        finishIdle(after: Double.random(in: 1.5...2.8)) { [weak self] in self?.resetPose(0.25) }
    }

    private func bSit() {
        poseNode.runAction(.rotateTo(x: -0.18, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true))
        finishIdle(after: Double.random(in: 3...5)) { [weak self] in self?.resetPose() }
    }

    private func bHunt() {
        // Crouch, wiggle, then a little pounce.
        poseNode.runAction(.moveBy(x: 0, y: -0.05, z: 0, duration: 0.4))
        let wiggle = SCNAction.sequence([
            .rotateBy(x: 0, y: 0.12, z: 0, duration: 0.12),
            .rotateBy(x: 0, y: -0.24, z: 0, duration: 0.24),
            .rotateBy(x: 0, y: 0.12, z: 0, duration: 0.12),
        ])
        poseNode.runAction(.repeat(wiggle, count: 2))
        finishIdle(after: 1.6) { [weak self] in
            guard let self else { return }
            let pounce = SCNAction.sequence([
                .moveBy(x: 0, y: 0.14, z: 0.12, duration: 0.18),
                .moveBy(x: 0, y: -0.09, z: -0.12, duration: 0.18),
            ])
            self.poseNode.runAction(pounce)
            self.resetPose(0.4)
        }
    }

    private func bWash() {
        poseNode.runAction(.rotateTo(x: -0.16, y: 0, z: 0, duration: 0.4, usesShortestUnitArc: true))
        let shake = SCNAction.sequence([
            .moveBy(x: 0, y: 0.02, z: 0, duration: 0.1),
            .moveBy(x: 0, y: -0.02, z: 0, duration: 0.1),
        ])
        poseNode.runAction(.repeat(shake, count: 8))
        finishIdle(after: 2.4) { [weak self] in self?.resetPose(0.3) }
    }
}

// MARK: - AnimalFactory (rounded low-poly critters, all facing +Z)

enum AnimalFactory {

    static func node(for kind: AnimalKind) -> SCNNode {
        switch kind {
        case .dog:    return dog()
        case .husky:  return husky()
        case .fox:    return fox()
        case .wolf:   return wolf()
        case .deer:   return deer()
        case .cow:    return cow()
        case .horse:  return horse()
        case .alpaca: return alpaca()
        }
    }

    // MARK: Primitives

    typealias C = (CGFloat, CGFloat, CGFloat)

    private static let nose: C = (0.12, 0.10, 0.11)
    private static let eyeC: C = (0.10, 0.10, 0.12)

    private static func mat(_ c: C) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        m.lightingModel = .lambert
        return m
    }

    @discardableResult
    private static func node(_ parent: SCNNode, _ g: SCNGeometry, _ c: C,
                             x: CGFloat = 0, y: CGFloat, z: CGFloat = 0,
                             pitch: CGFloat = 0, yaw: CGFloat = 0, roll: CGFloat = 0,
                             sx: CGFloat = 1, sy: CGFloat = 1, sz: CGFloat = 1) -> SCNNode {
        g.firstMaterial = mat(c)
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y, z)
        n.eulerAngles = SCNVector3(pitch, yaw, roll)
        n.scale = SCNVector3(sx, sy, sz)
        parent.addChildNode(n)
        return n
    }

    /// Rounded torso: a capsule lying along +Z (head end at +z).
    @discardableResult
    private static func torso(_ parent: SCNNode, r: CGFloat, len: CGFloat, _ c: C,
                              y: CGFloat, z: CGFloat = 0) -> SCNNode {
        node(parent, SCNCapsule(capRadius: r, height: len), c, y: y, z: z, pitch: .pi / 2)
    }

    /// Round head, gently flattened.
    @discardableResult
    private static func head(_ parent: SCNNode, _ r: CGFloat, _ c: C,
                             y: CGFloat, z: CGFloat) -> SCNNode {
        node(parent, SCNSphere(radius: r), c, y: y, z: z, sy: 0.92)
    }

    @discardableResult
    private static func ball(_ parent: SCNNode, _ r: CGFloat, _ c: C,
                             x: CGFloat = 0, y: CGFloat, z: CGFloat = 0,
                             sx: CGFloat = 1, sy: CGFloat = 1, sz: CGFloat = 1) -> SCNNode {
        node(parent, SCNSphere(radius: r), c, x: x, y: y, z: z, sx: sx, sy: sy, sz: sz)
    }

    @discardableResult
    private static func box(_ parent: SCNNode, _ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ c: C,
                            x: CGFloat = 0, y: CGFloat, z: CGFloat = 0,
                            pitch: CGFloat = 0, roll: CGFloat = 0, chamfer: CGFloat = 0.03) -> SCNNode {
        node(parent, SCNBox(width: w, height: h, length: l, chamferRadius: chamfer), c,
             x: x, y: y, z: z, pitch: pitch, roll: roll)
    }

    @discardableResult
    private static func coneNode(_ parent: SCNNode, _ r: CGFloat, _ h: CGFloat, _ c: C,
                                 x: CGFloat = 0, y: CGFloat, z: CGFloat = 0, pitch: CGFloat = 0) -> SCNNode {
        node(parent, SCNCone(topRadius: 0, bottomRadius: r, height: h), c, x: x, y: y, z: z, pitch: pitch)
    }

    /// Four soft rounded legs (capsules), feet planted at y = 0.
    private static func legs(_ parent: SCNNode, spanX: CGFloat, spanZ: CGFloat,
                             h: CGFloat, r: CGFloat, _ c: C) {
        for sx in [-1.0, 1.0] as [CGFloat] {
            for sz in [-1.0, 1.0] as [CGFloat] {
                node(parent, SCNCapsule(capRadius: r, height: h + r), c,
                     x: sx * spanX, y: (h + r) / 2 - r * 0.4, z: sz * spanZ)
            }
        }
    }

    private static func eyes(_ parent: SCNNode, spanX: CGFloat, y: CGFloat, z: CGFloat, r: CGFloat = 0.02) {
        for sx in [-1.0, 1.0] as [CGFloat] {
            // white catch-light + dark pupil for a friendlier face
            ball(parent, r, eyeC, x: sx * spanX, y: y, z: z)
            ball(parent, r * 0.4, (0.95, 0.95, 0.97), x: sx * spanX - r * 0.3, y: y + r * 0.3, z: z + r * 0.7)
        }
    }

    // MARK: Animals

    private static func dog() -> SCNNode {
        let root = SCNNode()
        let coat: C = (0.63, 0.45, 0.27), light: C = (0.80, 0.65, 0.44), dark: C = (0.46, 0.31, 0.18)
        let legH: CGFloat = 0.12
        legs(root, spanX: 0.085, spanZ: 0.13, h: legH, r: 0.032, light)
        let bodyY = legH + 0.11
        torso(root, r: 0.115, len: 0.4, coat, y: bodyY, z: -0.02)
        ball(root, 0.11, light, y: bodyY - 0.03, z: 0.12, sz: 1.2)       // chest/belly
        let headY = bodyY + 0.11, headZ: CGFloat = 0.26
        head(root, 0.115, coat, y: headY, z: headZ)
        ball(root, 0.07, light, y: headY - 0.035, z: headZ + 0.08, sz: 1.1)   // muzzle
        ball(root, 0.026, nose, y: headY - 0.015, z: headZ + 0.15)
        eyes(root, spanX: 0.05, y: headY + 0.035, z: headZ + 0.085, r: 0.019)
        // floppy ears
        box(root, 0.05, 0.11, 0.03, dark, x: -0.1, y: headY + 0.02, z: headZ - 0.02, roll: 0.25, chamfer: 0.025)
        box(root, 0.05, 0.11, 0.03, dark, x: 0.1, y: headY + 0.02, z: headZ - 0.02, roll: -0.25, chamfer: 0.025)
        // wagging tail up
        node(root, SCNCapsule(capRadius: 0.03, height: 0.16), coat, y: bodyY + 0.06, z: -0.22, pitch: 0.7)
        return root
    }

    private static func husky() -> SCNNode {
        let root = SCNNode()
        let coat: C = (0.52, 0.57, 0.63), white: C = (0.95, 0.96, 0.97), dark: C = (0.26, 0.28, 0.32)
        let legH: CGFloat = 0.13
        legs(root, spanX: 0.085, spanZ: 0.13, h: legH, r: 0.033, white)
        let bodyY = legH + 0.11
        torso(root, r: 0.115, len: 0.4, coat, y: bodyY, z: -0.02)
        ball(root, 0.11, white, y: bodyY - 0.03, z: 0.12, sz: 1.2)
        let headY = bodyY + 0.11, headZ: CGFloat = 0.26
        head(root, 0.115, coat, y: headY, z: headZ)
        ball(root, 0.08, white, y: headY - 0.03, z: headZ + 0.07, sz: 1.1)   // white mask/muzzle
        ball(root, 0.026, nose, y: headY - 0.01, z: headZ + 0.15)
        eyes(root, spanX: 0.05, y: headY + 0.035, z: headZ + 0.085, r: 0.019)
        // erect pointed ears
        coneNode(root, 0.045, 0.1, coat, x: -0.06, y: headY + 0.11, z: headZ - 0.02)
        coneNode(root, 0.045, 0.1, coat, x: 0.06, y: headY + 0.11, z: headZ - 0.02)
        // tightly curled tail
        node(root, SCNCapsule(capRadius: 0.035, height: 0.18), white, y: bodyY + 0.09, z: -0.2, pitch: 1.1)
        return root
    }

    private static func fox() -> SCNNode {
        let root = SCNNode()
        let coat: C = (0.85, 0.48, 0.24), white: C = (0.96, 0.95, 0.92), dark: C = (0.16, 0.14, 0.14)
        let legH: CGFloat = 0.1
        legs(root, spanX: 0.06, spanZ: 0.1, h: legH, r: 0.024, dark)         // black socks
        let bodyY = legH + 0.085
        torso(root, r: 0.085, len: 0.32, coat, y: bodyY, z: -0.02)
        ball(root, 0.08, white, y: bodyY - 0.02, z: 0.12, sz: 1.1)
        let headY = bodyY + 0.08, headZ: CGFloat = 0.2
        head(root, 0.09, coat, y: headY, z: headZ)
        ball(root, 0.05, white, y: headY - 0.03, z: headZ + 0.07, sz: 1.2)   // white cheeks/snout
        ball(root, 0.018, dark, y: headY - 0.015, z: headZ + 0.12)
        eyes(root, spanX: 0.04, y: headY + 0.025, z: headZ + 0.07, r: 0.016)
        // big pointy ears with dark tips
        coneNode(root, 0.045, 0.11, coat, x: -0.055, y: headY + 0.12, z: headZ - 0.02)
        coneNode(root, 0.045, 0.11, coat, x: 0.055, y: headY + 0.12, z: headZ - 0.02)
        coneNode(root, 0.022, 0.045, dark, x: -0.055, y: headY + 0.2, z: headZ - 0.02)
        coneNode(root, 0.022, 0.045, dark, x: 0.055, y: headY + 0.2, z: headZ - 0.02)
        // bushy tail with a white tip
        node(root, SCNCapsule(capRadius: 0.06, height: 0.24), coat, y: bodyY + 0.02, z: -0.24, pitch: -0.55)
        ball(root, 0.055, white, y: bodyY - 0.03, z: -0.34)
        return root
    }

    private static func wolf() -> SCNNode {
        let root = SCNNode()
        let coat: C = (0.50, 0.52, 0.56), pale: C = (0.72, 0.72, 0.74), dark: C = (0.30, 0.31, 0.34)
        let legH: CGFloat = 0.15
        legs(root, spanX: 0.09, spanZ: 0.14, h: legH, r: 0.032, dark)
        let bodyY = legH + 0.115
        torso(root, r: 0.115, len: 0.44, coat, y: bodyY, z: -0.02)
        ball(root, 0.11, pale, y: bodyY - 0.03, z: 0.13, sz: 1.15)
        let headY = bodyY + 0.09, headZ: CGFloat = 0.28
        head(root, 0.11, coat, y: headY, z: headZ)
        ball(root, 0.075, pale, y: headY - 0.035, z: headZ + 0.08, sz: 1.2)  // muzzle
        ball(root, 0.026, nose, y: headY - 0.02, z: headZ + 0.16)
        eyes(root, spanX: 0.05, y: headY + 0.025, z: headZ + 0.09, r: 0.018)
        coneNode(root, 0.045, 0.09, coat, x: -0.06, y: headY + 0.1, z: headZ - 0.02)
        coneNode(root, 0.045, 0.09, coat, x: 0.06, y: headY + 0.1, z: headZ - 0.02)
        // low bushy tail
        node(root, SCNCapsule(capRadius: 0.055, height: 0.26), coat, y: bodyY - 0.06, z: -0.26, pitch: -0.3)
        return root
    }

    private static func deer() -> SCNNode {
        let root = SCNNode()
        let coat: C = (0.66, 0.47, 0.30), pale: C = (0.92, 0.87, 0.78), antler: C = (0.55, 0.44, 0.30)
        let legH: CGFloat = 0.19
        legs(root, spanX: 0.075, spanZ: 0.13, h: legH, r: 0.022, (0.5, 0.36, 0.24))
        let bodyY = legH + 0.09
        torso(root, r: 0.095, len: 0.34, coat, y: bodyY, z: -0.02)
        ball(root, 0.088, pale, y: bodyY - 0.03, z: 0.1, sz: 1.05)
        // upright neck reaching a small head
        node(root, SCNCapsule(capRadius: 0.05, height: 0.2), coat, y: bodyY + 0.11, z: 0.16, pitch: -0.5)
        let headY = bodyY + 0.24, headZ: CGFloat = 0.26
        head(root, 0.07, coat, y: headY, z: headZ)
        ball(root, 0.04, pale, y: headY - 0.02, z: headZ + 0.05)
        ball(root, 0.016, nose, y: headY - 0.01, z: headZ + 0.085)
        eyes(root, spanX: 0.035, y: headY + 0.015, z: headZ + 0.05, r: 0.014)
        // big ears
        box(root, 0.045, 0.08, 0.02, coat, x: -0.07, y: headY + 0.04, z: headZ - 0.02, roll: 0.5, chamfer: 0.02)
        box(root, 0.045, 0.08, 0.02, coat, x: 0.07, y: headY + 0.04, z: headZ - 0.02, roll: -0.5, chamfer: 0.02)
        // simple branchy antlers
        for sx in [-1.0, 1.0] as [CGFloat] {
            coneNode(root, 0.017, 0.12, antler, x: sx * 0.04, y: headY + 0.1, z: headZ - 0.01, pitch: -0.2)
            coneNode(root, 0.01, 0.06, antler, x: sx * 0.07, y: headY + 0.16, z: headZ, pitch: -0.7)
        }
        ball(root, 0.03, pale, y: bodyY + 0.03, z: -0.18)   // short tail
        return root
    }

    private static func horse() -> SCNNode {
        let root = SCNNode()
        let coat: C = (0.46, 0.32, 0.22), mane: C = (0.25, 0.17, 0.11), pale: C = (0.55, 0.40, 0.28)
        let legH: CGFloat = 0.22
        legs(root, spanX: 0.09, spanZ: 0.16, h: legH, r: 0.03, (0.30, 0.22, 0.16))
        let bodyY = legH + 0.11
        torso(root, r: 0.12, len: 0.46, coat, y: bodyY, z: -0.02)
        ball(root, 0.11, pale, y: bodyY - 0.04, z: 0.12, sz: 1.1)
        // arched neck + long head
        node(root, SCNCapsule(capRadius: 0.06, height: 0.24), coat, y: bodyY + 0.13, z: 0.18, pitch: -0.55)
        let headY = bodyY + 0.26, headZ: CGFloat = 0.32
        node(root, SCNCapsule(capRadius: 0.05, height: 0.14), coat, y: headY, z: headZ, pitch: 1.2)
        ball(root, 0.03, nose, y: headY - 0.05, z: headZ + 0.08)
        eyes(root, spanX: 0.045, y: headY + 0.03, z: headZ + 0.02, r: 0.016)
        box(root, 0.03, 0.06, 0.02, coat, x: -0.05, y: headY + 0.08, z: headZ - 0.05, chamfer: 0.015)
        box(root, 0.03, 0.06, 0.02, coat, x: 0.05, y: headY + 0.08, z: headZ - 0.05, chamfer: 0.015)
        // mane down the neck
        for i in 0..<5 {
            box(root, 0.02, 0.07, 0.05, mane, y: bodyY + 0.14 + CGFloat(i) * 0.02, z: 0.1 + CGFloat(i) * 0.03, chamfer: 0.01)
        }
        node(root, SCNCapsule(capRadius: 0.035, height: 0.26), mane, y: bodyY - 0.02, z: -0.26, pitch: -0.25)   // tail
        return root
    }

    private static func alpaca() -> SCNNode {
        let root = SCNNode()
        let wool: C = (0.85, 0.77, 0.65), face: C = (0.60, 0.50, 0.40)
        let legH: CGFloat = 0.19
        legs(root, spanX: 0.075, spanZ: 0.12, h: legH, r: 0.028, face)
        let bodyY = legH + 0.1
        // fluffy body from clustered spheres
        ball(root, 0.13, wool, y: bodyY, z: -0.02, sz: 1.2)
        ball(root, 0.09, wool, x: -0.08, y: bodyY + 0.03, z: 0.05)
        ball(root, 0.09, wool, x: 0.08, y: bodyY + 0.03, z: -0.05)
        // long fluffy neck (stacked puffs)
        for i in 0..<3 {
            ball(root, 0.06 - CGFloat(i) * 0.006, wool,
                 y: bodyY + 0.1 + CGFloat(i) * 0.075, z: 0.12 + CGFloat(i) * 0.02)
        }
        let headY = bodyY + 0.32, headZ: CGFloat = 0.18
        head(root, 0.062, face, y: headY, z: headZ)
        ball(root, 0.04, face, y: headY - 0.015, z: headZ + 0.04)
        ball(root, 0.014, nose, y: headY - 0.01, z: headZ + 0.07)
        eyes(root, spanX: 0.03, y: headY + 0.015, z: headZ + 0.045, r: 0.015)
        coneNode(root, 0.018, 0.05, wool, x: -0.03, y: headY + 0.07, z: headZ - 0.02)   // little ears
        coneNode(root, 0.018, 0.05, wool, x: 0.03, y: headY + 0.07, z: headZ - 0.02)
        return root
    }

    private static func cow() -> SCNNode {
        let root = SCNNode()
        let white: C = (0.95, 0.95, 0.94), black: C = (0.20, 0.20, 0.22), pink: C = (0.93, 0.68, 0.70)
        let legH: CGFloat = 0.13
        legs(root, spanX: 0.11, spanZ: 0.16, h: legH, r: 0.04, black)
        let bodyY = legH + 0.14
        torso(root, r: 0.16, len: 0.48, white, y: bodyY, z: -0.02)
        ball(root, 0.15, white, y: bodyY - 0.04, z: 0.12, sz: 1.1)
        // black patches
        ball(root, 0.1, black, x: 0.07, y: bodyY + 0.08, z: 0.06, sz: 1.2)
        ball(root, 0.09, black, x: -0.1, y: bodyY + 0.02, z: -0.14)
        let headY = bodyY + 0.03, headZ: CGFloat = 0.32
        head(root, 0.12, white, y: headY, z: headZ)
        ball(root, 0.09, pink, y: headY - 0.05, z: headZ + 0.08, sx: 1.2, sy: 0.8)   // muzzle
        ball(root, 0.02, (0.7, 0.45, 0.48), x: -0.035, y: headY - 0.045, z: headZ + 0.13)
        ball(root, 0.02, (0.7, 0.45, 0.48), x: 0.035, y: headY - 0.045, z: headZ + 0.13)
        eyes(root, spanX: 0.06, y: headY + 0.04, z: headZ + 0.08, r: 0.019)
        // ears + little horns
        box(root, 0.07, 0.03, 0.05, white, x: -0.12, y: headY + 0.03, z: headZ - 0.03, roll: 0.4, chamfer: 0.02)
        box(root, 0.07, 0.03, 0.05, white, x: 0.12, y: headY + 0.03, z: headZ - 0.03, roll: -0.4, chamfer: 0.02)
        coneNode(root, 0.022, 0.05, (0.9, 0.87, 0.8), x: -0.05, y: headY + 0.11, z: headZ - 0.02)
        coneNode(root, 0.022, 0.05, (0.9, 0.87, 0.8), x: 0.05, y: headY + 0.11, z: headZ - 0.02)
        // udder + tufted tail
        ball(root, 0.06, pink, y: legH + 0.04, z: -0.08, sy: 0.8)
        node(root, SCNCapsule(capRadius: 0.022, height: 0.24), black, y: bodyY, z: -0.26, pitch: -0.3)
        return root
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
