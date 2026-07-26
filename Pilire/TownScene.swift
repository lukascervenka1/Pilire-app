import SceneKit
import SwiftUI

// MARK: - TownScene — 3D low-poly town (SceneKit)
//
// Floating grass island, orthographic isometric camera, one warm sun with
// soft shadows. Buildings are compositions of chamfered boxes/pyramids/cones
// in a muted pastel palette — the light does the work, not outlines.

final class TownScene: NSObject {

    static let tile: CGFloat = 1.0
    static func mapSize(forTier tier: Int) -> Int { 12 + tier * 4 }   // 12 → 16 → 20 → 24

    /// Current map size (dynamic — grows with expansion tier).
    private(set) var cols: Int = 12
    var rows: Int { cols }

    // Callbacks (same API as the old 2D scene)
    var onBuildingTapped: ((BuildingNode) -> Void)?
    var onDecorationTapped: ((DecorationNode) -> Void)?
    var onAnimalTapped: ((AnimalNode) -> Void)?    // tap → pet actions
    var onTileTapped: ((Int, Int) -> Void)?

    /// While placing small greenery, taps snap to the closest of the tile's five
    /// anchors (centre + four corners) and report through `onAnchorTapped`.
    var placingUsesAnchors = false {
        didSet { if isPlacementMode { showPlacementHints(true) } }   // redraw with corner dots
    }
    var onAnchorTapped: ((Anchor) -> Void)?
    /// Ground point of the last placement tap, so the handler can fall back to
    /// the next-closest free anchor when the tapped one is taken.
    private(set) var lastAnchorPoint: SCNVector3?
    var isPlacementMode = false {
        didSet { showPlacementHints(isPlacementMode || draggedNode != nil) }
    }

    /// Road painting: while active, the pan gesture paints road tiles under the
    /// finger instead of moving the camera. `onPaintCell` fires once per cell.
    var isRoadPaintMode = false
    var onPaintCell: ((Int, Int) -> Void)?
    private var lastPaintedCell: (col: Int, row: Int)?

    private(set) var buildingNodes: [BuildingNode] = []
    private(set) var decorationNodes: [DecorationNode] = []
    private(set) var animalNodes: [AnimalNode] = []

    let scnScene = SCNScene()
    weak var scnView: SCNView?

    private let cameraRig  = SCNNode()
    private let cameraNode = SCNNode()

    // Drag state
    private var draggedNode: (SCNNode & GridOccupant)?
    private var draggedAnimal: AnimalNode?
    private var dragOffset  = SCNVector3Zero
    private var ghostNode: SCNNode?
    private var islandNode: SCNNode?
    private var hintsNode: SCNNode?
    var cameraPanEnabled = true

    // Ambient life
    private var sunLight: SCNLight?
    private var ambLight: SCNLight?
    private(set) var weather: TownWeather = .sunny
    private(set) var daylight: DaylightPhase = .day

    override init() {
        super.init()
        setupLights()
        setupCamera()
        buildIsland()
        scatterGroundDetails()
        applyDaylight()
        applyWeather()
        setupClouds()
        setupBirds()
        setupButterflies()
        setupFireflies()
    }

    // MARK: - Grid math

    func gridToWorld(col: Int, row: Int) -> SCNVector3 {
        let c = Float(cols - 1) / 2
        return SCNVector3(Float(col) - c, 0, Float(row) - c)
    }

    func worldToGrid(_ p: SCNVector3) -> (col: Int, row: Int) {
        let c = Float(cols - 1) / 2
        return (Int((p.x + c).rounded()), Int((p.z + c).rounded()))
    }

    // MARK: - Corner anchors (second lattice for small greenery)

    /// Where a decoration sits: the centre of a tile, or a corner shared by the
    /// four tiles around it. Corner indices run 0…cols in both axes.
    enum Anchor {
        case tile(col: Int, row: Int)
        case corner(cx: Int, cy: Int)
    }

    /// World position of corner (cx, cy) — half a tile "before" tile (cx, cy).
    func cornerToWorld(cx: Int, cy: Int) -> SCNVector3 {
        let c = Float(cols - 1) / 2
        return SCNVector3(Float(cx) - c - 0.5, 0, Float(cy) - c - 0.5)
    }

    /// Snap a ground point to whichever of the 5 anchors of the tile under it is
    /// closest: the tile centre, or one of its four corners.
    func nearestAnchor(to p: SCNVector3) -> Anchor {
        anchorsByDistance(to: p).first ?? .tile(col: worldToGrid(p).col, row: worldToGrid(p).row)
    }

    /// Every anchor of the tile under `p` (its centre plus all four corners),
    /// nearest first. Placement walks this list so tapping beside something
    /// already occupied lands on the closest free spot instead of refusing.
    func anchorsByDistance(to p: SCNVector3) -> [Anchor] {
        let c = Float(cols - 1) / 2
        let tile = worldToGrid(p)
        let cx = Int((p.x + c + 0.5).rounded())
        let cy = Int((p.z + c + 0.5).rounded())

        var candidates: [Anchor] = [.tile(col: tile.col, row: tile.row)]
        for dx in 0...1 {
            for dy in 0...1 {
                candidates.append(.corner(cx: tile.col + dx, cy: tile.row + dy))
            }
        }
        // Keep the corner under the finger first among equals.
        candidates.append(.corner(cx: cx, cy: cy))

        func world(_ a: Anchor) -> SCNVector3 {
            switch a {
            case let .tile(col, row):   gridToWorld(col: col, row: row)
            case let .corner(cx, cy):   cornerToWorld(cx: cx, cy: cy)
            }
        }
        func d2(_ a: Anchor) -> Float {
            let w = world(a)
            let dx = w.x - p.x, dz = w.z - p.z
            return dx * dx + dz * dz
        }
        // De-duplicate (the extra corner may repeat) and sort by distance.
        var seen = Set<String>()
        return candidates.filter { a in
            let key: String
            switch a {
            case let .tile(col, row): key = "t\(col),\(row)"
            case let .corner(cx, cy): key = "c\(cx),\(cy)"
            }
            return seen.insert(key).inserted
        }
        .sorted { d2($0) < d2($1) }
    }

    /// A corner is valid when it lies inside the island and holds nothing yet.
    func cornerFree(cx: Int, cy: Int, excluding: DecorationNode? = nil) -> Bool {
        guard cx >= 0, cy >= 0, cx <= cols, cy <= rows else { return false }
        return !decorationNodes.contains { d in
            d !== excluding && d.isCornerAnchor && d.gridX == cx && d.gridY == cy
        }
    }

    /// Corner-anchored greenery around a tile — cleared when a building goes up
    /// there so a tree can never block construction.
    func cornerDecorations(around col: Int, row: Int) -> [DecorationNode] {
        decorationNodes.filter { d in
            guard d.isCornerAnchor else { return false }
            return (d.gridX == col || d.gridX == col + 1)
                && (d.gridY == row || d.gridY == row + 1)
        }
    }

    // MARK: - Map size / expansion

    /// Set the island size (rebuilds ground). Building world positions are
    /// center-relative, so they stay in place visually.
    func setMapSize(_ n: Int) {
        guard n != cols else { return }
        cols = n
        rebuildGround()
    }

    /// Pause the render loop (and thus all animations/skinning) when the map
    /// isn't on screen — no point burning the GPU behind another tab.
    func setRendering(active: Bool) {
        scnView?.isPlaying = active
    }

    /// Expand by one tier: shifts all grid coordinates by +delta/2 so the
    /// existing town keeps its world position while the island grows around it.
    func expand(toCols newCols: Int) {
        let shift = (newCols - cols) / 2
        guard shift > 0 else { return }
        for b in buildingNodes {
            b.gridX += shift
            b.gridY += shift
        }
        for d in decorationNodes {
            d.gridX += shift
            d.gridY += shift
        }
        for a in animalNodes {
            a.shiftGrid(by: shift)
        }
        setMapSize(newCols)
        Haptics.success()
        celebrate(at: SCNVector3(0, 0, 0))
    }

    private func rebuildGround() {
        islandNode?.removeFromParentNode()
        islandNode = nil
        scnScene.rootNode.childNodes(passingTest: { n, _ in n.name == "groundDetail" })
            .forEach { $0.removeFromParentNode() }
        buildIsland()
        scatterGroundDetails()
    }

    // MARK: - Scene setup

    private func setupLights() {
        // Warm sun with soft shadows
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1000
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.castsShadow = true
        sun.shadowMode = .forward   // deferred shadows don't composite over a transparent background
        sun.shadowColor = UIColor(red: 0.10, green: 0.14, blue: 0.10, alpha: 0.30)
        sun.shadowRadius = 7
        sun.shadowSampleCount = 16
        sun.orthographicScale = 26
        sun.automaticallyAdjustsShadowProjection = true
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-1.0, -0.75, 0)
        scnScene.rootNode.addChildNode(sunNode)
        sunLight = sun

        // Cool ambient fill
        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 550
        amb.color = UIColor(red: 0.82, green: 0.88, blue: 0.95, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scnScene.rootNode.addChildNode(ambNode)
        ambLight = amb
    }

    // MARK: - Daylight (real time of day drives the light)

    private func applyDaylight(now: Date = .now) {
        let hour = Calendar.current.component(.hour, from: now)
        daylight = DaylightPhase(hour: hour)

        switch daylight {
        case .dawn:
            sunLight?.intensity = 850
            sunLight?.color = UIColor(red: 1.0, green: 0.85, blue: 0.72, alpha: 1)
            ambLight?.intensity = 480
            ambLight?.color = UIColor(red: 0.90, green: 0.82, blue: 0.88, alpha: 1)
        case .day:
            sunLight?.intensity = 1000
            sunLight?.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
            ambLight?.intensity = 550
            ambLight?.color = UIColor(red: 0.82, green: 0.88, blue: 0.95, alpha: 1)
        case .dusk:
            sunLight?.intensity = 780
            sunLight?.color = UIColor(red: 1.0, green: 0.74, blue: 0.52, alpha: 1)
            ambLight?.intensity = 460
            ambLight?.color = UIColor(red: 0.80, green: 0.72, blue: 0.86, alpha: 1)
        case .night:
            sunLight?.intensity = 320
            sunLight?.color = UIColor(red: 0.68, green: 0.76, blue: 0.95, alpha: 1)
            ambLight?.intensity = 330
            ambLight?.color = UIColor(red: 0.55, green: 0.62, blue: 0.80, alpha: 1)
        }
        refreshFirePits()
    }

    /// Re-read the clock — call when the map comes back on screen so fires and
    /// bedtime follow real time without a restart.
    func refreshTimeOfDay() {
        applyDaylight()
    }

    // MARK: - Weather (seeded per day: mostly sun, sometimes rain or fog)

    private func applyWeather(now: Date = .now) {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0
        let year = Calendar.current.component(.year, from: now)
        var seed = UInt64(day * 131 + year * 17)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let roll = Double((seed >> 33) & 0xFFFF) / Double(0xFFFF)

        weather = roll < 0.70 ? .sunny : (roll < 0.85 ? .rain : .fog)

        switch weather {
        case .sunny:
            break
        case .rain:
            sunLight?.intensity = (sunLight?.intensity ?? 1000) * 0.65
            ambLight?.color = UIColor(red: 0.72, green: 0.76, blue: 0.82, alpha: 1)
            addRain()
        case .fog:
            sunLight?.intensity = (sunLight?.intensity ?? 1000) * 0.8
            scnScene.fogColor = UIColor(red: 0.88, green: 0.91, blue: 0.90, alpha: 1)
            scnScene.fogStartDistance = 52
            scnScene.fogEndDistance   = 82
            scnScene.fogDensityExponent = 1.5
        }
    }

    private func addRain() {
        let rain = SCNParticleSystem()
        rain.birthRate = 450
        rain.particleLifeSpan = 1.4
        rain.particleVelocity = 9
        rain.particleVelocityVariation = 2
        rain.emittingDirection = SCNVector3(0, -1, 0)
        rain.spreadingAngle = 2
        rain.particleSize = 0.02
        rain.particleSizeVariation = 0.01
        rain.stretchFactor = 0.12
        rain.particleColor = UIColor(red: 0.75, green: 0.82, blue: 0.92, alpha: 0.42)
        rain.emitterShape = SCNBox(width: 30, height: 0.1, length: 30, chamferRadius: 0)
        rain.birthLocation = .volume
        rain.isAffectedByGravity = false

        let node = SCNNode()
        node.position = SCNVector3(0, 9, 0)
        node.addParticleSystem(rain)
        node.name = "rain"
        scnScene.rootNode.addChildNode(node)
    }

    // MARK: - Clouds (drift slowly, cast real soft shadows)

    private func setupClouds() {
        guard weather != .fog else { return }
        var seed: UInt64 = 0xC10D_5EED
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }

        let cloudMat = SCNMaterial()
        cloudMat.diffuse.contents = UIColor(white: 1.0, alpha: weather == .rain ? 0.82 : 0.92)
        cloudMat.lightingModel = .lambert
        cloudMat.transparency = 0.92

        let count = weather == .rain ? 5 : 3
        for i in 0..<count {
            let cloud = SCNNode()
            let puffs = 2 + Int(rnd() * 2)
            for _ in 0...puffs {
                let s = CGFloat(0.7 + rnd() * 1.1)
                let g = SCNBox(width: s * 1.6, height: s * 0.5, length: s, chamferRadius: s * 0.24)
                g.materials = [cloudMat]
                let p = SCNNode(geometry: g)
                p.position = SCNVector3((rnd() - 0.5) * 2.2, (rnd() - 0.5) * 0.3, (rnd() - 0.5) * 1.2)
                cloud.addChildNode(p)
            }
            let y = 5.5 + rnd() * 1.5
            let z = (rnd() - 0.5) * 16
            let startX = -18 + rnd() * 30
            cloud.position = SCNVector3(startX, y, z)
            cloud.opacity = 0.9
            cloud.name = "cloud"
            scnScene.rootNode.addChildNode(cloud)

            // Drift across, wrap around
            let speed = 60.0 + Double(rnd()) * 40   // seconds for full crossing
            let toEdge = SCNAction.moveBy(x: CGFloat(18 - startX), y: 0, z: 0,
                                          duration: speed * Double(18 - startX) / 36)
            let wrap  = SCNAction.run { n in n.position.x = -18 }
            let cross = SCNAction.moveBy(x: 36, y: 0, z: 0, duration: speed)
            cloud.runAction(.sequence([toEdge, wrap, .repeatForever(.sequence([cross, wrap]))]))
            _ = i
        }
    }

    // MARK: - Birds (occasional fly-over)

    private func setupBirds() {
        guard weather == .sunny else { return }
        for i in 0..<2 {
            let bird = SCNNode()
            let body = SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.16)
            body.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
            body.firstMaterial?.lightingModel = .lambert
            let b = SCNNode(geometry: body)
            b.eulerAngles.z = -.pi / 2      // point along +x
            bird.addChildNode(b)
            for side in [-1.0, 1.0] as [CGFloat] {
                let wing = SCNBox(width: 0.10, height: 0.01, length: 0.16, chamferRadius: 0.004)
                wing.firstMaterial?.diffuse.contents = UIColor(white: 0.28, alpha: 1)
                let w = SCNNode(geometry: wing)
                w.position = SCNVector3(0, 0.01, side * 0.11)
                w.runAction(.repeatForever(.sequence([
                    .rotateTo(x: side * 0.5, y: 0, z: 0, duration: 0.18),
                    .rotateTo(x: side * -0.35, y: 0, z: 0, duration: 0.18)
                ])))
                bird.addChildNode(w)
            }

            // Spawn beyond the island edge and stay invisible while resting,
            // fading in/out at the flight ends — no parked birds when zoomed out.
            let margin = Float(cols) / 2 + 6
            let span = CGFloat(margin * 2)
            let flyDur = 14.0
            let y: Float = 3.2 + Float(i) * 0.7
            let z: Float = Float(i) * 4 - 2
            bird.position = SCNVector3(-margin, y, z)
            bird.opacity = 0
            bird.name = "bird"
            scnScene.rootNode.addChildNode(bird)

            let fly = SCNAction.moveBy(x: span, y: 0.6, z: 2, duration: flyDur)
            fly.timingMode = .linear
            let fade = SCNAction.sequence([
                .fadeIn(duration: 0.6),
                .wait(duration: flyDur - 1.4),
                .fadeOut(duration: 0.8),
            ])
            let reset = SCNAction.run { n in n.position = SCNVector3(-margin, y, z) }
            let rest  = SCNAction.wait(duration: 45 + Double(i) * 20)
            bird.runAction(.sequence([
                .wait(duration: 6 + Double(i) * 14),
                .repeatForever(.sequence([.group([fly, fade]), reset, rest])),
            ]))
        }
    }

    // MARK: - Butterflies (sunny daytime) & fireflies (night)

    /// A couple of butterflies fluttering low over the meadow.
    private func setupButterflies() {
        guard weather == .sunny, daylight != .night,
              !UIAccessibility.isReduceMotionEnabled else { return }

        let tints: [UIColor] = [
            UIColor(red: 0.98, green: 0.85, blue: 0.35, alpha: 1),
            UIColor(red: 0.95, green: 0.65, blue: 0.75, alpha: 1),
            UIColor(red: 0.85, green: 0.90, blue: 0.98, alpha: 1),
        ]

        for i in 0..<3 {
            let butterfly = SCNNode()
            for side in [-1.0, 1.0] as [CGFloat] {
                let wing = SCNPlane(width: 0.05, height: 0.045)
                wing.firstMaterial?.diffuse.contents = tints[i % tints.count]
                wing.firstMaterial?.isDoubleSided = true
                wing.firstMaterial?.lightingModel = .constant
                let w = SCNNode(geometry: wing)
                w.position = SCNVector3(side * 0.026, 0, 0)
                w.eulerAngles.x = -.pi / 2
                w.runAction(.repeatForever(.sequence([
                    .rotateTo(x: -.pi / 2 + side * 0.9, y: 0, z: 0, duration: 0.12),
                    .rotateTo(x: -.pi / 2 - side * 0.2, y: 0, z: 0, duration: 0.12),
                ])))
                butterfly.addChildNode(w)
            }

            // Orbit a random spot on the meadow, bobbing gently
            let half = Float(cols) / 2 - 2
            let anchor = SCNNode()
            anchor.position = SCNVector3(Float.random(in: -half...half), 0.35,
                                         Float.random(in: -half...half))
            anchor.name = "ambientLife"
            butterfly.position = SCNVector3(0.4, 0, 0)
            anchor.addChildNode(butterfly)
            scnScene.rootNode.addChildNode(anchor)

            anchor.runAction(.repeatForever(
                .rotateBy(x: 0, y: .pi * 2, z: 0, duration: Double.random(in: 6...10))))
            let bobUp = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 0.8)
            bobUp.timingMode = .easeInEaseOut
            let bobDn = SCNAction.moveBy(x: 0, y: -0.06, z: 0, duration: 0.8)
            bobDn.timingMode = .easeInEaseOut
            butterfly.runAction(.repeatForever(.sequence([bobUp, bobDn])))
        }
    }

    /// Slow glowing fireflies drifting over the night meadow.
    private func setupFireflies() {
        guard daylight == .night, weather != .rain,
              !UIAccessibility.isReduceMotionEnabled else { return }

        let half = Float(cols) / 2 - 2
        for _ in 0..<6 {
            let g = SCNSphere(radius: 0.016)
            g.firstMaterial?.diffuse.contents = UIColor(red: 0.85, green: 0.95, blue: 0.45, alpha: 1)
            g.firstMaterial?.emission.contents = UIColor(red: 0.75, green: 0.90, blue: 0.30, alpha: 1)
            g.firstMaterial?.lightingModel = .constant
            let fly = SCNNode(geometry: g)
            fly.position = SCNVector3(Float.random(in: -half...half),
                                      Float.random(in: 0.25...0.7),
                                      Float.random(in: -half...half))
            fly.name = "ambientLife"
            scnScene.rootNode.addChildNode(fly)

            // Lazy wandering loop + soft blinking
            let d1 = Double.random(in: 3...5)
            let dx = CGFloat.random(in: -0.5...0.5)
            let dz = CGFloat.random(in: -0.5...0.5)
            let wander = SCNAction.sequence([
                .moveBy(x: dx, y: 0.08, z: dz, duration: d1),
                .moveBy(x: -dx, y: -0.08, z: -dz, duration: d1),
            ])
            wander.timingMode = .easeInEaseOut
            fly.runAction(.repeatForever(wander))
            fly.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.15, duration: Double.random(in: 0.6...1.2)),
                .fadeOpacity(to: 1.0, duration: Double.random(in: 0.6...1.2)),
            ])))
        }
    }

    private func setupCamera() {
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = 7.5
        cam.zNear = -100
        cam.zFar  = 200
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 0, 60)

        cameraRig.addChildNode(cameraNode)
        cameraRig.eulerAngles = SCNVector3(-0.62, .pi / 4, 0)   // ~35.5° down, 45° yaw
        cameraRig.position = SCNVector3(0, 0, 0)
        scnScene.rootNode.addChildNode(cameraRig)
    }

    private func buildIsland() {
        let w = CGFloat(cols) * Self.tile + 1.6
        let island = SCNBox(width: w, height: 1.6, length: w, chamferRadius: 0.35)
        let grass = SCNMaterial()
        grass.diffuse.contents = Self.makeGrassTexture(islandWidth: w, cols: cols)
        grass.diffuse.wrapS = .clamp
        grass.diffuse.wrapT = .clamp
        grass.lightingModel = .lambert
        let soil = SCNMaterial()
        soil.diffuse.contents = UIColor(red: 0.52, green: 0.42, blue: 0.34, alpha: 1)
        soil.lightingModel = .lambert
        island.materials = [soil, soil, soil, soil, grass, soil]  // top = grass
        let node = SCNNode(geometry: island)
        node.position = SCNVector3(0, -0.8, 0)                    // top surface at y = 0
        node.name = "island"
        scnScene.rootNode.addChildNode(node)
        islandNode = node
    }

    /// Living grass texture: soft tile checker, mown-lawn patches and speckles.
    private static func makeGrassTexture(islandWidth: CGFloat, cols: Int) -> UIImage {
        let px: CGFloat = 1024
        let margin = px * (islandWidth - CGFloat(cols) * tile) / (2 * islandWidth)
        let cell = (px - 2 * margin) / CGFloat(cols)

        var seed: UInt64 = 0x5EED_1234
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: px, height: px))
        return renderer.image { ctx in
            let c = ctx.cgContext

            // Base
            c.setFillColor(UIColor(red: 0.55, green: 0.72, blue: 0.42, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: px, height: px))

            // Soft checker so the grid is readable but subtle
            for row in 0..<cols {
                for col in 0..<cols where (row + col) % 2 == 0 {
                    c.setFillColor(UIColor(white: 1, alpha: 0.045).cgColor)
                    c.fill(CGRect(x: margin + CGFloat(col) * cell,
                                  y: margin + CGFloat(row) * cell,
                                  width: cell, height: cell))
                }
            }

            // Large lighter/darker patches for a meadow feel. Drawn as radial
            // gradients that fade to nothing — a hard-edged ellipse this big
            // reads as a circle drawn on the lawn instead of a soft patch.
            let space = CGColorSpaceCreateDeviceRGB()
            for _ in 0..<16 {
                let r = 70 + rnd() * 130
                let light = rnd() > 0.5
                let alpha = 0.10 + rnd() * 0.06
                let core = UIColor(red: light ? 0.62 : 0.48,
                                   green: light ? 0.78 : 0.66,
                                   blue: light ? 0.46 : 0.38,
                                   alpha: alpha).cgColor
                let edge = core.copy(alpha: 0)!
                guard let grad = CGGradient(colorsSpace: space,
                                            colors: [core, edge] as CFArray,
                                            locations: [0, 1]) else { continue }
                let centre = CGPoint(x: rnd() * px, y: rnd() * px)
                let squash = 0.7 + rnd() * 0.5
                c.saveGState()
                c.translateBy(x: centre.x, y: centre.y)
                c.scaleBy(x: 1, y: squash)          // gentle ellipse, still soft
                c.drawRadialGradient(grad,
                                     startCenter: .zero, startRadius: 0,
                                     endCenter: .zero, endRadius: r,
                                     options: [])
                c.restoreGState()
            }

            // Fine speckles — grass blades
            for _ in 0..<2200 {
                let light = rnd() > 0.45
                c.setFillColor(UIColor(
                    red: light ? 0.68 : 0.40,
                    green: light ? 0.82 : 0.58,
                    blue: light ? 0.50 : 0.32,
                    alpha: 0.16 + rnd() * 0.18).cgColor)
                let s = 1.5 + rnd() * 2.5
                c.fillEllipse(in: CGRect(x: rnd() * px, y: rnd() * px, width: s, height: s * (1 + rnd())))
            }

            // Rare tiny flowers
            for _ in 0..<70 {
                let colors: [UIColor] = [
                    UIColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 0.85),
                    UIColor(red: 0.99, green: 0.85, blue: 0.40, alpha: 0.85),
                    UIColor(red: 0.95, green: 0.62, blue: 0.68, alpha: 0.8),
                ]
                c.setFillColor(colors[Int(rnd() * 2.99)].cgColor)
                let s = 2.5 + rnd() * 2.5
                c.fillEllipse(in: CGRect(x: rnd() * px, y: rnd() * px, width: s, height: s))
            }
        }
    }

    /// Scatter small 3D props (grass tufts, rocks, flowers) for life.
    private func scatterGroundDetails() {
        var seed: UInt64 = 0xB00B_5EED
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }

        let green  = UIColor(red: 0.42, green: 0.64, blue: 0.34, alpha: 1)
        let green2 = UIColor(red: 0.36, green: 0.58, blue: 0.30, alpha: 1)
        let stone  = UIColor(red: 0.70, green: 0.68, blue: 0.63, alpha: 1)

        let half = Float(cols) / 2 - 0.5
        for _ in 0..<46 {
            let x = (rnd() * 2 - 1) * half
            let z = (rnd() * 2 - 1) * half
            let kind = rnd()
            let n = SCNNode()

            if kind < 0.45 {
                // grass tuft — 3 tiny cones
                for i in 0..<3 {
                    let cone = SCNCone(topRadius: 0, bottomRadius: 0.025, height: CGFloat(0.08 + rnd() * 0.06))
                    cone.firstMaterial?.diffuse.contents = i % 2 == 0 ? green : green2
                    cone.firstMaterial?.lightingModel = .lambert
                    let t = SCNNode(geometry: cone)
                    t.position = SCNVector3((rnd() - 0.5) * 0.1, 0.05, (rnd() - 0.5) * 0.1)
                    n.addChildNode(t)
                }
            } else if kind < 0.7 {
                // rock
                let box = SCNBox(width: CGFloat(0.08 + rnd() * 0.08), height: CGFloat(0.06 + rnd() * 0.05),
                                 length: CGFloat(0.08 + rnd() * 0.08), chamferRadius: 0.03)
                box.firstMaterial?.diffuse.contents = stone
                box.firstMaterial?.lightingModel = .lambert
                let b = SCNNode(geometry: box)
                b.position.y = 0.03
                b.eulerAngles.y = rnd() * .pi
                n.addChildNode(b)
            } else {
                // flower — stem + colored head
                let stem = SCNCylinder(radius: 0.008, height: 0.09)
                stem.firstMaterial?.diffuse.contents = green
                let s = SCNNode(geometry: stem)
                s.position.y = 0.045
                n.addChildNode(s)
                let head = SCNSphere(radius: 0.028)
                let heads: [UIColor] = [
                    UIColor(red: 0.99, green: 0.85, blue: 0.35, alpha: 1),
                    UIColor(red: 0.96, green: 0.55, blue: 0.60, alpha: 1),
                    UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1),
                ]
                head.firstMaterial?.diffuse.contents = heads[Int(rnd() * 2.99)]
                head.firstMaterial?.lightingModel = .lambert
                let h = SCNNode(geometry: head)
                h.position.y = 0.1
                n.addChildNode(h)
            }
            n.position = SCNVector3(x, 0, z)
            n.name = "groundDetail"
            scnScene.rootNode.addChildNode(n)
        }
    }

    // MARK: - Buildings

    @discardableResult
    func addBuilding(type: BuildingType, gridX: Int, gridY: Int,
                     isComplete: Bool = true, animated: Bool = false, rotation: Int = 0,
                     style: BuildingStyle = BuildingStyle()) -> BuildingNode {
        let node = BuildingNode(type: type, gridX: gridX, gridY: gridY,
                                isComplete: isComplete, rotation: rotation, style: style)
        node.position = gridToWorld(col: gridX, row: gridY)
        scnScene.rootNode.addChildNode(node)
        buildingNodes.append(node)

        if animated {
            node.scale = SCNVector3(0.01, 0.01, 0.01)
            let pop = SCNAction.sequence([
                .scale(to: 1.12, duration: 0.24),
                .scale(to: 1.0,  duration: 0.12)
            ])
            pop.timingMode = .easeOut
            node.runAction(pop)
            moveCamera(to: node.position)
            scnScene.rootNode.runAction(.sequence([
                .wait(duration: 0.5),
                .run { [weak self] _ in self?.celebrate(at: node.position) }
            ]))
        }
        return node
    }

    func moveCamera(to p: SCNVector3) {
        let move = SCNAction.move(to: SCNVector3(p.x, 0, p.z), duration: 0.5)
        move.timingMode = .easeInEaseOut
        cameraRig.runAction(move)
    }

    // MARK: - Decorations

    @discardableResult
    func addDecoration(type: DecorationItem, gridX: Int, gridY: Int, rotation: Int = 0,
                       isCornerAnchor: Bool = false, variant: Int = 0) -> DecorationNode {
        let node = DecorationNode(type: type, gridX: gridX, gridY: gridY, rotation: rotation,
                                  isCornerAnchor: isCornerAnchor, variant: variant)
        node.position = isCornerAnchor
            ? cornerToWorld(cx: gridX, cy: gridY)
            : gridToWorld(col: gridX, row: gridY)
        scnScene.rootNode.addChildNode(node)
        decorationNodes.append(node)
        if type == .road { retileRoads(around: gridX, gridY) }
        if type == .birdFeeder { node.startFeederVisits() }
        if type == .firePit { node.setFireLit(isAfterDark) }
        return node
    }

    /// Dusk and night — when fires burn and pets turn in.
    var isAfterDark: Bool { daylight == .night || daylight == .dusk }

    /// Keep every fire pit in step with the time of day.
    func refreshFirePits() {
        for d in decorationNodes where d.type == .firePit {
            d.setFireLit(isAfterDark)
        }
    }

    func removeDecoration(_ node: DecorationNode) {
        decorationNodes.removeAll { $0 === node }
        let col = node.gridX, row = node.gridY
        node.runAction(.sequence([
            .group([.scale(to: 0.01, duration: 0.18), .fadeOut(duration: 0.18)]),
            .removeFromParentNode()
        ]))
        if node.type == .road { retileRoads(around: col, row) }
    }

    func removeBuilding(_ node: BuildingNode) {
        buildingNodes.removeAll { $0 === node }
        node.runAction(.sequence([
            .group([.scale(to: 0.01, duration: 0.22), .fadeOut(duration: 0.22)]),
            .removeFromParentNode()
        ]))
    }

    // MARK: - Animals (zoo)

    /// A cell an animal may stand on: inside the map, no building, and no solid
    /// decoration. Roads and the pond count as walkable (they can stroll on paths
    /// and paddle in the water); trees, benches, fountains block them.
    func isAnimalWalkable(col: Int, row: Int) -> Bool {
        guard col >= 0, row >= 0, col < cols, row < rows else { return false }
        if buildingNodes.contains(where: { b in
            b.occupiedOffsets.contains { col == b.gridX + $0.dx && row == b.gridY + $0.dy }
        }) { return false }
        for d in decorationNodes {
            guard !d.isCornerAnchor else { continue }   // cosmetic corner greenery
            let fp = d.type.footprint
            let inside = col >= d.gridX && col < d.gridX + fp.w
                      && row >= d.gridY && row < d.gridY + fp.l
            guard inside else { continue }
            if d.type == .road || d.type == .pond { continue }   // walkable
            return false
        }
        return true
    }

    func isWater(col: Int, row: Int) -> Bool {
        decorationNodes.contains { d in
            guard d.type == .pond else { return false }
            let fp = d.type.footprint
            return col >= d.gridX && col < d.gridX + fp.w
                && row >= d.gridY && row < d.gridY + fp.l
        }
    }

    private func randomWalkableLandCell() -> (col: Int, row: Int) {
        for _ in 0..<80 {
            let c = Int.random(in: 0..<cols), r = Int.random(in: 0..<rows)
            if isAnimalWalkable(col: c, row: r), !isWater(col: c, row: r) { return (c, r) }
        }
        return (cols / 2, rows / 2)
    }

    @discardableResult
    func addAnimal(kind: AnimalKind) -> AnimalNode {
        let node = AnimalNode(
            kind: kind,
            calm: UIAccessibility.isReduceMotionEnabled,
            isWalkable: { [weak self] c, r in self?.isAnimalWalkable(col: c, row: r) ?? false },
            isWater: { [weak self] c, r in self?.isWater(col: c, row: r) ?? false },
            worldFor: { [weak self] c, r in self?.gridToWorld(col: c, row: r) ?? SCNVector3Zero },
            isNight: {
                let phase = DaylightPhase(hour: Calendar.current.component(.hour, from: .now))
                return phase == .night || phase == .dusk
            }
        )
        // A doghouse to sleep in, and a filled bowl to trot over to.
        node.findBed = { [weak self] animal in self?.freeKennel(for: animal) }
        node.findBowl = { [weak self] animal in
            guard animal.kind.usesDoghouse else { return nil }   // it's dog food
            return self?.filledBowl()
        }
        node.onAteFromBowl = { [weak self] _ in
            // Fired from a SceneKit action completion (render thread) — clear the
            // node flag here, then hop to the main thread for the SwiftData part.
            guard let self else { return }
            for d in self.decorationNodes where d.type == .doghouse && d.bowlHasFood {
                d.setBowlFilled(false)
            }
            DispatchQueue.main.async { [weak self] in self?.onBowlEmptied?() }
        }

        let cell = randomWalkableLandCell()
        node.place(col: cell.col, row: cell.row)
        scnScene.rootNode.addChildNode(node)
        animalNodes.append(node)
        // Load the downloaded glTF; adoptRig adds the model and starts it living.
        AnimalModelLoader.loadRig(kind) { [weak node] visual, clips in
            node?.adoptRig(visual: visual, clips: clips)
        }
        return node
    }

    /// Fired when a pet finishes the food in a bowl, so the model layer can
    /// clear the stored `hasFood` flag.
    var onBowlEmptied: (() -> Void)?

    /// A doghouse nobody else has claimed for the night, with the spot inside it.
    private func freeKennel(for animal: AnimalNode)
        -> (cell: (col: Int, row: Int), world: SCNVector3, yaw: Float)? {
        guard animal.kind.usesDoghouse else { return nil }   // a horse won't fit
        let houses = decorationNodes.filter { $0.type == .doghouse }
        guard !houses.isEmpty else { return nil }
        // One pet per house: claim by index so two dogs don't share a bed.
        let sleepers = animalNodes.filter { $0 !== animal && $0.isSleeping }
        for house in houses {
            let taken = sleepers.contains { s in
                abs(s.position.x - house.position.x) < 0.4 && abs(s.position.z - house.position.z) < 0.4
            }
            guard !taken, let bed = house.doghouseBed else { continue }
            let world = SCNVector3(house.position.x + bed.offset.x,
                                   bed.offset.y,
                                   house.position.z + bed.offset.z)
            return ((house.gridX, house.gridY), world, bed.yaw)
        }
        return nil
    }

    /// The first doghouse whose bowl currently has food in it. Reads the node's
    /// own flag — this runs on the render thread, where SwiftData is off limits.
    private func filledBowl() -> (cell: (col: Int, row: Int), world: SCNVector3)? {
        for d in decorationNodes where d.type == .doghouse {
            guard d.bowlHasFood,
                  let bowl = d.childNode(withName: "bowl", recursively: true) else { continue }
            let w = d.convertPosition(bowl.position, to: nil)
            return ((d.gridX, d.gridY), SCNVector3(w.x, 0, w.z))
        }
        return nil
    }

    func removeAnimal(_ node: AnimalNode) {
        animalNodes.removeAll { $0 === node }
        node.removeAllActions()
        node.runAction(.sequence([
            .group([.scale(to: 0.01, duration: 0.2), .fadeOut(duration: 0.2)]),
            .removeFromParentNode(),
        ]))
    }

    func hasOccupant(col: Int, row: Int, excluding: SCNNode? = nil) -> Bool {
        let bOcc = buildingNodes.contains { b in
            guard b !== excluding else { return false }
            return b.occupiedOffsets.contains { col == b.gridX + $0.dx && row == b.gridY + $0.dy }
        }
        let dOcc = decorationNodes.contains { d in
            // Corner greenery lives on its own lattice and is purely cosmetic —
            // it never occupies a build cell.
            guard d !== excluding, !d.isCornerAnchor else { return false }
            let fp = d.type.footprint
            return col >= d.gridX && col < d.gridX + fp.w
                && row >= d.gridY && row < d.gridY + fp.l
        }
        return bOcc || dOcc
    }

    /// All footprint cells free and inside the buildable area (edge to edge)?
    func cellsFree(col: Int, row: Int, w: Int = 1, l: Int = 1, excluding: SCNNode? = nil) -> Bool {
        guard col >= 0, row >= 0, col + w <= cols, row + l <= rows else { return false }
        for dc in 0..<w {
            for dr in 0..<l where hasOccupant(col: col + dc, row: row + dr, excluding: excluding) {
                return false
            }
        }
        return true
    }

    /// Rotation-aware occupied offsets for anything on the grid.
    private func occupiedOffsets(of n: SCNNode & GridOccupant) -> [(dx: Int, dy: Int)] {
        if let b = n as? BuildingNode { return b.occupiedOffsets }
        if let d = n as? DecorationNode {
            let fp = d.type.footprint
            return (0..<fp.w).flatMap { dx in (0..<fp.l).map { dy in (dx, dy) } }
        }
        return [(0, 0)]
    }

    /// Every offset cell inside the map and free (ignoring the node itself)?
    func canPlace(offsets: [(dx: Int, dy: Int)], at col: Int, row: Int,
                  excluding: SCNNode? = nil) -> Bool {
        for o in offsets {
            let c = col + o.dx, r = row + o.dy
            guard c >= 0, r >= 0, c < cols, r < rows,
                  !hasOccupant(col: c, row: r, excluding: excluding) else { return false }
        }
        return true
    }

    /// Rotates a building if the rotated footprint fits; buzzes otherwise.
    func tryRotate(_ b: BuildingNode) {
        let next = BuildingNode.occupiedOffsets(footprint: b.type.footprint,
                                                steps: b.rotationSteps + 1)
        guard canPlace(offsets: next, at: b.gridX, row: b.gridY, excluding: b) else {
            Haptics.warning()
            return
        }
        Haptics.tap()
        b.toggleRotation()
    }

    // MARK: - Road auto-tiling

    private func roadNode(col: Int, row: Int) -> DecorationNode? {
        decorationNodes.first { $0.type == .road && $0.gridX == col && $0.gridY == row }
    }

    private func retileRoad(col: Int, row: Int) {
        guard let r = roadNode(col: col, row: row) else { return }
        r.rebuildRoad(
            n: roadNode(col: col,     row: row - 1) != nil,
            e: roadNode(col: col + 1, row: row)     != nil,
            s: roadNode(col: col,     row: row + 1) != nil,
            w: roadNode(col: col - 1, row: row)     != nil
        )
    }

    func retileRoads(around col: Int, _ row: Int) {
        for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] {
            retileRoad(col: col + dx, row: row + dy)
        }
    }

    func nextFreeCell(w: Int = 1, l: Int = 1) -> (col: Int, row: Int) {
        let cx = cols / 2, cy = rows / 2
        for radius in 0..<cols {
            for dx in -radius...radius {
                for dy in -radius...radius {
                    guard abs(dx) == radius || abs(dy) == radius else { continue }
                    let col = cx + dx, row = cy + dy
                    if cellsFree(col: col, row: row, w: w, l: l) { return (col, row) }
                }
            }
        }
        return (1, 1)
    }

    // MARK: - Hit testing / picking

    func buildingHit(at point: CGPoint) -> BuildingNode? {
        occupantHit(at: point) as? BuildingNode
    }

    /// Any draggable grid object (building or decoration) under the touch.
    func occupantHit(at point: CGPoint) -> (SCNNode & GridOccupant)? {
        guard let view = scnView else { return nil }
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        for hit in hits {
            var n: SCNNode? = hit.node
            while let cur = n {
                if let b = cur as? BuildingNode   { return b }
                if let d = cur as? DecorationNode { return d }
                n = cur.parent
            }
        }
        return nil
    }

    /// Intersect the screen point with the ground plane (y = 0).
    func groundPoint(at point: CGPoint) -> SCNVector3? {
        guard let view = scnView else { return nil }
        let near = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
        let far  = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
        let dy = far.y - near.y
        guard abs(dy) > 1e-6 else { return nil }
        let t = -near.y / dy
        return SCNVector3(near.x + (far.x - near.x) * t, 0, near.z + (far.z - near.z) * t)
    }

    // MARK: - Gesture handlers (called by TownSceneView.Coordinator)

    func handleTap(at point: CGPoint) {
        if isPlacementMode {
            guard let g = groundPoint(at: point) else { return }
            if placingUsesAnchors {
                lastAnchorPoint = g          // lets the handler try nearby spots too
                onAnchorTapped?(nearestAnchor(to: g))
                return
            }
            let cell = worldToGrid(g)
            onTileTapped?(cell.col, cell.row)
            return
        }
        switch occupantHit(at: point) {
        case let b as BuildingNode:
            b.bounce()
            onBuildingTapped?(b)
        case let d as DecorationNode:
            onDecorationTapped?(d)
        default:
            if let a = animalHit(at: point) { onAnimalTapped?(a) }
        }
    }

    /// A roaming pet under the touch (animals aren't grid occupants).
    func animalHit(at point: CGPoint) -> AnimalNode? {
        guard let view = scnView else { return nil }
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        for hit in hits {
            var n: SCNNode? = hit.node
            while let cur = n {
                if let a = cur as? AnimalNode { return a }
                n = cur.parent
            }
        }
        return nil
    }

    func handleDoubleTap(at point: CGPoint) {
        guard !isPlacementMode else { return }
        switch occupantHit(at: point) {
        case let b as BuildingNode:
            tryRotate(b)
        case let d as DecorationNode where d.canRotate:
            Haptics.tap()
            d.toggleRotation()
        default:
            break
        }
    }

    func handlePinch(scale: CGFloat, began: inout CGFloat) {
        guard let cam = cameraNode.camera else { return }
        if began == 0 { began = cam.orthographicScale }
        cam.orthographicScale = min(16, max(3.5, began / Double(scale)))
    }

    /// One paint step of a road stroke — converts the touch to a grid cell and
    /// notifies once per newly entered cell.
    func paintStroke(at point: CGPoint) {
        guard let g = groundPoint(at: point) else { return }
        let cell = worldToGrid(g)
        if let last = lastPaintedCell, last == cell { return }
        lastPaintedCell = cell
        onPaintCell?(cell.col, cell.row)
    }

    func endPaintStroke() {
        lastPaintedCell = nil
    }

    func handlePan(translation: CGPoint, start: inout SCNVector3?) {
        guard cameraPanEnabled else { return }
        if start == nil { start = cameraRig.position }
        guard let s = start, let cam = cameraNode.camera, let view = scnView else { return }

        // Screen px → world units at current ortho scale
        let unitsPerPt = Float(cam.orthographicScale * 2 / Double(view.bounds.height))
        let dx = Float(translation.x) * unitsPerPt
        let dz = Float(translation.y) * unitsPerPt

        // Camera-relative right/forward flattened to the ground plane
        let yaw = cameraRig.eulerAngles.y
        let right   = SCNVector3(cos(yaw), 0, -sin(yaw))
        let forward = SCNVector3(-sin(yaw), 0, -cos(yaw))

        // Natural mode (default): the map follows the finger on both axes.
        // Classic mode: the camera moves in the drag direction instead.
        let follows = UserDefaults.standard.object(forKey: "mapFollowsFinger") as? Bool ?? true
        let m: Float = follows ? 1 : -1

        var p = SCNVector3(
            s.x + m * (-right.x * dx + forward.x * dz),
            0,
            s.z + m * (-right.z * dx + forward.z * dz)
        )
        let limit: Float = Float(cols) / 2 + 2
        p.x = min(limit, max(-limit, p.x))
        p.z = min(limit, max(-limit, p.z))
        cameraRig.position = p
    }

    // MARK: - Drag & drop

    func dragBegan(at point: CGPoint) {
        guard !isPlacementMode, draggedNode == nil, draggedAnimal == nil else { return }
        // Pets are picked up and carried like anything else on the map.
        if occupantHit(at: point) == nil, let a = animalHit(at: point) {
            draggedAnimal = a
            cameraPanEnabled = false
            a.beginCarry()
            a.runAction(.move(to: SCNVector3(a.position.x, 0.5, a.position.z), duration: 0.12))
            return
        }
        guard let b = occupantHit(at: point),
              let g = groundPoint(at: point) else { return }
        draggedNode = b
        dragOffset  = SCNVector3(b.position.x - g.x, 0, b.position.z - g.z)
        cameraPanEnabled = false
        Haptics.pickup()
        showPlacementHints(true)

        b.runAction(.move(to: SCNVector3(b.position.x, 0.45, b.position.z), duration: 0.12))
        b.setSelected(true)

        // Greenery can land on a corner, where a one-cell ghost would lie — the
        // anchor dots are the guide instead.
        if let dn = b as? DecorationNode, dn.type.canUseCornerAnchor { return }

        let bounds = offsetsBounds(of: b)
        let ghost = SCNNode(geometry: SCNPlane(width: CGFloat(bounds.w) + 0.02,
                                               height: CGFloat(bounds.l) + 0.02))
        ghost.eulerAngles.x = -.pi / 2
        ghost.geometry?.firstMaterial?.lightingModel = .constant
        scnScene.rootNode.addChildNode(ghost)
        ghostNode = ghost
        updateGhost(col: b.gridX, row: b.gridY)
    }

    /// Bounding box of a node's occupied offsets (for the drag ghost).
    private func offsetsBounds(of n: SCNNode & GridOccupant)
        -> (w: Int, l: Int, midX: Float, midY: Float) {
        let offs = occupiedOffsets(of: n)
        let xs = offs.map(\.dx), ys = offs.map(\.dy)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        return (maxX - minX + 1, maxY - minY + 1,
                Float(minX + maxX) / 2, Float(minY + maxY) / 2)
    }

    func dragMoved(at point: CGPoint) {
        if let a = draggedAnimal, let g = groundPoint(at: point) {
            a.position = SCNVector3(g.x, 0.5, g.z)
            return
        }
        guard let b = draggedNode, let g = groundPoint(at: point) else { return }
        b.position = SCNVector3(g.x + dragOffset.x, 0.45, g.z + dragOffset.z)
        let cell = worldToGrid(SCNVector3(b.position.x, 0, b.position.z))
        updateGhost(col: cell.col, row: cell.row)
    }

    func dragEnded(at point: CGPoint) {
        // Setting a carried pet down: land it on the nearest walkable cell.
        if let a = draggedAnimal {
            draggedAnimal = nil
            cameraPanEnabled = true
            let cell = worldToGrid(SCNVector3(a.position.x, 0, a.position.z))
            let target = isAnimalWalkable(col: cell.col, row: cell.row)
                ? cell
                : randomWalkableLandCell()
            a.endCarry(col: target.col, row: target.row)
            return
        }
        guard let b = draggedNode else { return }
        draggedNode = nil
        cameraPanEnabled = true
        ghostNode?.removeFromParentNode()
        ghostNode = nil
        b.setSelected(false)
        showPlacementHints(isPlacementMode)

        // Greenery lands on whichever is closer: a tile centre or a shared corner.
        // It can move freely between the two lattices.
        if let dn = b as? DecorationNode, dn.type.canUseCornerAnchor {
            switch nearestAnchor(to: SCNVector3(dn.position.x, 0, dn.position.z)) {
            case let .corner(cx, cy) where cornerFree(cx: cx, cy: cy, excluding: dn):
                dn.isCornerAnchor = true
                dn.gridX = cx; dn.gridY = cy
                Haptics.drop()
            case let .tile(col, row) where canPlace(offsets: [(0, 0)], at: col, row: row, excluding: dn):
                dn.isCornerAnchor = false
                dn.gridX = col; dn.gridY = row
                Haptics.drop()
            default:
                Haptics.warning()   // occupied → snap back where it came from
            }
            dn.associatedDecoration?.isCornerAnchor = dn.isCornerAnchor
            dn.associatedDecoration?.gridX = dn.gridX
            dn.associatedDecoration?.gridY = dn.gridY
            let dest = dn.isCornerAnchor
                ? cornerToWorld(cx: dn.gridX, cy: dn.gridY)
                : gridToWorld(col: dn.gridX, row: dn.gridY)
            let settle = SCNAction.move(to: dest, duration: 0.18)
            settle.timingMode = .easeOut
            dn.runAction(settle)
            return
        }

        let cell = worldToGrid(SCNVector3(b.position.x, 0, b.position.z))
        let valid = canPlace(offsets: occupiedOffsets(of: b),
                             at: cell.col, row: cell.row, excluding: b)

        if valid {
            Haptics.drop()
            let oldCol = b.gridX, oldRow = b.gridY
            b.gridX = cell.col
            b.gridY = cell.row
            switch b {
            case let bn as BuildingNode:
                bn.associatedBuilding?.gridX = cell.col
                bn.associatedBuilding?.gridY = cell.row
            case let dn as DecorationNode:
                dn.associatedDecoration?.gridX = cell.col
                dn.associatedDecoration?.gridY = cell.row
                if dn.type == .road {
                    retileRoads(around: oldCol, oldRow)
                    retileRoads(around: cell.col, cell.row)
                }
            default:
                break
            }
        } else {
            Haptics.warning()
        }
        let dest = gridToWorld(col: b.gridX, row: b.gridY)
        let settle = SCNAction.move(to: dest, duration: 0.18)
        settle.timingMode = .easeOut
        b.runAction(settle)
    }

    // MARK: - Placement hints (soft dots on free buildable cells)

    /// Quietly shows where building is possible — tiny translucent dots that
    /// appear only while placing or dragging, so they never fight the scenery.
    private func showPlacementHints(_ show: Bool) {
        hintsNode?.removeFromParentNode()
        hintsNode = nil
        guard show else { return }

        let group = SCNNode()
        let disc = SCNCylinder(radius: 0.05, height: 0.01)
        disc.firstMaterial?.diffuse.contents = UIColor(white: 1, alpha: 0.34)
        disc.firstMaterial?.lightingModel = .constant

        for col in 0..<cols {
            for row in 0..<rows {
                guard !hasOccupant(col: col, row: row, excluding: draggedNode) else { continue }
                let n = SCNNode(geometry: disc)
                let p = gridToWorld(col: col, row: row)
                n.position = SCNVector3(p.x, 0.02, p.z)
                group.addChildNode(n)
            }
        }

        // Show the corner lattice whenever greenery is in play — both when
        // placing a new one and when dragging an existing one around.
        let draggingGreenery = (draggedNode as? DecorationNode)?.type.canUseCornerAnchor ?? false
        if placingUsesAnchors || draggingGreenery {
            let small = SCNCylinder(radius: 0.035, height: 0.01)
            small.firstMaterial?.diffuse.contents = UIColor(red: 0.85, green: 0.98, blue: 0.80, alpha: 0.42)
            small.firstMaterial?.lightingModel = .constant
            for cx in 0...cols {
                for cy in 0...rows {
                    guard cornerFree(cx: cx, cy: cy, excluding: draggedNode as? DecorationNode) else { continue }
                    let n = SCNNode(geometry: small)
                    let p = cornerToWorld(cx: cx, cy: cy)
                    n.position = SCNVector3(p.x, 0.02, p.z)
                    group.addChildNode(n)
                }
            }
        }
        group.opacity = 0
        group.runAction(.fadeOpacity(to: 1, duration: 0.22))
        scnScene.rootNode.addChildNode(group)
        hintsNode = group
    }

    private func updateGhost(col: Int, row: Int) {
        guard let ghost = ghostNode, let dragged = draggedNode else { return }
        let valid = canPlace(offsets: occupiedOffsets(of: dragged),
                             at: col, row: row, excluding: dragged)
        ghost.geometry?.firstMaterial?.diffuse.contents = valid
            ? UIColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 0.45)
            : UIColor(red: 0.95, green: 0.30, blue: 0.25, alpha: 0.45)
        let bounds = offsetsBounds(of: dragged)
        let p = gridToWorld(col: col, row: row)
        ghost.position = SCNVector3(p.x + bounds.midX, 0.02, p.z + bounds.midY)
    }

    // MARK: - Celebration confetti

    func celebrate(at p: SCNVector3) {
        // Respect the system Reduce Motion setting — skip the confetti burst.
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let colors: [UIColor] = [
            UIColor(red: 1.00, green: 0.84, blue: 0.25, alpha: 1),
            UIColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1),
            UIColor(red: 0.55, green: 0.80, blue: 0.45, alpha: 1),
            UIColor(red: 0.98, green: 0.95, blue: 0.90, alpha: 1),
        ]
        for i in 0..<16 {
            let g = SCNBox(width: 0.09, height: 0.09, length: 0.02, chamferRadius: 0)
            g.firstMaterial?.diffuse.contents = colors[i % colors.count]
            g.firstMaterial?.lightingModel = .constant
            let c = SCNNode(geometry: g)
            c.position = SCNVector3(p.x, 0.8, p.z)
            scnScene.rootNode.addChildNode(c)

            let angle = Float(i) / 16 * 2 * .pi + .random(in: -0.2...0.2)
            let dist  = Float.random(in: 0.6...1.3)
            let up    = SCNAction.moveBy(x: CGFloat(cos(angle) * dist),
                                         y: CGFloat(Float.random(in: 0.7...1.3)),
                                         z: CGFloat(sin(angle) * dist), duration: 0.35)
            up.timingMode = .easeOut
            let down = SCNAction.moveBy(x: 0, y: -0.9, z: 0, duration: 0.45)
            down.timingMode = SCNActionTimingMode.easeIn
            let spin = SCNAction.rotateBy(x: CGFloat(Float.random(in: -4...4)),
                                          y: CGFloat(Float.random(in: -4...4)), z: 0, duration: 0.8)
            c.runAction(.sequence([
                .group([.sequence([up, down]), spin, .sequence([.wait(duration: 0.4), .fadeOut(duration: 0.4)])]),
                .removeFromParentNode()
            ]))
        }
    }
}

// MARK: - BuildingNode (3D)

final class BuildingNode: SCNNode {
    let type: BuildingType
    var gridX: Int
    var gridY: Int
    let isComplete: Bool
    var associatedBuilding: Building?
    private(set) var rotationSteps: Int

    init(type: BuildingType, gridX: Int, gridY: Int, isComplete: Bool = true,
         rotation: Int = 0, style: BuildingStyle = BuildingStyle()) {
        self.type = type
        self.gridX = gridX
        self.gridY = gridY
        self.isComplete = isComplete
        self.rotationSteps = rotation
        super.init()

        let variant = (abs(gridX) * 3 + abs(gridY) * 5) % 3
        let model = BuildingFactory.node(for: type, variant: variant, style: style)
        addChildNode(model)
        addChildNode(contactShadowNode(radius: 0.42))
        eulerAngles.y = Float(rotationSteps) * .pi / 2
        if !isComplete { opacity = 0.55 }
    }
    required init?(coder: NSCoder) { nil }

    func bounce() {
        removeAction(forKey: "bounce")
        let up = SCNAction.moveBy(x: 0, y: 0.18, z: 0, duration: 0.1)
        up.timingMode = .easeOut
        let dn = SCNAction.moveBy(x: 0, y: -0.18, z: 0, duration: 0.12)
        dn.timingMode = .easeIn
        runAction(.sequence([up, dn]), forKey: "bounce")
    }

    var canRotate: Bool { true }

    /// Cells occupied relative to the anchor, honoring rotation. A 2×1
    /// building's second cell swings around the anchor in 90° steps
    /// (+x → −z → −x → +z, matching a +90° yaw per step).
    var occupiedOffsets: [(dx: Int, dy: Int)] {
        Self.occupiedOffsets(footprint: type.footprint, steps: rotationSteps)
    }

    static func occupiedOffsets(footprint: (w: Int, l: Int), steps: Int) -> [(dx: Int, dy: Int)] {
        guard footprint.w * footprint.l > 1 else { return [(0, 0)] }
        let dirs = [(1, 0), (0, -1), (-1, 0), (0, 1)]
        return [(0, 0), dirs[((steps % 4) + 4) % 4]]
    }

    /// Rotate without validation — TownScene.tryRotate checks the target cells.
    func toggleRotation() {
        rotationSteps = (rotationSteps + 1) % 4
        associatedBuilding?.rotation = rotationSteps
        let spin = SCNAction.rotateBy(x: 0, y: .pi / 2, z: 0, duration: 0.22)
        spin.timingMode = .easeInEaseOut
        runAction(spin)
    }

    func setSelected(_ selected: Bool) {
        childNode(withName: "selectionRing", recursively: false)?.removeFromParentNode()
        guard selected else { return }
        let ring = SCNNode(geometry: SCNCylinder(radius: 0.62, height: 0.02))
        ring.name = "selectionRing"
        ring.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 1, alpha: 0.65)
        ring.geometry?.firstMaterial?.lightingModel = .constant
        ring.position = SCNVector3(0, -0.42, 0)
        ring.runAction(.repeatForever(.sequence([
            .fadeOpacity(to: 0.25, duration: 0.45),
            .fadeOpacity(to: 0.9,  duration: 0.45)
        ])))
        addChildNode(ring)
    }
}

// MARK: - Contact shadow (soft dark disc that grounds an object)

func contactShadowNode(radius: CGFloat) -> SCNNode {
    let g = SCNCylinder(radius: radius, height: 0.003)
    g.firstMaterial?.diffuse.contents = UIColor(white: 0, alpha: 0.12)
    g.firstMaterial?.lightingModel = .constant
    let n = SCNNode(geometry: g)
    n.position = SCNVector3(0, 0.0015, 0)
    n.castsShadow = false
    return n
}

// MARK: - GridOccupant (anything draggable on the grid)

protocol GridOccupant: AnyObject {
    var gridX: Int { get set }
    var gridY: Int { get set }
    func setSelected(_ selected: Bool)
}

extension BuildingNode: GridOccupant {}

// MARK: - DecorationNode (3D)

final class DecorationNode: SCNNode, GridOccupant {
    let type: DecorationItem
    var gridX: Int
    var gridY: Int
    var associatedDecoration: PlacedDecoration?
    /// True when (gridX, gridY) addresses a tile corner rather than a tile centre.
    /// Greenery can be dragged between the two lattices, so this can change.
    var isCornerAnchor: Bool
    private var rotationSteps: Int

    /// Roads auto-tile and the pond has a multi-cell footprint — those two
    /// keep their orientation; everything else rotates on double-tap.
    var canRotate: Bool { type != .road && type != .pond }

    init(type: DecorationItem, gridX: Int, gridY: Int, rotation: Int = 0,
         isCornerAnchor: Bool = false, variant: Int = 0) {
        self.type = type
        self.gridX = gridX
        self.gridY = gridY
        self.isCornerAnchor = isCornerAnchor
        self.rotationSteps = rotation
        super.init()
        DecorationFactory.build(into: self, type: type, variant: variant)
        if let r = Self.shadowRadius(for: type) {
            addChildNode(contactShadowNode(radius: r))
        }
        if canRotate {
            eulerAngles.y = Float(rotationSteps) * .pi / 2
        }

        // Vegetation variety: no two trees look identical. Deterministic per
        // cell, so the forest stays stable between app launches.
        if type == .tree || type == .leafTree || type == .fruitTree || type == .bush {
            let seed = abs(gridX * 73 + gridY * 151)
            let s = 0.82 + Float(seed % 100) / 100 * 0.36        // 0.82…1.18
            scale = SCNVector3(s, s, s)
            if rotationSteps == 0 {
                eulerAngles.y = Float(seed % 360) * .pi / 180    // random facing
            }
        }
    }

    func toggleRotation() {
        guard canRotate else { return }
        rotationSteps = (rotationSteps + 1) % 4
        associatedDecoration?.rotation = rotationSteps
        let spin = SCNAction.rotateBy(x: 0, y: .pi / 2, z: 0, duration: 0.22)
        spin.timingMode = .easeInEaseOut
        runAction(spin)
    }

    // MARK: - Living decorations

    /// Fire pit: cold and dark by day, burning after dusk.
    func setFireLit(_ lit: Bool) {
        guard type == .firePit,
              let fire = childNode(withName: "fire", recursively: true) else { return }
        guard fire.isHidden == lit else { return }      // already in the right state
        fire.isHidden = !lit
        fire.removeAllActions()
        guard lit, !UIAccessibility.isReduceMotionEnabled else { return }
        // Gentle flicker
        let flicker = SCNAction.sequence([
            .scale(to: 1.12, duration: 0.32),
            .scale(to: 0.94, duration: 0.28),
            .scale(to: 1.04, duration: 0.24),
        ])
        flicker.timingMode = .easeInEaseOut
        fire.runAction(.repeatForever(flicker))
    }

    /// Mirrors `PlacedDecoration.hasFood` as a plain flag on the node, so the
    /// SceneKit render thread never has to touch a SwiftData model.
    private(set) var bowlHasFood = false

    /// Hang (or clear) the name sign on the doghouse gable.
    func setKennelName(_ name: String) {
        guard type == .doghouse else { return }
        childNode(withName: "namePlate", recursively: true)?.removeFromParentNode()
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let px = CGSize(width: 320, height: 110)
        let image = UIGraphicsImageRenderer(size: px).image { ctx in
            // Wooden board with a darker rim
            UIColor(red: 0.52, green: 0.36, blue: 0.22, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: px))
            UIColor(red: 0.85, green: 0.71, blue: 0.47, alpha: 1).setFill()
            ctx.fill(CGRect(x: 8, y: 8, width: px.width - 16, height: px.height - 16))

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            // Long names simply get a smaller font so they still fit the board.
            let size: CGFloat = text.count <= 6 ? 58 : (text.count <= 10 ? 44 : 32)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: UIColor(red: 0.30, green: 0.19, blue: 0.11, alpha: 1),
                .paragraphStyle: style,
            ]
            let bounds = CGRect(x: 12, y: (px.height - size * 1.25) / 2,
                                width: px.width - 24, height: size * 1.25)
            (text as NSString).draw(in: bounds, withAttributes: attrs)
        }

        let mat = SCNMaterial()
        mat.diffuse.contents = image
        mat.lightingModel = .lambert
        mat.isDoubleSided = true

        let plane = SCNPlane(width: 0.36, height: 0.125)
        plane.materials = [mat]
        let n = SCNNode(geometry: plane)
        n.name = "namePlate"
        n.position = SCNVector3(0, 0.38, 0.37)   // on the gable, above the opening
        addChildNode(n)
    }

    /// Doghouse bowl: show or hide the kibble.
    func setBowlFilled(_ filled: Bool) {
        guard type == .doghouse else { return }
        bowlHasFood = filled
        childNode(withName: "bowlFood", recursively: true)?.isHidden = !filled
    }

    /// Where a pet should curl up inside this doghouse (world space offset from
    /// the node), plus the facing that looks out of the opening.
    var doghouseBed: (offset: SCNVector3, yaw: Float)? {
        guard type == .doghouse else { return nil }
        let yaw = eulerAngles.y
        // Lying in the doorway with head and chest out, body inside — the way a
        // dog actually rests in its kennel, and the only pose that stays visible
        // from the game's isometric angle.
        let depth: Float = 0.18
        return (SCNVector3(depth * sin(yaw), 0.02, depth * cos(yaw)), yaw)
    }

    /// Krmítko: a small bird drops in every now and then, hops, and leaves.
    func startFeederVisits() {
        guard type == .birdFeeder, !UIAccessibility.isReduceMotionEnabled else { return }
        let bird = SCNNode()
        bird.name = "feederBird"
        let body = SCNSphere(radius: 0.038)
        body.segmentCount = 8
        body.materials = [{ let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.45, green: 0.50, blue: 0.58, alpha: 1)
            m.lightingModel = .lambert; return m }()]
        let b = SCNNode(geometry: body)
        b.scale = SCNVector3(1, 0.9, 1.25)
        bird.addChildNode(b)

        let head = SCNSphere(radius: 0.024)
        head.segmentCount = 8
        head.materials = body.materials
        let h = SCNNode(geometry: head)
        h.position = SCNVector3(0, 0.028, 0.038)
        bird.addChildNode(h)

        let beak = SCNCone(topRadius: 0, bottomRadius: 0.009, height: 0.026)
        beak.radialSegmentCount = 5
        beak.materials = [{ let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.90, green: 0.68, blue: 0.25, alpha: 1)
            m.lightingModel = .lambert; return m }()]
        let bk = SCNNode(geometry: beak)
        bk.position = SCNVector3(0, 0.024, 0.062)
        bk.eulerAngles.x = .pi / 2
        bird.addChildNode(bk)

        bird.position = SCNVector3(0.06, 0.47, 0.02)
        bird.opacity = 0
        addChildNode(bird)

        // Land, hop about pecking, then leave — repeating with quiet gaps.
        let hop = SCNAction.sequence([
            .moveBy(x: -0.07, y: 0.05, z: 0.02, duration: 0.18),
            .moveBy(x: 0, y: -0.05, z: 0, duration: 0.12),
            .wait(duration: 0.5),
            .moveBy(x: 0.09, y: 0.05, z: -0.03, duration: 0.18),
            .moveBy(x: -0.02, y: -0.05, z: 0.01, duration: 0.12),
            .wait(duration: 0.7),
        ])
        let visit = SCNAction.sequence([
            .fadeIn(duration: 0.35),
            .repeat(hop, count: 2),
            .fadeOut(duration: 0.4),
            .wait(duration: Double.random(in: 12...26)),
        ])
        bird.runAction(.sequence([
            .wait(duration: Double.random(in: 2...10)),
            .repeatForever(visit),
        ]))
    }

    private static func shadowRadius(for type: DecorationItem) -> CGFloat? {
        switch type {
        case .tree:       0.20
        case .leafTree:   0.25
        case .fruitTree:  0.22
        case .bush:       0.14
        case .bench:      0.17
        case .fountain:   0.32
        case .doghouse:   0.28
        case .birdFeeder: 0.12
        case .firePit:    0.30
        case .road, .pond: nil    // flat, sit in the ground already
        }
    }
    required init?(coder: NSCoder) { nil }

    /// Roads re-render whenever a neighbouring road appears/disappears.
    func rebuildRoad(n: Bool, e: Bool, s: Bool, w: Bool) {
        guard type == .road else { return }
        childNodes.forEach { $0.removeFromParentNode() }
        DecorationFactory.buildRoad(self, n: n, e: e, s: s, w: w)
    }

    func setSelected(_ selected: Bool) {
        childNode(withName: "selectionRing", recursively: false)?.removeFromParentNode()
        guard selected else { return }
        let ring = SCNNode(geometry: SCNCylinder(radius: 0.52, height: 0.02))
        ring.name = "selectionRing"
        ring.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 1, alpha: 0.65)
        ring.geometry?.firstMaterial?.lightingModel = .constant
        ring.position = SCNVector3(0, -0.42, 0)
        ring.runAction(.repeatForever(.sequence([
            .fadeOpacity(to: 0.25, duration: 0.45),
            .fadeOpacity(to: 0.9,  duration: 0.45)
        ])))
        addChildNode(ring)
    }
}

// MARK: - Building factory (low-poly compositions)

/// Per-building visual customization (roof color / facade). Index 0 = default.
struct BuildingStyle {
    var roof: Int = 0
    var facade: Int = 0
}

enum BuildingFactory {

    private static var style = BuildingStyle()

    /// Customization palettes — index 0 means "builder's default".
    static let roofPalette: [(r: CGFloat, g: CGFloat, b: CGFloat)?] = [
        nil,
        (0.36, 0.48, 0.66),   // břidlicová modrá
        (0.44, 0.62, 0.45),   // šalvějová zelená
        (0.55, 0.42, 0.62),   // švestková
        (0.30, 0.30, 0.33),   // grafitová
    ]
    static let facadePalette: [(r: CGFloat, g: CGFloat, b: CGFloat)?] = [
        nil,
        (0.92, 0.90, 0.84),   // bílá omítka
        (0.90, 0.80, 0.55),   // teplá okrová
        (0.85, 0.68, 0.62),   // růžová
        (0.72, 0.78, 0.82),   // holubí šeď
    ]

    static func node(for type: BuildingType, variant: Int = 0,
                     style st: BuildingStyle = BuildingStyle()) -> SCNNode {
        style = st
        let root = SCNNode()
        let f: CGFloat = variant == 1 ? 1.06 : (variant == 2 ? 0.94 : 1.0)
        switch type {
        case .well:       buildWell(root)
        case .cottage:    buildCottage(root, f, variant)
        case .house:      buildHouse(root, f, variant)
        case .barn:       buildBarn(root, f)
        case .farm:       buildFarm(root, f)
        case .stables:    buildStables(root, f)
        case .shop:       buildShop(root, f)
        case .flowerShop: buildFlowerShop(root, f)
        case .post:       buildPost(root, f)
        case .school:     buildSchool(root, f)
        case .tower:      buildTower(root, f)
        case .tavern:     buildTavern(root, f)
        case .blacksmith: buildBlacksmith(root, f)
        case .market:     buildMarket(root, f)
        case .townhall:   buildTownhall(root, f)
        case .church:     buildChurch(root, f)
        case .fortress:   buildFortress(root, f)
        case .cathedral:  buildCathedral(root, f)
        case .castle:     buildCastle(root, f)
        }
        style = BuildingStyle()
        return root
    }

    /// Roof material honouring the user's roof-color choice.
    private static func roofMat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ f: CGFloat = 1) -> SCNMaterial {
        if style.roof > 0, style.roof < roofPalette.count, let o = roofPalette[style.roof] {
            return mat(o.r, o.g, o.b, f)
        }
        return mat(r, g, b, f)
    }

    /// Facade material honouring the user's facade choice (keeps the texture style).
    private static func facadeMat(_ tex: TexStyle?, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                                  _ f: CGFloat = 1) -> SCNMaterial {
        let c: (CGFloat, CGFloat, CGFloat)
        if style.facade > 0, style.facade < facadePalette.count, let o = facadePalette[style.facade] {
            c = (o.r, o.g, o.b)
        } else {
            c = (r, g, b)
        }
        if let tex { return texMat(tex, c.0, c.1, c.2, f) }
        return mat(c.0, c.1, c.2, f)
    }

    // MARK: Shared materials / helpers

    private static func mat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ f: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: min(1, r*f), green: min(1, g*f), blue: min(1, b*f), alpha: 1)
        m.lightingModel = .lambert
        return m
    }

    // MARK: Subtle procedural textures (planks / stone blocks / plaster)

    private enum TexStyle: String { case planks, stone, plaster }
    private static var texCache: [String: UIImage] = [:]

    private static func texMat(_ style: TexStyle, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                               _ f: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = texture(style, r: min(1, r*f), g: min(1, g*f), b: min(1, b*f))
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.lightingModel = .lambert
        return m
    }

    private static func texture(_ style: TexStyle, r: CGFloat, g: CGFloat, b: CGFloat) -> UIImage {
        let key = "\(style.rawValue)|\(Int(r*255)),\(Int(g*255)),\(Int(b*255))"
        if let img = texCache[key] { return img }

        let px: CGFloat = 256
        var seed: UInt64 = 0x7E97_0000 &+ UInt64(r * 255) &+ UInt64(g * 255) << 8
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: px, height: px))
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(red: r, green: g, blue: b, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: px, height: px))

            switch style {
            case .planks:
                let step: CGFloat = 36
                for i in 0..<Int(px / step) {
                    let x = CGFloat(i) * step
                    // per-plank brightness variation
                    if i % 2 == 0 {
                        c.setFillColor(UIColor(white: 1, alpha: 0.030).cgColor)
                        c.fill(CGRect(x: x, y: 0, width: step, height: px))
                    }
                    c.setFillColor(UIColor(white: 0, alpha: 0.085).cgColor)
                    c.fill(CGRect(x: x, y: 0, width: 2.2, height: px))
                }

            case .stone:
                let rowH: CGFloat = 42
                let colW: CGFloat = 62
                for row in 0..<Int(px / rowH) {
                    let y = CGFloat(row) * rowH
                    c.setFillColor(UIColor(white: 0, alpha: 0.085).cgColor)
                    c.fill(CGRect(x: 0, y: y, width: px, height: 2))
                    let offset = row % 2 == 0 ? 0 : colW / 2
                    var x = -offset
                    while x < px {
                        c.setFillColor(UIColor(white: 0, alpha: 0.06).cgColor)
                        c.fill(CGRect(x: x, y: y, width: 2, height: rowH))
                        // occasional lighter block
                        if rnd() > 0.72 {
                            c.setFillColor(UIColor(white: 1, alpha: 0.035).cgColor)
                            c.fill(CGRect(x: x + 2, y: y + 2, width: colW - 2, height: rowH - 2))
                        }
                        x += colW
                    }
                }

            case .plaster:
                for _ in 0..<260 {
                    let light = rnd() > 0.5
                    c.setFillColor(UIColor(white: light ? 1 : 0, alpha: 0.035 + rnd() * 0.03).cgColor)
                    let s = 1.5 + rnd() * 3.5
                    c.fillEllipse(in: CGRect(x: rnd() * px, y: rnd() * px, width: s, height: s))
                }
            }
        }
        texCache[key] = img
        return img
    }

    @discardableResult
    private static func box(_ parent: SCNNode, w: CGFloat, h: CGFloat, l: CGFloat,
                            x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0,
                            material: SCNMaterial, chamfer: CGFloat = 0.02) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: min(chamfer, min(w, h, l)/2))
        g.materials = [material]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y + h/2, z)   // y = base
        parent.addChildNode(n)
        return n
    }

    /// Gable roof: a box rotated 45° about its ridge axis → diamond prism.
    /// `ridgeLen` runs along X (or Z when `alongZ`), `span` is the across-ridge width.
    /// Placed so the diamond center sits at `y` (bottom half hides inside the body).
    @discardableResult
    private static func gableRoof(_ parent: SCNNode, ridgeLen: CGFloat, span: CGFloat,
                                  x: CGFloat = 0, y: CGFloat, z: CGFloat = 0,
                                  material: SCNMaterial, alongZ: Bool = false) -> SCNNode {
        let s = span / 1.41421356   // square side so the diamond spans `span`
        let g = SCNBox(width: ridgeLen, height: s, length: s, chamferRadius: 0.015)
        g.materials = [material]
        let inner = SCNNode(geometry: g)
        inner.eulerAngles.x = .pi / 4
        let container = SCNNode()
        container.addChildNode(inner)
        if alongZ { container.eulerAngles.y = .pi / 2 }
        container.position = SCNVector3(x, y, z)
        parent.addChildNode(container)
        return container
    }

    @discardableResult
    private static func pyramidRoof(_ parent: SCNNode, w: CGFloat, h: CGFloat, l: CGFloat,
                                    x: CGFloat = 0, y: CGFloat, z: CGFloat = 0,
                                    material: SCNMaterial) -> SCNNode {
        let g = SCNPyramid(width: w, height: h, length: l)
        g.materials = [material]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y, z)
        parent.addChildNode(n)
        return n
    }

    @discardableResult
    private static func cone(_ parent: SCNNode, r: CGFloat, h: CGFloat,
                             x: CGFloat = 0, y: CGFloat, z: CGFloat = 0,
                             material: SCNMaterial) -> SCNNode {
        let g = SCNCone(topRadius: 0, bottomRadius: r, height: h)
        g.materials = [material]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y + h/2, z)
        parent.addChildNode(n)
        return n
    }

    @discardableResult
    private static func cylinder(_ parent: SCNNode, r: CGFloat, h: CGFloat,
                                 x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0,
                                 material: SCNMaterial) -> SCNNode {
        let g = SCNCylinder(radius: r, height: h)
        g.materials = [material]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y + h/2, z)
        parent.addChildNode(n)
        return n
    }

    private static func windowMat() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents  = UIColor(red: 0.99, green: 0.88, blue: 0.55, alpha: 1)
        m.emission.contents = UIColor(red: 0.45, green: 0.36, blue: 0.14, alpha: 1)
        m.lightingModel = .lambert
        return m
    }

    private static func glassMat() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents  = UIColor(red: 0.72, green: 0.85, blue: 0.95, alpha: 1)
        m.emission.contents = UIColor(red: 0.10, green: 0.16, blue: 0.22, alpha: 1)
        m.lightingModel = .lambert
        return m
    }

    /// Small window pane slightly proud of a wall facing +z or +x.
    private static func window(_ parent: SCNNode, x: CGFloat, y: CGFloat, z: CGFloat,
                               w: CGFloat = 0.13, h: CGFloat = 0.16, onXFace: Bool = false,
                               material: SCNMaterial? = nil) {
        let m = material ?? windowMat()
        let g = SCNBox(width: onXFace ? 0.03 : w, height: h, length: onXFace ? w : 0.03, chamferRadius: 0.005)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y, z)
        parent.addChildNode(n)
    }

    private static let doorMat  = mat(0.32, 0.24, 0.18)
    private static let stoneMat = mat(0.62, 0.60, 0.56)
    private static let darkStoneMat = mat(0.48, 0.46, 0.43)
    private static let woodMat  = mat(0.55, 0.40, 0.27)

    private static func door(_ parent: SCNNode, x: CGFloat = 0, z: CGFloat, w: CGFloat = 0.18, h: CGFloat = 0.30) {
        let g = SCNBox(width: w, height: h, length: 0.03, chamferRadius: 0.01)
        g.materials = [doorMat]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, h/2, z)
        parent.addChildNode(n)
    }

    // MARK: Individual buildings (footprint ≤ ~0.85)

    private static func buildWell(_ r: SCNNode) {
        cylinder(r, r: 0.24, h: 0.22, material: stoneMat)
        // posts
        box(r, w: 0.05, h: 0.5, l: 0.05, x: -0.22, y: 0, material: woodMat)
        box(r, w: 0.05, h: 0.5, l: 0.05, x:  0.22, y: 0, material: woodMat)
        pyramidRoof(r, w: 0.62, h: 0.22, l: 0.62, y: 0.5, material: mat(0.55, 0.34, 0.22))
        // water
        cylinder(r, r: 0.18, h: 0.02, y: 0.21, material: mat(0.42, 0.70, 0.86))
    }

    /// Chalupa: tři varianty podle pozice, ať sousedící chalupy nejsou kopie.
    private static func buildCottage(_ r: SCNNode, _ f: CGFloat, _ v: Int) {
        let body = facadeMat(.plaster, 0.87, 0.78, 0.64, f)
        // default terracotta / moss green / weathered brown roof per variant
        let roofDefaults: [(CGFloat, CGFloat, CGFloat)] = [
            (0.78, 0.42, 0.31), (0.48, 0.58, 0.40), (0.60, 0.44, 0.32),
        ]
        let rd = roofDefaults[v % roofDefaults.count]
        let roof = roofMat(rd.0, rd.1, rd.2, f)

        box(r, w: 0.72, h: 0.42, l: 0.58, material: body)
        gableRoof(r, ridgeLen: 0.80, span: 0.66, y: 0.42, material: roof)

        switch v % 3 {
        case 1:
            // mirrored layout, chimney on the right
            door(r, x: 0.18, z: 0.30)
            window(r, x: -0.2, y: 0.26, z: 0.30)
            box(r, w: 0.09, h: 0.30, l: 0.09, x: 0.2, y: 0.55, material: stoneMat)
            smoke(r, x: 0.2, y: 0.87, z: 0)
        case 2:
            // two front windows, no chimney, side window
            door(r, z: 0.30)
            window(r, x: -0.24, y: 0.26, z: 0.30)
            window(r, x: 0.24, y: 0.26, z: 0.30)
            window(r, x: 0.37, y: 0.26, z: 0.0, onXFace: true)
        default:
            door(r, z: 0.30)
            window(r, x: 0.24, y: 0.26, z: 0.30)
            window(r, x: 0.37, y: 0.26, z: 0.0, onXFace: true)
            box(r, w: 0.09, h: 0.30, l: 0.09, x: -0.2, y: 0.55, material: stoneMat)
            smoke(r, x: -0.2, y: 0.87, z: 0)
        }
    }

    /// Rodinný domek: patrový, tři varianty (barva střechy, zrcadlení, vikýř).
    private static func buildHouse(_ r: SCNNode, _ f: CGFloat, _ v: Int) {
        let body = facadeMat(.plaster, 0.92, 0.88, 0.79, f)
        let roofDefaults: [(CGFloat, CGFloat, CGFloat)] = [
            (0.56, 0.30, 0.26), (0.36, 0.44, 0.58), (0.44, 0.54, 0.40),
        ]
        let rd = roofDefaults[v % roofDefaults.count]
        let roof = roofMat(rd.0, rd.1, rd.2, f)
        let mirror: CGFloat = v % 3 == 1 ? -1 : 1

        // two-story body
        box(r, w: 0.68, h: 0.52, l: 0.56, material: body)
        gableRoof(r, ridgeLen: 0.76, span: 0.64, y: 0.52, material: roof)

        // door with a small step, ground-floor window, two upstairs windows
        door(r, x: mirror * -0.18, z: 0.29, w: 0.15, h: 0.26)
        box(r, w: 0.2, h: 0.03, l: 0.1, x: mirror * -0.18, z: 0.33, material: stoneMat, chamfer: 0.01)
        window(r, x: mirror * 0.17, y: 0.16, z: 0.29)
        window(r, x: -0.17, y: 0.40, z: 0.29)
        window(r, x: 0.17, y: 0.40, z: 0.29)

        // chimney
        box(r, w: 0.08, h: 0.26, l: 0.08, x: mirror * 0.2, y: 0.62, material: stoneMat)
        smoke(r, x: mirror * 0.2, y: 0.9, z: 0)

        // variant 2 gets a little dormer window on the roof front
        if v % 3 == 2 {
            box(r, w: 0.14, h: 0.12, l: 0.12, y: 0.56, z: 0.16, material: body)
            gableRoof(r, ridgeLen: 0.18, span: 0.16, y: 0.68, z: 0.16, material: roof, alongZ: true)
            window(r, x: 0, y: 0.62, z: 0.225, w: 0.08, h: 0.07)
        }

        // low hedge along the front edge
        let hedge = mat(0.44, 0.62, 0.36, f)
        box(r, w: 0.26, h: 0.09, l: 0.07, x: mirror * 0.16, z: 0.42, material: hedge, chamfer: 0.03)
    }

    private static func buildBarn(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.planks, 0.72, 0.32, 0.26, f)
        box(r, w: 0.82, h: 0.46, l: 0.6, material: body)
        gableRoof(r, ridgeLen: 0.9, span: 0.7, y: 0.46, material: roofMat(0.42, 0.30, 0.24, f))
        door(r, z: 0.31, w: 0.34, h: 0.38)
        // white trim X
        box(r, w: 0.36, h: 0.03, l: 0.02, y: 0.30, z: 0.315, material: mat(0.95, 0.93, 0.88))
    }

    /// Obchod — enclosed store with a striped awning and a display window.
    private static func buildShop(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.88, 0.83, 0.72, f)
        box(r, w: 0.72, h: 0.44, l: 0.56, material: body)
        // flat parapet roof
        box(r, w: 0.78, h: 0.06, l: 0.62, y: 0.44, material: roofMat(0.48, 0.42, 0.38, f), chamfer: 0.015)

        // display window + door on the front (+z)
        let glass = glassMat()
        let win = SCNBox(width: 0.30, height: 0.18, length: 0.03, chamferRadius: 0.008)
        win.materials = [glass]
        let wn = SCNNode(geometry: win)
        wn.position = SCNVector3(0.13, 0.20, 0.28)
        r.addChildNode(wn)
        door(r, x: -0.20, z: 0.28, w: 0.16, h: 0.28)

        // striped awning above the front
        let teal = mat(0.30, 0.56, 0.52), cream = mat(0.96, 0.94, 0.88)
        for i in 0..<4 {
            let seg = SCNBox(width: 0.155, height: 0.025, length: 0.22, chamferRadius: 0.008)
            seg.materials = [i % 2 == 0 ? teal : cream]
            let s = SCNNode(geometry: seg)
            s.position = SCNVector3(-0.233 + CGFloat(i) * 0.155, 0.36, 0.36)
            s.eulerAngles.x = -0.35
            r.addChildNode(s)
        }
        // small sign
        box(r, w: 0.22, h: 0.07, l: 0.02, y: 0.30, z: 0.29, material: mat(0.85, 0.68, 0.30, f))
    }

    /// Farma zabírá 2 pole: stavení na kotevním poli, velké oplocené pole vedle.
    private static func buildFarm(_ r: SCNNode, _ f: CGFloat) {
        // farmhouse fills the anchor cell
        box(r, w: 0.58, h: 0.36, l: 0.5, material: facadeMat(.plaster, 0.88, 0.80, 0.66, f))
        gableRoof(r, ridgeLen: 0.66, span: 0.58, y: 0.36, material: roofMat(0.70, 0.40, 0.28, f))
        door(r, z: 0.26, w: 0.14, h: 0.24)
        window(r, x: 0.18, y: 0.2, z: 0.26)
        box(r, w: 0.08, h: 0.22, l: 0.08, x: -0.18, y: 0.5, material: stoneMat)
        smoke(r, x: -0.18, y: 0.75, z: 0)

        // --- Big field on the second cell (x + 1) ---
        let gx: CGFloat = 1.0
        let field = SCNNode()
        field.position = SCNVector3(gx, 0, 0)
        r.addChildNode(field)

        box(field, w: 0.88, h: 0.035, l: 0.88, material: mat(0.46, 0.34, 0.23, f), chamfer: 0.012)

        // four crop rows
        for i in 0..<4 {
            let row = SCNBox(width: 0.76, height: 0.06, length: 0.07, chamferRadius: 0.025)
            row.materials = [mat(0.44, 0.64, 0.32, f)]
            let n = SCNNode(geometry: row)
            n.position = SCNVector3(0, 0.06, -0.3 + CGFloat(i) * 0.2)
            field.addChildNode(n)
        }

        // a couple of pumpkins between the rows
        for (px, pz) in [(-0.25, -0.2), (0.28, 0.2)] {
            let p = SCNSphere(radius: 0.05)
            p.segmentCount = 10
            p.materials = [mat(0.88, 0.52, 0.18, f)]
            let n = SCNNode(geometry: p)
            n.position = SCNVector3(CGFloat(px), 0.07, CGFloat(pz))
            n.scale = SCNVector3(1, 0.75, 1)
            field.addChildNode(n)
        }

        // fence around the three open sides of the field
        let wood = mat(0.55, 0.42, 0.28)
        for px in [-0.42, 0.0, 0.42] {
            box(field, w: 0.035, h: 0.14, l: 0.035, x: CGFloat(px), z: 0.44, material: wood)
            box(field, w: 0.035, h: 0.14, l: 0.035, x: CGFloat(px), z: -0.44, material: wood)
        }
        box(field, w: 0.86, h: 0.025, l: 0.02, y: 0.09, z: 0.44, material: wood)
        box(field, w: 0.86, h: 0.025, l: 0.02, y: 0.09, z: -0.44, material: wood)
        for pz in [-0.42, 0.0, 0.42] {
            box(field, w: 0.035, h: 0.14, l: 0.035, x: 0.44, z: CGFloat(pz), material: wood)
        }
        box(field, w: 0.02, h: 0.025, l: 0.86, x: 0.44, y: 0.09, material: wood)
    }

    /// Stáje — dlouhá dřevěná budova s výběhem a koňmi.
    private static func buildStables(_ r: SCNNode, _ f: CGFloat) {
        // long low stable at the back
        let stable = SCNNode()
        stable.position = SCNVector3(0, 0, -0.22)
        r.addChildNode(stable)
        box(stable, w: 0.84, h: 0.32, l: 0.34, material: facadeMat(.planks, 0.60, 0.44, 0.28, f))
        gableRoof(stable, ridgeLen: 0.92, span: 0.42, y: 0.32, material: roofMat(0.44, 0.32, 0.24, f))
        // stable doors
        for dx in [-0.24, 0.1] {
            door(stable, x: CGFloat(dx), z: 0.18, w: 0.16, h: 0.24)
        }

        // paddock fence in front
        let wood = mat(0.55, 0.42, 0.28)
        let fenceY: CGFloat = 0.09
        for px in [-0.38, 0.0, 0.38] {
            box(r, w: 0.03, h: 0.14, l: 0.03, x: CGFloat(px), z: 0.40, material: wood)
        }
        box(r, w: 0.78, h: 0.025, l: 0.02, y: fenceY, z: 0.40, material: wood)
        for side in [-0.39, 0.39] {
            box(r, w: 0.03, h: 0.14, l: 0.03, x: CGFloat(side), z: 0.12, material: wood)
            box(r, w: 0.02, h: 0.025, l: 0.30, x: CGFloat(side), y: fenceY, z: 0.26, material: wood)
        }

        // horses in the paddock
        horse(r, x: -0.16, z: 0.24, tone: (0.45, 0.30, 0.20), f: f, flip: false)
        horse(r, x: 0.18, z: 0.28, tone: (0.62, 0.48, 0.34), f: f, flip: true)
    }

    /// Low-poly horse: body, head, legs, tail.
    private static func horse(_ parent: SCNNode, x: CGFloat, z: CGFloat,
                              tone: (CGFloat, CGFloat, CGFloat), f: CGFloat, flip: Bool) {
        let h = SCNNode()
        h.position = SCNVector3(x, 0, z)
        h.eulerAngles.y = flip ? .pi * 0.75 : -.pi * 0.25
        parent.addChildNode(h)
        let coat = mat(tone.0, tone.1, tone.2, f)
        let dark = mat(tone.0 * 0.7, tone.1 * 0.7, tone.2 * 0.7, f)

        // body
        box(h, w: 0.17, h: 0.09, l: 0.08, y: 0.10, material: coat, chamfer: 0.025)
        // legs
        for (lx, lz) in [(-0.06, -0.025), (0.06, -0.025), (-0.06, 0.025), (0.06, 0.025)] {
            box(h, w: 0.02, h: 0.10, l: 0.02, x: CGFloat(lx), z: CGFloat(lz), material: dark)
        }
        // neck + head
        let neck = SCNBox(width: 0.035, height: 0.09, length: 0.035, chamferRadius: 0.01)
        neck.materials = [coat]
        let nk = SCNNode(geometry: neck)
        nk.position = SCNVector3(0.085, 0.20, 0)
        nk.eulerAngles.z = -0.4
        h.addChildNode(nk)
        box(h, w: 0.065, h: 0.035, l: 0.04, x: 0.125, y: 0.225, material: coat, chamfer: 0.012)
        // tail
        let tail = SCNBox(width: 0.02, height: 0.07, length: 0.02, chamferRadius: 0.008)
        tail.materials = [dark]
        let tl = SCNNode(geometry: tail)
        tl.position = SCNVector3(-0.09, 0.10, 0)
        tl.eulerAngles.z = 0.35
        h.addChildNode(tl)
    }

    /// Květinářství: útulný krámek s růžovou markýzou a truhlíky plnými květin.
    private static func buildFlowerShop(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.90, 0.84, 0.78, f)
        box(r, w: 0.66, h: 0.42, l: 0.54, material: body)
        gableRoof(r, ridgeLen: 0.74, span: 0.62, y: 0.42, material: roofMat(0.55, 0.42, 0.48, f))

        // display window + door
        let glass = glassMat()
        let win = SCNBox(width: 0.26, height: 0.16, length: 0.03, chamferRadius: 0.008)
        win.materials = [glass]
        let wn = SCNNode(geometry: win)
        wn.position = SCNVector3(0.12, 0.19, 0.27)
        r.addChildNode(wn)
        door(r, x: -0.18, z: 0.27, w: 0.15, h: 0.27)

        // pink striped awning
        let pink = mat(0.90, 0.55, 0.62, f), cream = mat(0.96, 0.94, 0.88)
        for i in 0..<4 {
            let seg = SCNBox(width: 0.14, height: 0.022, length: 0.2, chamferRadius: 0.008)
            seg.materials = [i % 2 == 0 ? pink : cream]
            let s = SCNNode(geometry: seg)
            s.position = SCNVector3(-0.21 + CGFloat(i) * 0.14, 0.35, 0.34)
            s.eulerAngles.x = -0.35
            r.addChildNode(s)
        }

        // flower boxes out front, with colorful blossoms
        let soil = mat(0.42, 0.31, 0.22)
        let blossoms: [(CGFloat, CGFloat, CGFloat)] = [
            (0.95, 0.45, 0.50), (0.98, 0.80, 0.30), (0.75, 0.50, 0.85), (0.95, 0.60, 0.30),
        ]
        for (bi, bx) in [(-0.2, -0.36), (0, 0.36)].enumerated() {
            _ = bx
            let x = bi == 0 ? -0.18 : 0.2
            box(r, w: 0.26, h: 0.08, l: 0.1, x: CGFloat(x), z: 0.4, material: soil, chamfer: 0.01)
            for j in 0..<3 {
                let c = blossoms[(bi * 2 + j) % blossoms.count]
                let head = SCNSphere(radius: 0.026)
                head.segmentCount = 8
                head.materials = [mat(c.0, c.1, c.2)]
                let n = SCNNode(geometry: head)
                n.position = SCNVector3(CGFloat(x) - 0.08 + CGFloat(j) * 0.08, 0.12, 0.4)
                r.addChildNode(n)
            }
        }
    }

    /// Pošta: teplá okrová budova s cedulí a modrou schránkou před vchodem.
    private static func buildPost(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.90, 0.76, 0.44, f)
        box(r, w: 0.74, h: 0.5, l: 0.58, material: body)
        pyramidRoof(r, w: 0.82, h: 0.26, l: 0.66, y: 0.5, material: roofMat(0.42, 0.38, 0.35, f))
        door(r, z: 0.3, w: 0.18, h: 0.3)
        window(r, x: -0.22, y: 0.32, z: 0.3)
        window(r, x: 0.22, y: 0.32, z: 0.3)

        // white sign with a letter emblem
        box(r, w: 0.3, h: 0.1, l: 0.02, y: 0.4, z: 0.3, material: mat(0.96, 0.95, 0.92))
        box(r, w: 0.1, h: 0.06, l: 0.015, y: 0.42, z: 0.315, material: mat(0.30, 0.48, 0.72, f))

        // blue mailbox by the door
        box(r, w: 0.1, h: 0.16, l: 0.09, x: 0.3, z: 0.38, material: mat(0.28, 0.45, 0.72, f), chamfer: 0.02)
        box(r, w: 0.035, h: 0.1, l: 0.035, x: 0.3, y: -0.1 + 0.1, z: 0.38, material: darkStoneMat)
    }

    /// Škola: cihlová budova s bílým lemem a zvoničkou na hřebeni.
    private static func buildSchool(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.stone, 0.76, 0.46, 0.36, f)
        box(r, w: 0.8, h: 0.6, l: 0.6, material: body)
        gableRoof(r, ridgeLen: 0.88, span: 0.7, y: 0.6, material: roofMat(0.38, 0.36, 0.40, f))

        // white door frame + door, two rows of windows
        box(r, w: 0.24, h: 0.36, l: 0.02, y: 0, z: 0.3, material: mat(0.95, 0.94, 0.90))
        door(r, z: 0.315, w: 0.18, h: 0.32)
        for (x, y) in [(-0.26, 0.2), (0.26, 0.2), (-0.26, 0.45), (0.0, 0.45), (0.26, 0.45)] {
            window(r, x: CGFloat(x), y: CGFloat(y), z: 0.31)
        }

        // bell gable on the ridge
        box(r, w: 0.16, h: 0.16, l: 0.1, y: 0.92, material: mat(0.95, 0.94, 0.90))
        pyramidRoof(r, w: 0.2, h: 0.1, l: 0.14, y: 1.08, material: roofMat(0.38, 0.36, 0.40, f))
        let bell = SCNSphere(radius: 0.035)
        bell.segmentCount = 8
        bell.materials = [mat(0.85, 0.70, 0.30)]
        let b = SCNNode(geometry: bell)
        b.position = SCNVector3(0, 0.98, 0)
        r.addChildNode(b)
    }

    /// Věž: kamenná hláska s ochozem, kuželovou střechou a praporkem.
    private static func buildTower(_ r: SCNNode, _ f: CGFloat) {
        let stone = facadeMat(.stone, 0.62, 0.60, 0.56, f)
        cylinder(r, r: 0.22, h: 0.95, material: stone)

        // wooden lookout platform
        cylinder(r, r: 0.28, h: 0.05, y: 0.95, material: mat(0.55, 0.40, 0.27, f))
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * 2 * .pi
            box(r, w: 0.03, h: 0.12, l: 0.03,
                x: cos(a) * 0.25, y: 1.0, z: sin(a) * 0.25,
                material: mat(0.55, 0.40, 0.27, f))
        }

        cone(r, r: 0.3, h: 0.34, y: 1.12, material: roofMat(0.42, 0.34, 0.55, f))

        // window slit + flag
        window(r, x: 0, y: 0.6, z: 0.21, w: 0.07, h: 0.16)
        cylinder(r, r: 0.012, h: 0.2, y: 1.46, material: mat(0.85, 0.82, 0.75))
        box(r, w: 0.11, h: 0.06, l: 0.01, x: 0.065, y: 1.58, material: mat(0.88, 0.28, 0.25, f))
    }

    /// Hostinec zabírá 2 pole: budova na kotevním poli, pivní zahrádka vedle.
    private static func buildTavern(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.planks, 0.76, 0.61, 0.42, f)
        box(r, w: 0.76, h: 0.56, l: 0.6, material: body)
        gableRoof(r, ridgeLen: 0.84, span: 0.70, y: 0.56, material: roofMat(0.36, 0.48, 0.60, f))
        door(r, x: -0.15, z: 0.31)
        window(r, x: 0.15, y: 0.2, z: 0.31)
        window(r, x: -0.1, y: 0.44, z: 0.31)
        window(r, x: 0.18, y: 0.44, z: 0.31)
        // hanging sign
        box(r, w: 0.14, h: 0.12, l: 0.02, x: 0.33, y: 0.4, z: 0.32, material: mat(0.9, 0.75, 0.35))
        box(r, w: 0.09, h: 0.3, l: 0.09, x: 0.18, y: 0.7, material: stoneMat)
        smoke(r, x: 0.18, y: 1.02, z: 0)

        // --- Zahrádka na druhém poli (x + 1) ---
        let gx: CGFloat = 1.0
        let wood = mat(0.58, 0.43, 0.28, f)

        // patio deck
        box(r, w: 0.88, h: 0.035, l: 0.88, x: gx, material: mat(0.72, 0.60, 0.44, f), chamfer: 0.015)

        // parasol
        cylinder(r, r: 0.018, h: 0.52, x: gx - 0.08, z: -0.05, material: mat(0.85, 0.82, 0.75))
        cone(r, r: 0.32, h: 0.14, x: gx - 0.08, y: 0.52, z: -0.05, material: mat(0.85, 0.32, 0.28, f))

        // table + two stools under the parasol
        cylinder(r, r: 0.035, h: 0.2, x: gx - 0.08, y: 0.035, z: -0.05, material: wood)
        cylinder(r, r: 0.16, h: 0.03, x: gx - 0.08, y: 0.235, z: -0.05, material: mat(0.68, 0.52, 0.34, f))
        for (sx, sz) in [(-0.32, 0.08), (0.13, -0.16)] {
            cylinder(r, r: 0.06, h: 0.13, x: gx + CGFloat(sx), y: 0.035, z: CGFloat(sz), material: wood)
        }

        // second small table by the fence
        cylinder(r, r: 0.03, h: 0.17, x: gx + 0.25, y: 0.035, z: 0.28, material: wood)
        cylinder(r, r: 0.12, h: 0.03, x: gx + 0.25, y: 0.205, z: 0.28, material: mat(0.68, 0.52, 0.34, f))

        // beer barrel in the corner
        cylinder(r, r: 0.09, h: 0.2, x: gx + 0.32, y: 0.035, z: -0.3, material: mat(0.48, 0.34, 0.20, f))
        cylinder(r, r: 0.095, h: 0.02, x: gx + 0.32, y: 0.12, z: -0.3, material: mat(0.35, 0.32, 0.30))

        // low fence on the far edge
        for pz in [-0.36, 0.0, 0.36] {
            box(r, w: 0.035, h: 0.15, l: 0.035, x: gx + 0.42, z: CGFloat(pz), material: wood)
        }
        box(r, w: 0.02, h: 0.03, l: 0.8, x: gx + 0.42, y: 0.1, material: wood)
    }

    /// Gentle chimney smoke; skipped when Reduce Motion is on.
    private static func smoke(_ parent: SCNNode, x: CGFloat, y: CGFloat, z: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let ps = SCNParticleSystem()
        ps.birthRate = 1.4
        ps.particleLifeSpan = 2.6
        ps.particleLifeSpanVariation = 0.6
        ps.particleVelocity = 0.16
        ps.particleVelocityVariation = 0.05
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 10
        ps.particleSize = 0.055
        ps.particleSizeVariation = 0.02
        ps.particleColor = UIColor(white: 0.93, alpha: 0.32)
        ps.isAffectedByGravity = false
        ps.acceleration = SCNVector3(0.02, 0.04, 0)   // slow drift with the wind
        let n = SCNNode()
        n.position = SCNVector3(x, y, z)
        n.addParticleSystem(ps)
        parent.addChildNode(n)
    }

    private static func buildBlacksmith(_ r: SCNNode, _ f: CGFloat) {
        box(r, w: 0.78, h: 0.44, l: 0.6, material: mat(0.50, 0.47, 0.44, f))
        gableRoof(r, ridgeLen: 0.86, span: 0.68, y: 0.44, material: mat(0.30, 0.28, 0.26, f))
        door(r, x: -0.14, z: 0.31, w: 0.24, h: 0.34)
        window(r, x: 0.2, y: 0.26, z: 0.31, material: windowMat())
        // big chimney
        box(r, w: 0.14, h: 0.5, l: 0.14, x: 0.24, y: 0.4, material: darkStoneMat)
        smoke(r, x: 0.24, y: 0.92, z: 0)
    }

    private static func buildMarket(_ r: SCNNode, _ f: CGFloat) {
        box(r, w: 0.8, h: 0.3, l: 0.6, material: mat(0.88, 0.76, 0.54, f))
        // striped awning: alternating red/white segments
        let red = mat(0.83, 0.36, 0.30), white = mat(0.96, 0.94, 0.90)
        for i in 0..<5 {
            let seg = SCNBox(width: 0.176, height: 0.03, length: 0.72, chamferRadius: 0.01)
            seg.materials = [i % 2 == 0 ? red : white]
            let n = SCNNode(geometry: seg)
            n.position = SCNVector3(-0.352 + CGFloat(i) * 0.176, 0.52, 0.02)
            n.eulerAngles.x = -0.16
            r.addChildNode(n)
        }
        // posts
        for sx in [-0.36, 0.36] {
            box(r, w: 0.05, h: 0.5, l: 0.05, x: CGFloat(sx), y: 0, z: 0.26, material: woodMat)
        }
        // goods
        box(r, w: 0.14, h: 0.12, l: 0.14, x: -0.18, y: 0.3, z: 0.1, material: mat(0.85, 0.55, 0.25))
        box(r, w: 0.14, h: 0.10, l: 0.14, x: 0.1, y: 0.3, z: 0.14, material: mat(0.55, 0.72, 0.40))
    }

    private static func buildTownhall(_ r: SCNNode, _ f: CGFloat) {
        let body = mat(0.79, 0.76, 0.71, f)
        box(r, w: 0.8, h: 0.72, l: 0.62, material: body)
        pyramidRoof(r, w: 0.88, h: 0.34, l: 0.7, y: 0.72, material: mat(0.37, 0.62, 0.52, f))
        door(r, z: 0.32, w: 0.2, h: 0.32)
        for (x, y) in [(-0.22, 0.3), (0.22, 0.3), (-0.22, 0.55), (0.0, 0.55), (0.22, 0.55)] {
            window(r, x: CGFloat(x), y: CGFloat(y), z: 0.32)
        }
        // clock
        cylinder(r, r: 0.07, h: 0.02, y: 0.6, z: 0.0, material: mat(0.95, 0.93, 0.85))
            .eulerAngles.x = .pi / 2
        // small bell tower
        box(r, w: 0.18, h: 0.24, l: 0.18, y: 1.06, material: body)
        pyramidRoof(r, w: 0.24, h: 0.16, l: 0.24, y: 1.3, material: mat(0.37, 0.62, 0.52, f))
    }

    private static func buildChurch(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.90, 0.88, 0.83, f)
        let roof = roofMat(0.36, 0.48, 0.66, f)
        // nave
        box(r, w: 0.5, h: 0.5, l: 0.72, x: 0.1, material: body)
        gableRoof(r, ridgeLen: 0.8, span: 0.56, x: 0.1, y: 0.5, material: roof, alongZ: true)
        // tower
        box(r, w: 0.28, h: 0.86, l: 0.28, x: -0.28, material: body)
        cone(r, r: 0.21, h: 0.4, x: -0.28, y: 0.86, material: roof)
        // cross
        box(r, w: 0.03, h: 0.16, l: 0.03, x: -0.28, y: 1.26, material: mat(0.9, 0.85, 0.6))
        box(r, w: 0.10, h: 0.03, l: 0.03, x: -0.28, y: 1.35, material: mat(0.9, 0.85, 0.6))
        door(r, x: -0.28, z: 0.16)
        window(r, x: 0.1, y: 0.32, z: 0.37)
        window(r, x: -0.28, y: 0.55, z: 0.16, w: 0.1, h: 0.2)
    }

    private static func buildFortress(_ r: SCNNode, _ f: CGFloat) {
        let stone = texMat(.stone, 0.60, 0.58, 0.54, f)
        box(r, w: 0.72, h: 0.6, l: 0.72, material: stone, chamfer: 0.01)
        // corner towers
        for (x, z) in [(-0.34, -0.34), (0.34, -0.34), (-0.34, 0.34), (0.34, 0.34)] {
            cylinder(r, r: 0.12, h: 0.78, x: CGFloat(x), z: CGFloat(z), material: darkStoneMat)
            cylinder(r, r: 0.14, h: 0.05, x: CGFloat(x), y: 0.78, z: CGFloat(z), material: stone)
        }
        // crenellations
        for i in 0..<4 {
            let t = -0.27 + CGFloat(i) * 0.18
            box(r, w: 0.1, h: 0.1, l: 0.06, x: t, y: 0.6, z: 0.33, material: stone, chamfer: 0.01)
            box(r, w: 0.06, h: 0.1, l: 0.1, x: 0.33, y: 0.6, z: t, material: stone, chamfer: 0.01)
        }
        door(r, z: 0.37, w: 0.22, h: 0.3)
    }

    private static func buildCathedral(_ r: SCNNode, _ f: CGFloat) {
        let body  = texMat(.stone, 0.87, 0.82, 0.73, f)   // warm sandstone
        let roof  = mat(0.32, 0.46, 0.56, f)              // slate teal
        let spire = mat(0.28, 0.40, 0.50, f)
        let gold  = mat(0.94, 0.80, 0.40, f)

        // Long, tall nave with a steep roof
        box(r, w: 0.56, h: 0.92, l: 0.82, z: -0.02, material: body)
        gableRoof(r, ridgeLen: 0.86, span: 0.64, y: 0.92, z: -0.02, material: roof, alongZ: true)

        // Buttresses down both sides of the nave
        for zz in [-0.28, -0.06, 0.16] as [CGFloat] {
            box(r, w: 0.05, h: 0.66, l: 0.07, x: -0.31, z: zz, material: body)
            box(r, w: 0.05, h: 0.66, l: 0.07, x:  0.31, z: zz, material: body)
        }

        // Twin front towers with tall spires + gold tips
        for sx in [-0.32, 0.32] as [CGFloat] {
            box(r, w: 0.24, h: 1.4, l: 0.24, x: sx, z: 0.34, material: body)
            window(r, x: sx, y: 0.9, z: 0.47, w: 0.09, h: 0.2)
            cone(r, r: 0.185, h: 0.6, x: sx, y: 1.4, z: 0.34, material: spire)
            box(r, w: 0.035, h: 0.1, l: 0.035, x: sx, y: 2.0, z: 0.34, material: gold)
        }

        // Central crossing spire — the tallest point
        box(r, w: 0.2, h: 1.15, l: 0.2, z: -0.12, material: body)
        cone(r, r: 0.155, h: 0.72, y: 1.15, z: -0.12, material: spire)
        box(r, w: 0.03, h: 0.12, l: 0.03, y: 1.87, z: -0.12, material: gold)

        // Big rose window + arched door on the front facade
        cylinder(r, r: 0.13, h: 0.02, y: 0.6, z: 0.5, material: glassMat())
            .eulerAngles.x = .pi / 2
        door(r, z: 0.51, w: 0.2, h: 0.4)
    }

    private static func buildCastle(_ r: SCNNode, _ f: CGFloat) {
        let stone = texMat(.stone, 0.62, 0.59, 0.54, f)
        let roof  = mat(0.34, 0.40, 0.54, f)              // blue slate
        let pole  = mat(0.86, 0.83, 0.76, f)
        let flag  = mat(0.86, 0.30, 0.26, f)

        /// Row of merlons (battlement teeth) along a wall top.
        func merlons(alongX: Bool, fixed: CGFloat, top: CGFloat, span: CGFloat) {
            let count = 5
            for i in 0..<count {
                let t = -span / 2 + span * CGFloat(i) / CGFloat(count - 1)
                if alongX { box(r, w: 0.06, h: 0.09, l: 0.07, x: t, y: top, z: fixed, material: stone) }
                else      { box(r, w: 0.07, h: 0.09, l: 0.06, x: fixed, y: top, z: t, material: stone) }
            }
        }

        // Big central keep with a pyramid roof
        box(r, w: 0.5, h: 1.02, l: 0.5, material: stone, chamfer: 0.01)
        pyramidRoof(r, w: 0.6, h: 0.38, l: 0.6, y: 1.02, material: roof)
        box(r, w: 0.02, h: 0.24, l: 0.02, y: 1.4, material: pole)          // keep flag
        box(r, w: 0.14, h: 0.09, l: 0.01, x: 0.08, y: 1.55, material: flag)

        // Four tall corner towers with conical roofs
        for (x, z) in [(-0.39, -0.39), (0.39, -0.39), (-0.39, 0.39), (0.39, 0.39)] as [(CGFloat, CGFloat)] {
            cylinder(r, r: 0.12, h: 0.86, x: x, z: z, material: stone)
            cone(r, r: 0.17, h: 0.34, x: x, y: 0.86, z: z, material: roof)
        }

        // Curtain walls between the towers, topped with battlements
        box(r, w: 0.66, h: 0.44, l: 0.08, z: -0.39, material: stone, chamfer: 0.01)
        box(r, w: 0.66, h: 0.44, l: 0.08, z:  0.39, material: stone, chamfer: 0.01)
        box(r, w: 0.08, h: 0.44, l: 0.66, x: -0.39, material: stone, chamfer: 0.01)
        box(r, w: 0.08, h: 0.44, l: 0.66, x:  0.39, material: stone, chamfer: 0.01)
        merlons(alongX: true,  fixed: -0.39, top: 0.44, span: 0.6)
        merlons(alongX: true,  fixed:  0.39, top: 0.44, span: 0.6)
        merlons(alongX: false, fixed: -0.39, top: 0.44, span: 0.6)
        merlons(alongX: false, fixed:  0.39, top: 0.44, span: 0.6)

        // Gatehouse + door on the front wall
        box(r, w: 0.24, h: 0.56, l: 0.12, z: 0.42, material: stone, chamfer: 0.01)
        window(r, x: 0, y: 0.62, z: 0.27, w: 0.1, h: 0.14)
        door(r, z: 0.49, w: 0.18, h: 0.3)
    }
}

// MARK: - Decoration factory

enum DecorationFactory {

    static func node(for type: DecorationItem, variant: Int = 0) -> SCNNode {
        let root = SCNNode()
        build(into: root, type: type, variant: variant)
        return root
    }

    static func build(into root: SCNNode, type: DecorationItem, variant: Int = 0) {
        switch type {
        case .tree:      buildTree(root)
        case .leafTree:  buildLeafTree(root)
        case .fruitTree: buildFruitTree(root, variant)
        case .bush:      buildBush(root, variant)
        case .road:      buildRoad(root, n: false, e: false, s: false, w: false)
        case .bench:     buildBench(root)
        case .fountain:  buildFountain(root)
        case .pond:      buildPond(root)
        case .doghouse:   buildDoghouse(root)
        case .birdFeeder: buildBirdFeeder(root)
        case .firePit:    buildFirePit(root)
        }
    }

    /// Psí bouda — open front so you can see the dog asleep inside, plus a bowl.
    /// The opening faces +z (towards the camera in the default orientation).
    private static func buildDoghouse(_ r: SCNNode) {
        let wall = m(0.76, 0.53, 0.32)
        let wallDark = m(0.63, 0.43, 0.25)
        let roof = m(0.56, 0.29, 0.23)
        // Light enough that the sleeping dog stands out against it.
        let inside = m(0.40, 0.31, 0.24)

        // Sized so a curled-up dog genuinely fits, with a wide low opening so
        // you can actually see him in there.
        func slab(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat,
                  _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ mat: SCNMaterial,
                  chamfer: CGFloat = 0.012) {
            let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
            g.materials = [mat]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(x, y + h / 2, z)
            r.addChildNode(n)
        }

        let wallH: CGFloat = 0.30
        slab(0.72, 0.02, 0.66, 0, 0, 0, m(0.50, 0.36, 0.24))              // floor
        // Kept light enough that the sleeping dog reads against it.
        slab(0.60, 0.28, 0.58, 0, 0.02, -0.02, inside, chamfer: 0.008)    // interior
        slab(0.06, wallH, 0.66, -0.33, 0, 0, wall)                        // left wall
        slab(0.06, wallH, 0.66,  0.33, 0, 0, wall)                        // right wall
        slab(0.72, wallH, 0.06,  0, 0, -0.30, wallDark)                   // back wall
        // The front is left wide open: from the game's isometric angle a lintel
        // hides the whole interior, so the gable above the opening is the only
        // thing spanning the front.

        // Gable ends filling the triangle under the roof, front and back.
        for side in [0.33, -0.33] as [CGFloat] {
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: -0.36, y: 0))
            tri.addLine(to: CGPoint(x: 0.36, y: 0))
            tri.addLine(to: CGPoint(x: 0, y: 0.20))
            tri.close()
            let g = SCNShape(path: tri, extrusionDepth: 0.05)
            g.materials = [side > 0 ? wall : wallDark]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(0, Float(wallH), Float(side))
            r.addChildNode(n)
        }

        // Gable roof: two slabs meeting in a ridge that runs across the front,
        // so the triangle sits above the door like a proper kennel.
        let halfDepth: CGFloat = 0.39
        let rise: CGFloat = 0.20
        let slope = sqrt(halfDepth * halfDepth + rise * rise)
        let pitch = Float(atan2(rise, halfDepth))
        for side in [1.0, -1.0] as [CGFloat] {
            let g = SCNBox(width: 0.80, height: 0.035, length: slope, chamferRadius: 0.01)
            g.materials = [roof]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(0, Float(wallH + rise / 2), Float(side * halfDepth / 2))
            n.eulerAngles.x = side > 0 ? pitch : -pitch
            r.addChildNode(n)
        }
        // Ridge cap
        slab(0.82, 0.04, 0.07, 0, wallH + rise - 0.02, 0, roof)

        // Bowl in front of the house, off to one side.
        let bowl = SCNCylinder(radius: 0.075, height: 0.035)
        bowl.materials = [m(0.35, 0.52, 0.68)]
        let b = SCNNode(geometry: bowl)
        b.position = SCNVector3(0.36, 0.018, 0.42)
        b.name = "bowl"
        r.addChildNode(b)

        let food = SCNSphere(radius: 0.052)
        food.segmentCount = 10
        food.materials = [m(0.42, 0.28, 0.16)]
        let f = SCNNode(geometry: food)
        f.position = SCNVector3(0.36, 0.038, 0.42)
        f.scale = SCNVector3(1, 0.42, 1)
        f.name = "bowlFood"
        f.isHidden = true
        r.addChildNode(f)
    }

    /// Krmítko — a little roofed tray on a post; birds come and go.
    private static func buildBirdFeeder(_ r: SCNNode) {
        let wood = m(0.60, 0.44, 0.28)
        let roof = m(0.45, 0.55, 0.38)

        let post = SCNCylinder(radius: 0.022, height: 0.42)
        post.materials = [wood]
        let p = SCNNode(geometry: post)
        p.position = SCNVector3(0, 0.21, 0)
        r.addChildNode(p)

        let tray = SCNBox(width: 0.26, height: 0.022, length: 0.22, chamferRadius: 0.008)
        tray.materials = [m(0.68, 0.52, 0.34)]
        let t = SCNNode(geometry: tray)
        t.position = SCNVector3(0, 0.43, 0)
        t.name = "perch"
        r.addChildNode(t)

        // Seed scattered on the tray
        for (sx, sz) in [(-0.05, 0.03), (0.04, -0.02), (0.01, 0.05)] as [(CGFloat, CGFloat)] {
            let g = SCNSphere(radius: 0.012)
            g.segmentCount = 6
            g.materials = [m(0.78, 0.66, 0.36)]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(sx, 0.45, sz)
            r.addChildNode(n)
        }

        // Two small posts holding a pitched roof over the tray
        for sx in [-0.10, 0.10] as [CGFloat] {
            let g = SCNBox(width: 0.016, height: 0.12, length: 0.016, chamferRadius: 0.004)
            g.materials = [wood]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(sx, 0.50, 0)
            r.addChildNode(n)
        }
        let rf = SCNBox(width: 0.30, height: 0.13, length: 0.13, chamferRadius: 0.012)
        rf.materials = [roof]
        let roofNode = SCNNode(geometry: rf)
        roofNode.eulerAngles.x = .pi / 4
        let holder = SCNNode()
        holder.addChildNode(roofNode)
        holder.position = SCNVector3(0, 0.60, 0)
        r.addChildNode(holder)
    }

    /// Ohniště — a ring of stones with logs; the flames light up after dark.
    private static func buildFirePit(_ r: SCNNode) {
        // Stone ring
        for i in 0..<9 {
            let a = CGFloat(i) / 9 * .pi * 2
            let g = SCNSphere(radius: 0.055 + CGFloat(i % 3) * 0.008)
            g.segmentCount = 8
            g.materials = [i % 2 == 0 ? m(0.60, 0.58, 0.55) : m(0.50, 0.48, 0.46)]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(cos(a) * 0.24), 0.03, Float(sin(a) * 0.24))
            n.scale = SCNVector3(1, 0.7, 1)
            r.addChildNode(n)
        }
        // Ash bed
        let ash = SCNCylinder(radius: 0.20, height: 0.02)
        ash.materials = [m(0.32, 0.29, 0.27)]
        let a = SCNNode(geometry: ash)
        a.position = SCNVector3(0, 0.01, 0)
        r.addChildNode(a)
        // Crossed logs
        for (i, yaw) in [0.5, 2.2, 4.0].enumerated() {
            let g = SCNCylinder(radius: 0.028, height: 0.30)
            g.materials = [i == 1 ? m(0.40, 0.29, 0.19) : m(0.47, 0.34, 0.22)]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(0, 0.06, 0)
            n.eulerAngles = SCNVector3(Float.pi / 2 - 0.35, Float(yaw), 0)
            r.addChildNode(n)
        }
        // Seats around the fire: two log stumps and a felled log to sit on, so
        // the pit reads as a campfire people gather at.
        for (sx, sz) in [(-0.36, 0.20), (0.34, -0.24)] as [(CGFloat, CGFloat)] {
            let g = SCNCylinder(radius: 0.075, height: 0.13)
            g.materials = [m(0.52, 0.38, 0.24)]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(sx), 0.065, Float(sz))
            r.addChildNode(n)
            let top = SCNCylinder(radius: 0.077, height: 0.012)
            top.materials = [m(0.68, 0.53, 0.35)]
            let t = SCNNode(geometry: top)
            t.position = SCNVector3(Float(sx), 0.132, Float(sz))
            r.addChildNode(t)
        }
        let bench = SCNCylinder(radius: 0.06, height: 0.42)
        bench.materials = [m(0.49, 0.36, 0.23)]
        let bn = SCNNode(geometry: bench)
        bn.position = SCNVector3(0.06, 0.055, 0.40)
        bn.eulerAngles = SCNVector3(0, 0.25, Float.pi / 2)
        r.addChildNode(bn)

        // Flame group, hidden until night (toggled by setFireLit)
        let fire = SCNNode()
        fire.name = "fire"
        fire.isHidden = true
        r.addChildNode(fire)

        for (i, spec) in [(0.075, 0.16, 0.0), (0.05, 0.11, 0.05), (0.045, 0.09, -0.05)].enumerated() {
            let g = SCNCone(topRadius: 0, bottomRadius: spec.0, height: spec.1)
            g.radialSegmentCount = 7
            let mat = SCNMaterial()
            let warm: UIColor = i == 0
                ? UIColor(red: 1.0, green: 0.62, blue: 0.18, alpha: 1)
                : UIColor(red: 1.0, green: 0.82, blue: 0.35, alpha: 1)
            mat.diffuse.contents = warm
            mat.emission.contents = warm
            mat.lightingModel = .constant
            g.materials = [mat]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(spec.2), Float(0.09 + spec.1 / 2), Float(i == 1 ? 0.04 : -0.03))
            fire.addChildNode(n)
        }

        // Warm light so the fire actually lifts the scene at night
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.66, blue: 0.32, alpha: 1)
        light.intensity = 420
        light.attenuationEndDistance = 3.2
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(0, 0.28, 0)
        fire.addChildNode(lightNode)
    }

    /// Rybníček přes 2 pole — organický tvar, rákosí na západní straně,
    /// kachnička pomalu kroužící po hladině. Anchor = první pole, voda se
    /// táhne do sousedního pole na +x.
    private static func buildPond(_ r: SCNNode) {
        // Organic blob outline centred on (0.5, 0) spanning both cells
        func blob(_ scale: CGFloat) -> UIBezierPath {
            let c = CGPoint(x: 0.5, y: 0)
            let pts: [CGPoint] = [
                CGPoint(x: -0.40, y: 0.02),
                CGPoint(x: -0.28, y: -0.26),
                CGPoint(x: 0.10, y: -0.38),
                CGPoint(x: 0.62, y: -0.30),
                CGPoint(x: 1.10, y: -0.34),
                CGPoint(x: 1.38, y: -0.06),
                CGPoint(x: 1.22, y: 0.26),
                CGPoint(x: 0.78, y: 0.34),
                CGPoint(x: 0.30, y: 0.38),
                CGPoint(x: -0.12, y: 0.28),
            ].map { CGPoint(x: c.x + ($0.x - c.x) * scale, y: c.y + ($0.y - c.y) * scale) }

            let path = UIBezierPath()
            path.move(to: midPoint(pts[pts.count - 1], pts[0]))
            for i in 0..<pts.count {
                let next = pts[(i + 1) % pts.count]
                path.addQuadCurve(to: midPoint(pts[i], next), controlPoint: pts[i])
            }
            path.close()
            return path
        }

        func flatShape(_ path: UIBezierPath, color: SCNMaterial, y: CGFloat, depth: CGFloat) {
            path.flatness = 0.005
            let g = SCNShape(path: path, extrusionDepth: depth)
            g.materials = [color]
            let n = SCNNode(geometry: g)
            n.eulerAngles.x = -.pi / 2
            n.position = SCNVector3(0, y, 0)
            r.addChildNode(n)
        }

        // Wet sandy bank + water surface
        flatShape(blob(1.0),  color: m(0.64, 0.59, 0.45), y: 0.006, depth: 0.012)
        flatShape(blob(0.84), color: m(0.36, 0.64, 0.82), y: 0.020, depth: 0.012)

        // Rákosí — cluster on the west bank
        let stemMat = m(0.32, 0.52, 0.28)
        let tipMat  = m(0.42, 0.30, 0.20)
        for (sx, sz, sh) in [(-0.30, -0.08, 0.30), (-0.34, 0.06, 0.24), (-0.24, 0.14, 0.34),
                             (-0.20, -0.18, 0.26), (-0.36, -0.16, 0.28)] {
            let stem = SCNCylinder(radius: 0.011, height: CGFloat(sh))
            stem.materials = [stemMat]
            let s = SCNNode(geometry: stem)
            s.position = SCNVector3(CGFloat(sx), CGFloat(sh) / 2, CGFloat(sz))
            r.addChildNode(s)
            let tip = SCNCylinder(radius: 0.02, height: 0.06)
            tip.materials = [tipMat]
            let t = SCNNode(geometry: tip)
            t.position = SCNVector3(CGFloat(sx), CGFloat(sh) + 0.02, CGFloat(sz))
            r.addChildNode(t)
        }

        // Kachnička — slowly circles the pond
        let orbit = SCNNode()
        orbit.position = SCNVector3(0.5, 0.028, 0)
        r.addChildNode(orbit)

        let duck = SCNNode()
        duck.position = SCNVector3(0.34, 0, 0)
        orbit.addChildNode(duck)

        let bodyG = SCNSphere(radius: 0.055)
        bodyG.segmentCount = 12
        bodyG.materials = [m(0.96, 0.90, 0.62)]
        let body = SCNNode(geometry: bodyG)
        body.scale = SCNVector3(1.35, 0.8, 0.9)
        body.position = SCNVector3(0, 0.035, 0)
        duck.addChildNode(body)

        let headG = SCNSphere(radius: 0.032)
        headG.segmentCount = 10
        headG.materials = [m(0.96, 0.90, 0.62)]
        let head = SCNNode(geometry: headG)
        head.position = SCNVector3(0, 0.10, -0.055)
        duck.addChildNode(head)

        let beakG = SCNBox(width: 0.02, height: 0.012, length: 0.03, chamferRadius: 0.004)
        beakG.materials = [m(0.92, 0.56, 0.20)]
        let beak = SCNNode(geometry: beakG)
        beak.position = SCNVector3(0, 0.095, -0.09)
        duck.addChildNode(beak)

        orbit.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 26)))
        let bobUp = SCNAction.moveBy(x: 0, y: 0.008, z: 0, duration: 0.9)
        bobUp.timingMode = .easeInEaseOut
        let bobDn = SCNAction.moveBy(x: 0, y: -0.008, z: 0, duration: 0.9)
        bobDn.timingMode = .easeInEaseOut
        duck.runAction(.repeatForever(.sequence([bobUp, bobDn])))
    }

    private static func midPoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func m(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let mm = SCNMaterial()
        mm.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
        mm.lightingModel = .lambert
        return mm
    }

    private static func buildTree(_ r: SCNNode) {
        let trunk = SCNCylinder(radius: 0.05, height: 0.2)
        trunk.materials = [m(0.45, 0.33, 0.22)]
        let t = SCNNode(geometry: trunk)
        t.position = SCNVector3(0, 0.1, 0)
        r.addChildNode(t)

        let green = m(0.38, 0.62, 0.33)
        let dark  = m(0.30, 0.52, 0.28)
        for (i, tier) in [(0.30, 0.34), (0.24, 0.30), (0.17, 0.26)].enumerated() {
            let cone = SCNCone(topRadius: 0, bottomRadius: tier.0, height: tier.1)
            cone.materials = [i % 2 == 0 ? green : dark]
            let n = SCNNode(geometry: cone)
            n.position = SCNVector3(0, 0.2 + CGFloat(i) * 0.18 + tier.1/2, 0)
            r.addChildNode(n)
        }
    }

    /// Auto-tiling road, flush with the grass. Each tile is one flat organic
    /// shape: a rounded center plate with arms that end exactly at the tile
    /// boundary — corners and dead-ends are softly rounded, joins between
    /// neighbouring tiles stay seamless. A slightly wider, darker rim under
    /// the surface eases the transition into the grass.
    static func buildRoad(_ r: SCNNode, n: Bool, e: Bool, s: Bool, w: Bool) {
        let topMat = m(0.72, 0.66, 0.52)      // trodden earth
        let rimMat = m(0.60, 0.55, 0.42)      // packed edge into the grass

        /// Union of rounded center + connecting arms (arms always reach ±0.5).
        func outline(inset: CGFloat, corner: CGFloat, armW: CGFloat) -> UIBezierPath {
            let half = 0.30 + inset
            let p = UIBezierPath(
                roundedRect: CGRect(x: -half, y: -half, width: half * 2, height: half * 2),
                cornerRadius: corner)
            let aw = armW / 2
            // path +y maps to world −z after the flat rotation
            if n { p.append(UIBezierPath(rect: CGRect(x: -aw, y: 0.25, width: armW, height: 0.25))) }
            if s { p.append(UIBezierPath(rect: CGRect(x: -aw, y: -0.50, width: armW, height: 0.25))) }
            if e { p.append(UIBezierPath(rect: CGRect(x: 0.25, y: -aw, width: 0.25, height: armW))) }
            if w { p.append(UIBezierPath(rect: CGRect(x: -0.50, y: -aw, width: 0.25, height: armW))) }
            return p
        }

        func flat(_ path: UIBezierPath, material: SCNMaterial, centerY: CGFloat, depth: CGFloat) {
            let g = SCNShape(path: path, extrusionDepth: depth)
            g.materials = [material]
            let node = SCNNode(geometry: g)
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(0, centerY, 0)
            r.addChildNode(node)
        }

        // flatness matters: our units are tiny, default tessellation is coarse
        let rimShape = outline(inset: 0.05, corner: 0.22, armW: 0.50)
        let topShape = outline(inset: 0,    corner: 0.16, armW: 0.40)
        rimShape.flatness = 0.005
        topShape.flatness = 0.005
        flat(rimShape, material: rimMat, centerY: 0.005, depth: 0.010)
        flat(topShape, material: topMat, centerY: 0.013, depth: 0.012)

        // Two subtle flat pebbles
        for (px, pz) in [(-0.12, 0.09), (0.10, -0.12)] {
            let peb = SCNCylinder(radius: 0.02, height: 0.006)
            peb.materials = [m(0.64, 0.58, 0.46)]
            let p = SCNNode(geometry: peb)
            p.position = SCNVector3(CGFloat(px), 0.022, CGFloat(pz))
            r.addChildNode(p)
        }
    }

    /// Listnáč — round layered canopy on a short trunk.
    private static func buildLeafTree(_ r: SCNNode) {
        let trunk = SCNCylinder(radius: 0.055, height: 0.26)
        trunk.materials = [m(0.47, 0.34, 0.22)]
        let t = SCNNode(geometry: trunk)
        t.position = SCNVector3(0, 0.13, 0)
        r.addChildNode(t)

        let lit  = m(0.46, 0.66, 0.36)
        let dark = m(0.37, 0.56, 0.31)
        let blobs: [(x: CGFloat, y: CGFloat, z: CGFloat, s: CGFloat, dark: Bool)] = [
            (0,      0.48,  0,     0.26, false),
            (-0.14,  0.40, -0.06,  0.18, true),
            (0.15,   0.42,  0.05,  0.17, true),
            (0.02,   0.36,  0.14,  0.15, false),
            (-0.04,  0.60,  0.02,  0.16, false),
        ]
        for b in blobs {
            let g = SCNSphere(radius: b.s)
            g.segmentCount = 12                      // low-poly feel
            g.materials = [b.dark ? dark : lit]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(b.x, b.y, b.z)
            r.addChildNode(n)
        }
    }

    /// Ovocný strom — three genuinely different trees, not one tree in three
    /// colours. Fruit is anchored to the *surface* of the crown so it actually
    /// reads from the game camera instead of hiding inside the leaves.
    private static func buildFruitTree(_ r: SCNNode, _ variant: Int) {
        let v = ((variant % 3) + 3) % 3

        /// Fruit hanging *under* the canopy on a short stalk. Ringing fruit around
        /// the crown's equator always reads as bumps on the silhouette, so these
        /// dangle below the leaves where they're seen against the grass instead.
        /// `rh`/`rv` are the canopy's horizontal/vertical radii (crowns are squashed).
        let stemMat = m(0.34, 0.28, 0.18)
        func fruit(centre c: (x: CGFloat, y: CGFloat, z: CGFloat), rh: CGFloat, rv: CGFloat,
                   yaw: CGFloat, pitch: CGFloat, size: CGFloat, material: SCNMaterial) {
            let dx = cos(pitch) * sin(yaw), dy = sin(pitch), dz = cos(pitch) * cos(yaw)
            // Distance from the centre to the ellipsoid surface along this direction.
            let surf = 1 / sqrt(pow(dx / rh, 2) + pow(dy / rv, 2) + pow(dz / rh, 2))
            let hang = surf + size * 0.85          // clear of the leaves

            let g = SCNSphere(radius: size)
            g.segmentCount = 12
            g.materials = [material]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(c.x + dx * hang),
                                    Float(c.y + dy * hang),
                                    Float(c.z + dz * hang))
            n.scale = SCNVector3(1, 0.92, 1)       // a touch squat, less bauble-like
            r.addChildNode(n)

            // Stalk from inside the foliage out to the fruit.
            let inset = surf * 0.8
            let mid = (inset + hang) / 2
            let stem = SCNCylinder(radius: 0.006, height: hang - inset + 0.01)
            stem.radialSegmentCount = 6
            stem.materials = [stemMat]
            let s = SCNNode(geometry: stem)
            s.position = SCNVector3(Float(c.x + dx * mid), Float(c.y + dy * mid), Float(c.z + dz * mid))
            s.eulerAngles = SCNVector3(Float.pi / 2 - Float(pitch), Float(yaw), 0)
            r.addChildNode(s)
        }

        func trunk(_ radius: CGFloat, _ height: CGFloat, _ material: SCNMaterial) {
            let g = SCNCylinder(radius: radius, height: height)
            g.materials = [material]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(0, height / 2, 0)
            r.addChildNode(n)
        }

        func leaves(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ s: CGFloat,
                    _ material: SCNMaterial, squash: CGFloat = 1) {
            let g = SCNSphere(radius: s)
            g.segmentCount = 12
            g.materials = [material]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(x, y, z)
            n.scale = SCNVector3(1, Float(squash), 1)
            r.addChildNode(n)
        }

        switch v {
        case 1:
            // ŠVESTKA — tall, narrow, upright crown on a slim dark trunk.
            let lit  = m(0.33, 0.52, 0.31)
            let dark = m(0.25, 0.42, 0.26)
            let plum = m(0.42, 0.24, 0.55)
            trunk(0.038, 0.30, m(0.36, 0.26, 0.18))
            leaves(0, 0.50, 0, 0.17, lit, squash: 1.45)
            leaves(-0.07, 0.40, 0.03, 0.11, dark, squash: 1.2)
            leaves(0.07, 0.62, -0.02, 0.10, lit)
            for (yaw, pitch) in [(0.5, -0.75), (2.4, -0.55), (3.5, -0.95), (5.3, -0.65)] {
                fruit(centre: (0, 0.50, 0), rh: 0.175, rv: 0.245,
                      yaw: CGFloat(yaw), pitch: CGFloat(pitch), size: 0.028, material: plum)
            }
            // a couple windfalls in the grass
            for (fx, fz) in [(-0.17, 0.13), (0.15, -0.16)] as [(CGFloat, CGFloat)] {
                let g = SCNSphere(radius: 0.026); g.segmentCount = 8; g.materials = [plum]
                let n = SCNNode(geometry: g); n.position = SCNVector3(fx, 0.024, fz)
                r.addChildNode(n)
            }

        case 2:
            // POMERANČOVNÍK — low and wide, two flat tiers, heavy with fruit.
            let lit  = m(0.42, 0.63, 0.30)
            let dark = m(0.33, 0.52, 0.26)
            let orange = m(0.97, 0.56, 0.14)
            trunk(0.05, 0.15, m(0.50, 0.38, 0.24))
            leaves(0, 0.30, 0, 0.25, lit, squash: 0.62)
            leaves(0, 0.44, 0, 0.17, dark, squash: 0.6)
            for (yaw, pitch) in [(0.4, -0.85), (1.9, -0.6), (3.2, -1.0), (4.6, -0.7), (5.6, -0.5)] {
                fruit(centre: (0, 0.30, 0), rh: 0.25, rv: 0.155,
                      yaw: CGFloat(yaw), pitch: CGFloat(pitch), size: 0.032, material: orange)
            }

        default:
            // JABLOŇ — broad billowing crown, big red apples, chunky trunk.
            let lit  = m(0.47, 0.68, 0.36)
            let dark = m(0.37, 0.57, 0.31)
            let apple = m(0.88, 0.20, 0.18)
            trunk(0.055, 0.20, m(0.48, 0.34, 0.22))
            leaves(0, 0.42, 0, 0.22, lit)
            leaves(-0.15, 0.36, -0.04, 0.14, dark)
            leaves(0.15, 0.38, 0.05, 0.13, dark)
            for (yaw, pitch) in [(0.6, -0.7), (2.2, -0.5), (3.4, -0.9), (5.0, -0.6)] {
                fruit(centre: (0, 0.42, 0), rh: 0.22, rv: 0.22,
                      yaw: CGFloat(yaw), pitch: CGFloat(pitch), size: 0.034, material: apple)
            }
            fruit(centre: (-0.15, 0.36, -0.04), rh: 0.14, rv: 0.14,
                  yaw: 3.9, pitch: -0.8, size: 0.03, material: apple)
            // one apple fallen under the tree
            let g = SCNSphere(radius: 0.032); g.segmentCount = 8; g.materials = [apple]
            let n = SCNNode(geometry: g); n.position = SCNVector3(0.18, 0.03, 0.14)
            r.addChildNode(n)
        }
    }

    /// Keř — three looks: 0 bobulový, 1 kvetoucí, 2 vysoký travnatý trs.
    private static func buildBush(_ r: SCNNode, _ variant: Int = 0) {
        let v = ((variant % 3) + 3) % 3

        if v == 2 {
            // Tall grassy tuft: a few slim blades fanning out
            let blade = m(0.46, 0.66, 0.36)
            let bladeDark = m(0.38, 0.57, 0.31)
            for (i, spec) in [(-0.07, 0.0, 0.03, -0.18), (0.0, 0.0, -0.02, 0.0),
                              (0.07, 0.0, 0.04, 0.20), (0.02, 0.0, 0.09, 0.08)].enumerated() {
                let g = SCNCone(topRadius: 0.004, bottomRadius: 0.035, height: 0.26)
                g.radialSegmentCount = 6
                g.materials = [i % 2 == 0 ? blade : bladeDark]
                let n = SCNNode(geometry: g)
                n.position = SCNVector3(spec.0, 0.13, spec.2)
                n.eulerAngles.z = Float(spec.3)
                r.addChildNode(n)
            }
            return
        }

        let lit  = m(0.50, 0.70, 0.40)
        let dark = m(0.40, 0.60, 0.34)
        for (i, p) in [(-0.08, 0.11, 0.03, 0.14), (0.09, 0.09, -0.04, 0.11)].enumerated() {
            let g = SCNSphere(radius: p.3)
            g.segmentCount = 10
            g.materials = [i == 0 ? lit : dark]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(p.0, p.1, p.2)
            n.scale = SCNVector3(1, 0.75, 1)         // squashed mound
            r.addChildNode(n)
        }

        // Berries (v0) or little blossoms (v1)
        let dotMat = v == 1 ? m(0.94, 0.72, 0.82) : m(0.88, 0.36, 0.34)
        let dots: [(CGFloat, CGFloat, CGFloat)] = v == 1
            ? [(-0.06, 0.20, 0.08), (0.11, 0.16, 0.03), (0.02, 0.21, -0.06), (-0.12, 0.16, -0.02)]
            : [(-0.05, 0.19, 0.10), (0.12, 0.15, 0.02)]
        for (bx, by, bz) in dots {
            let g = SCNSphere(radius: v == 1 ? 0.022 : 0.018)
            g.segmentCount = 8
            g.materials = [dotMat]
            let b = SCNNode(geometry: g)
            b.position = SCNVector3(bx, by, bz)
            r.addChildNode(b)
        }
    }

    private static func buildBench(_ r: SCNNode) {
        let wood = m(0.58, 0.42, 0.28)
        let seat = SCNBox(width: 0.4, height: 0.04, length: 0.14, chamferRadius: 0.01)
        seat.materials = [wood]
        let s = SCNNode(geometry: seat)
        s.position = SCNVector3(0, 0.16, 0)
        r.addChildNode(s)
        let back = SCNBox(width: 0.4, height: 0.14, length: 0.03, chamferRadius: 0.01)
        back.materials = [wood]
        let b = SCNNode(geometry: back)
        b.position = SCNVector3(0, 0.26, -0.06)
        r.addChildNode(b)
        for sx in [-0.16, 0.16] {
            let leg = SCNBox(width: 0.04, height: 0.14, length: 0.12, chamferRadius: 0.005)
            leg.materials = [m(0.35, 0.30, 0.26)]
            let l = SCNNode(geometry: leg)
            l.position = SCNVector3(CGFloat(sx), 0.07, 0)
            r.addChildNode(l)
        }
    }

    private static func buildFountain(_ r: SCNNode) {
        let stone = m(0.72, 0.70, 0.66)
        let basin = SCNCylinder(radius: 0.34, height: 0.14)
        basin.materials = [stone]
        let b = SCNNode(geometry: basin)
        b.position = SCNVector3(0, 0.07, 0)
        r.addChildNode(b)

        let water = SCNCylinder(radius: 0.28, height: 0.02)
        water.materials = [m(0.42, 0.70, 0.86)]
        let w = SCNNode(geometry: water)
        w.position = SCNVector3(0, 0.145, 0)
        r.addChildNode(w)

        let post = SCNCylinder(radius: 0.05, height: 0.3)
        post.materials = [stone]
        let p = SCNNode(geometry: post)
        p.position = SCNVector3(0, 0.29, 0)
        r.addChildNode(p)

        let top = SCNSphere(radius: 0.07)
        top.materials = [m(0.55, 0.78, 0.90)]
        let t = SCNNode(geometry: top)
        t.position = SCNVector3(0, 0.47, 0)
        r.addChildNode(t)

        // Live water — fine spray arcing from the spout back into the basin
        let spray = SCNParticleSystem()
        spray.birthRate = 90
        spray.particleLifeSpan = 0.55
        spray.particleLifeSpanVariation = 0.12
        spray.particleVelocity = 0.55
        spray.particleVelocityVariation = 0.18
        spray.emittingDirection = SCNVector3(0, 1, 0)
        spray.spreadingAngle = 24
        spray.particleSize = 0.014
        spray.particleSizeVariation = 0.006
        spray.particleColor = UIColor(red: 0.72, green: 0.87, blue: 0.97, alpha: 0.85)
        spray.isAffectedByGravity = false
        spray.acceleration = SCNVector3(0, -2.4, 0)

        let sprayNode = SCNNode()
        sprayNode.position = SCNVector3(0, 0.50, 0)
        sprayNode.addParticleSystem(spray)
        r.addChildNode(sprayNode)
    }
}

// MARK: - SwiftUI wrapper

struct TownSceneView: UIViewRepresentable {
    let scene: TownScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene.scnScene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X   // 4X is costly with skinned animals
        view.allowsCameraControl = false
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        scene.scnView = view

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let pan   = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        let lp    = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        lp.minimumPressDuration = 0.28
        lp.allowableMovement = 400

        [tap, dbl, pinch, pan, lp].forEach { view.addGestureRecognizer($0) }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(scene: scene) }

    final class Coordinator: NSObject {
        let scene: TownScene
        private var pinchStart: CGFloat = 0
        private var panStart: SCNVector3?

        init(scene: TownScene) { self.scene = scene }

        @objc func tap(_ r: UITapGestureRecognizer) {
            guard r.state == .ended, let v = r.view else { return }
            scene.handleTap(at: r.location(in: v))
        }

        @objc func doubleTap(_ r: UITapGestureRecognizer) {
            guard r.state == .ended, let v = r.view else { return }
            scene.handleDoubleTap(at: r.location(in: v))
        }

        @objc func pinch(_ r: UIPinchGestureRecognizer) {
            if r.state == .began { pinchStart = 0 }
            scene.handlePinch(scale: r.scale, began: &pinchStart)
        }

        @objc func pan(_ r: UIPanGestureRecognizer) {
            guard let v = r.view else { return }
            if scene.isRoadPaintMode {
                switch r.state {
                case .began, .changed:
                    scene.paintStroke(at: r.location(in: v))
                case .ended, .cancelled, .failed:
                    scene.endPaintStroke()
                default:
                    break
                }
                return
            }
            if r.state == .began { panStart = nil }
            scene.handlePan(translation: r.translation(in: v), start: &panStart)
        }

        @objc func longPress(_ r: UILongPressGestureRecognizer) {
            guard let v = r.view else { return }
            let p = r.location(in: v)
            switch r.state {
            case .began:                       scene.dragBegan(at: p)
            case .changed:                     scene.dragMoved(at: p)
            case .ended, .cancelled, .failed:  scene.dragEnded(at: p)
            default: break
            }
        }
    }
}

// MARK: - Ambient state

enum TownWeather { case sunny, rain, fog }

enum DaylightPhase {
    case dawn, day, dusk, night

    init(hour: Int) {
        switch hour {
        case 5..<8:   self = .dawn
        case 8..<17:  self = .day
        case 17..<21: self = .dusk
        default:      self = .night
        }
    }
}

// MARK: - BuildingType accent color (used by Calendar / sheets)

extension BuildingType {
    var skColorRGB: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .cottage, .house, .barn, .well, .farm, .stables:        (0.78, 0.49, 0.34)
        case .tavern, .blacksmith, .market, .shop, .flowerShop, .post: (0.36, 0.48, 0.60)
        case .townhall, .school, .church, .fortress, .tower:           (0.37, 0.62, 0.52)
        case .cathedral, .castle:                                      (0.49, 0.42, 0.62)
        }
    }
}
