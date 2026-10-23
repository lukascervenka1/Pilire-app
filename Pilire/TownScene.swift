import SceneKit
import simd
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
    private var rimNode: SCNNode?
    private var hintsNode: SCNNode?
    private var hintsRebuildScheduled = false
    private var pendingHints = false
    private var warmUpScheduled = false
    /// The last lattice we built, kept so repeated pickups reuse it.
    private var cachedHints: SCNNode?
    private var cachedHintsKey: HintsKey?

    // Worked out once when the drag starts, not on every touch move.
    private var dragOffsets: [(dx: Int, dy: Int)] = []
    private var dragBounds: (w: Int, l: Int, midX: Float, midY: Float) = (1, 1, 0, 0)
    /// Screen → ground-plane mapping, solved once per gesture. `unprojectPoint`
    /// synchronises with the renderer and costs several milliseconds a call, and
    /// `groundPoint` makes two of them — which was the entire cost of dragging.
    /// The map camera is orthographic and frozen while you drag or paint, so the
    /// mapping is plain affine and two multiplies give the identical answer.
    private var groundBasis: (o: SCNVector3, dx: SCNVector3, dz: SCNVector3)?

    private var lastGhostCell: (col: Int, row: Int)?
    private var lastGhostValid: Bool?
    private static let ghostOKColor  = UIColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 0.45)
    private static let ghostBadColor = UIColor(red: 0.95, green: 0.30, blue: 0.25, alpha: 0.45)
    var cameraPanEnabled = true

    /// Things the player can never touch — hint dots and the placement ghost.
    /// Hit tests skip them, so a tap doesn't have to trace a ray through the
    /// whole lattice before finding the tree underneath it.
    static let decorCategory = 1 << 5
    private static let touchableCategory = 1

    // Built once for the whole app. A fresh SCNGeometry per drag meant the GPU
    // set up brand-new resources at the exact moment you picked something up.
    /// One round dot, built once. A plane with a full corner radius *is* a
    /// circle — the same trick the contact shadow uses — and it costs two
    /// triangles instead of the forty a cylinder was spending per dot.
    private static let tileHintGeometry: SCNPlane = {
        let g = SCNPlane(width: 0.10, height: 0.10)
        g.cornerRadius = 0.05
        g.firstMaterial?.diffuse.contents = UIColor(white: 1, alpha: 0.34)
        g.firstMaterial?.lightingModel = .constant
        return g
    }()

    private static let cornerHintGeometry: SCNPlane = {
        let g = SCNPlane(width: 0.07, height: 0.07)
        g.cornerRadius = 0.035
        g.firstMaterial?.diffuse.contents = UIColor(red: 0.85, green: 0.98, blue: 0.80, alpha: 0.42)
        g.firstMaterial?.lightingModel = .constant
        return g
    }()

    // Ambient life
    private var sunLight: SCNLight?
    private var ambLight: SCNLight?
    private var daylightTimer: Timer?
    private var stormEffects: StormWeatherEffects?
    private(set) var renderingActive = true
    private var weatherConfigured = false
    private var appliedBuildingLightPhase: DaylightPhase?
    private var ambientMotionAllowed = !UIAccessibility.isReduceMotionEnabled
    private(set) var weather: TownWeather = .sunny
    private(set) var daylight: DaylightPhase = .day

    /// Last known island size, mirrored out of SwiftData. The scene is built
    /// when the view is constructed, which is before the store can be read — so
    /// an expanded town used to raise a 12×12 island and immediately tear it
    /// down for the real one, on the main thread, right as you started playing.
    /// Purely a cache: `setMapSize` still corrects it if it's ever stale.
    private static let mapSizeCacheKey = "cachedMapSize"

    override init() {
        super.init()
        let cached = UserDefaults.standard.integer(forKey: Self.mapSizeCacheKey)
        if (12...24).contains(cached) { cols = cached }
        setupLights()
        setupCamera()
        buildIsland()
        scatterGroundDetails()
        applyWeather()
        applyDaylight()
        setupBirds()
        setupButterflies()
        setupFireflies()
        daylightTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshTimeOfDay()
        }
    }

    deinit { daylightTimer?.invalidate() }

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
        UserDefaults.standard.set(n, forKey: Self.mapSizeCacheKey)
        guard n != cols else { return }
        cols = n
        rebuildGround()
        applyWeather(force: true)
        applyDaylight()
    }

    /// Pause the render loop (and thus all animations/skinning) when the map
    /// isn't on screen — no point burning the GPU behind another tab.
    func setRendering(active: Bool) {
        renderingActive = active
        stormEffects?.setActive(active)
        scnView?.isPlaying = active
    }

    /// Uploads geometry, textures and shaders for everything currently in the
    /// scene, on a background queue. Without this the *first* interaction after
    /// launch is the one that pays for all of it — which is why picking up a
    /// building right after opening the app stuttered, and why it was fine once
    /// the app had been running for a bit. The hint dots are included so the
    /// first press-and-hold doesn't upload them mid-gesture.
    func warmUp() {
        guard let view = scnView else { return }
        view.prepare([scnScene, Self.tileHintGeometry, Self.cornerHintGeometry]) { _ in }
    }

    /// Coalesced `warmUp` — animals finish loading one by one, and there is no
    /// point kicking off a fresh upload pass for each of them.
    func scheduleWarmUp() {
        guard !warmUpScheduled else { return }
        warmUpScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.warmUpScheduled = false
            self?.warmUp()
        }
    }

    /// Expand by one tier: shifts all grid coordinates by +delta/2 so the
    /// existing town keeps its world position while the island grows around it.
    func expand(toCols newCols: Int) {
        UserDefaults.standard.set(newCols, forKey: Self.mapSizeCacheKey)
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
        cachedHints = nil
        cachedHintsKey = nil
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
        let hour = ScreenshotMode.currentHour(at: now)
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
            ambLight?.intensity = 380
            ambLight?.color = UIColor(red: 0.61, green: 0.68, blue: 0.84, alpha: 1)
        }
        // Compose weather with the current time every refresh. Applying the
        // weather only once let the minute timer restore sunny illumination.
        sunLight?.shadowRadius = weather == .storm ? 12 : 7
        sunLight?.shadowColor = UIColor(red: 0.10, green: 0.14, blue: 0.10,
                                        alpha: weather == .storm ? 0.12 : 0.30)
        switch weather {
        case .sunny: break
        case .rain:
            sunLight?.intensity *= 0.65
            ambLight?.color = UIColor(red: 0.72, green: 0.76, blue: 0.82, alpha: 1)
        case .fog:
            sunLight?.intensity *= 0.8
        case .storm:
            sunLight?.intensity *= 0.47
            sunLight?.color = UIColor(red: 0.76, green: 0.82, blue: 0.86, alpha: 1)
            ambLight?.intensity *= 0.90
            ambLight?.color = UIColor(red: 0.68, green: 0.75, blue: 0.78, alpha: 1)
            scnScene.fogColor = skyColors.last!
        }
        stormEffects?.apply(daylight)
        if appliedBuildingLightPhase != buildingLightPhase {
            appliedBuildingLightPhase = buildingLightPhase
            SCNTransaction.begin()
            SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 1.4
            for building in buildingNodes { building.nightLighting?.apply(buildingLightPhase) }
            for decoration in decorationNodes { decoration.streetLighting?.apply(buildingLightPhase) }
            SCNTransaction.commit()
        }
        refreshLocalBuildingLights()
        refreshFirePits()
        updateSkyBackground()
        onAtmosphereChanged?()
    }

    /// Low window and lantern glow gives the overcast town a little warmth,
    /// without changing the clock used by animals, fires or the soundscape.
    private var buildingLightPhase: DaylightPhase {
        weather == .storm && daylight == .day ? .dawn : daylight
    }

    /// What the town sounds like right now: weather, time of day and a lit fire.
    var atmosphere: SoundManager.Atmosphere {
        .init(weather: weather, daylight: daylight,
              fireLit: isAfterDark && decorationNodes.contains { $0.type == .firePit })
    }

    /// Fired when the weather, time of day or the set of fire pits changes.
    var onAtmosphereChanged: (() -> Void)?

    /// Share six local lights between buildings and street lamps (five during
    /// storms, reserving one for lightning). Every lamp retains its luminous
    /// glass and ground pool even outside this budget.
    func refreshLocalBuildingLights() {
        let focus = cameraRig.position
        let candidates: [SCNNode] = buildingNodes.filter { $0.isComplete }.map { $0 as SCNNode }
            + decorationNodes.filter { $0.type == .streetLamp }.map { $0 as SCNNode }
        let nearest = candidates.sorted {
            let a = $0.position, b = $1.position
            let da = (a.x-focus.x)*(a.x-focus.x) + (a.z-focus.z)*(a.z-focus.z)
            let db = (b.x-focus.x)*(b.x-focus.x) + (b.z-focus.z)*(b.z-focus.z)
            return da < db
        }.prefix(weather == .storm ? 5 : 6)
        let active = Set(nearest.map { ObjectIdentifier($0) })
        for building in buildingNodes {
            building.nightLighting?.setLocalLightEnabled(active.contains(ObjectIdentifier(building)))
        }
        for decoration in decorationNodes {
            decoration.streetLighting?.setLocalLightEnabled(active.contains(ObjectIdentifier(decoration)))
        }
    }

    /// Re-read the clock — call when the map comes back on screen so fires and
    /// bedtime follow real time without a restart.
    func refreshTimeOfDay(now: Date = .now) {
        let previousWeather = weather, previousDaylight = daylight
        let motionAllowed = !UIAccessibility.isReduceMotionEnabled
        applyWeather(now: now)
        applyDaylight(now: now)
        stormEffects?.setActive(renderingActive)
        if weather != previousWeather || daylight != previousDaylight || motionAllowed != ambientMotionAllowed {
            scnScene.rootNode.childNodes.filter { $0.name == "bird" || $0.name == "ambientLife" }
                .forEach { $0.removeFromParentNode() }
            ambientMotionAllowed = motionAllowed
            setupBirds(); setupButterflies(); setupFireflies()
        }
    }

    /// Also clears an in-progress pulse when the user enables dimmed flashes.
    func refreshWeatherAccessibility() {
        stormEffects?.setActive(renderingActive)
        refreshTimeOfDay()
    }

    // MARK: - Weather (stable for each local day)

    private func applyWeather(now: Date = .now, force: Bool = false) {
        let next = ScreenshotMode.weather ?? TownWeather.seeded(at: now)
        guard force || !weatherConfigured || next != weather else { return }
        weatherConfigured = true
        weather = next
        stormEffects?.setActive(false)
        stormEffects?.root.removeFromParentNode()
        stormEffects = nil
        scnScene.rootNode.childNodes.filter { $0.name == "rain" }.forEach { $0.removeFromParentNode() }
        scnScene.fogStartDistance = 0
        scnScene.fogEndDistance = 0
        scnScene.fogDensityExponent = 1

        switch weather {
        case .sunny: break
        case .rain: addRain()
        case .fog:
            scnScene.fogColor = UIColor(red: 0.88, green: 0.91, blue: 0.90, alpha: 1)
            scnScene.fogStartDistance = 52
            scnScene.fogEndDistance = 82
            scnScene.fogDensityExponent = 1.5
        case .storm:
            addRain()
            scnScene.fogStartDistance = 56
            scnScene.fogEndDistance = 94
            scnScene.fogDensityExponent = 1.2
            let effects = StormWeatherEffects(islandSize: cols)
            effects.onLightning = { SoundManager.shared.playDistantThunder() }
            scnScene.rootNode.addChildNode(effects.root)
            effects.apply(daylight)
            effects.setActive(renderingActive)
            stormEffects = effects
        }
    }

    /// Shared with SwiftUI's backing view. Keeping the sky in the 3D render
    /// target lets translucent stone and water blend in linear color space;
    /// compositing those pixels over a separate UI gradient creates pale rims.
    var skyColors: [UIColor] {
        if weather == .storm {
            let rgb: [(CGFloat, CGFloat, CGFloat)]
            switch daylight {
            case .dawn: rgb = [(0.38, 0.40, 0.49), (0.57, 0.59, 0.64), (0.76, 0.77, 0.74)]
            case .day: rgb = [(0.36, 0.43, 0.49), (0.52, 0.60, 0.63), (0.73, 0.78, 0.75)]
            case .dusk: rgb = [(0.30, 0.33, 0.43), (0.48, 0.49, 0.55), (0.66, 0.66, 0.64)]
            case .night: rgb = [(0.10, 0.14, 0.20), (0.21, 0.28, 0.32), (0.38, 0.46, 0.45)]
            }
            return rgb.map { UIColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
        }
        if weather == .fog {
            return [UIColor(red: 0.80, green: 0.84, blue: 0.84, alpha: 1),
                    UIColor(red: 0.87, green: 0.90, blue: 0.88, alpha: 1)]
        }
        let rgb: [(CGFloat, CGFloat, CGFloat)]
        switch daylight {
        case .dawn:  rgb = [(0.78, 0.72, 0.86), (0.96, 0.80, 0.72), (0.98, 0.90, 0.80)]
        case .day:   rgb = [(0.66, 0.83, 0.93), (0.82, 0.91, 0.90), (0.93, 0.95, 0.88)]
        case .dusk:  rgb = [(0.46, 0.42, 0.66), (0.90, 0.62, 0.48), (0.97, 0.82, 0.62)]
        case .night: rgb = [(0.10, 0.13, 0.26), (0.16, 0.22, 0.38), (0.24, 0.32, 0.44)]
        }
        return rgb.map { UIColor(red: $0.0, green: $0.1, blue: $0.2,
                                 alpha: weather == .rain ? 0.85 : 1) }
    }

    private func updateSkyBackground() {
        let colors = skyColors.map(\.cgColor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 4, height: 512)
        scnScene.background.contents = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors as CFArray, locations: nil) else { return }
            ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    private func addRain() {
        let rain = SCNParticleSystem()
        let storm = weather == .storm
        rain.birthRate = storm ? CGFloat(cols * cols) * 2.0 : 220
        rain.particleLifeSpan = 1.4
        rain.particleVelocity = 9
        rain.particleVelocityVariation = 2
        rain.emittingDirection = storm ? SCNVector3(-0.24, -1, 0.08) : SCNVector3(0, -1, 0)
        rain.spreadingAngle = 2
        rain.particleSize = storm ? 0.010 : 0.012
        rain.particleSizeVariation = 0.004
        rain.stretchFactor = storm ? 0.025 : 0.035
        rain.particleColor = UIColor(red: 0.75, green: 0.82, blue: 0.92, alpha: 0.20)
        let span = storm ? CGFloat(cols + 5) : 30
        rain.emitterShape = SCNBox(width: span, height: 0.1, length: span, chamferRadius: 0)
        rain.birthLocation = .volume
        rain.isAffectedByGravity = false

        let node = SCNNode()
        node.position = SCNVector3(0, 9, 0)
        node.addParticleSystem(rain)
        node.name = "rain"
        scnScene.rootNode.addChildNode(node)
    }


    // MARK: - Birds (occasional fly-over)

    private func setupBirds() {
        guard !weather.hasPrecipitation, daylight != .night, !UIAccessibility.isReduceMotionEnabled else { return }
        for i in 0..<2 {
            let bird = AmbientBirdNode()
            bird.scale = SCNVector3(0.78,0.78,0.78)
            let margin = Float(cols)/2 + 6
            let start = SCNVector3(-margin,3.5 + Float(i)*0.65,Float(i)*3.3-1.8)
            let end = SCNVector3(margin,start.y+0.25,start.z+3.0)
            let flight = SCNAction.customAction(duration:15) { node,elapsed in
                let t = Float(elapsed)/15
                node.position = SCNVector3(start.x+(end.x-start.x)*t,
                                           start.y+(end.y-start.y)*t+0.20*sin(.pi*t),
                                           start.z+(end.z-start.z)*t)
                node.eulerAngles = SCNVector3(-0.015,atan2(end.x-start.x,end.z-start.z),0.065*sin(2 * .pi*t))
            }
            bird.position = start;bird.opacity = 0;bird.name = "bird"
            scnScene.rootNode.addChildNode(bird)
            let fade = SCNAction.sequence([.fadeIn(duration:0.8),.wait(duration:13.2),.fadeOut(duration:1)])
            bird.runAction(.sequence([
                .wait(duration:8+Double(i)*19),
                .repeatForever(.sequence([
                    // Action blocks run on the render thread; sound lives on main.
                    .run { node in
                        let visible = !node.isHidden
                        DispatchQueue.main.async { if visible { SoundManager.shared.playBirdFlyby() } }
                    },
                    .group([flight,fade]),
                    .run { $0.position = start },
                    .wait(duration:55+Double(i)*23),
                ])),
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
        guard daylight == .night, !weather.hasPrecipitation,
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
        cam.orthographicScale = ScreenshotMode.zoom ?? 7.5
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
        // Only as deep as the topsoil layer of the rim around it, so it can never
        // poke out through the island's narrower layers further down.
        let island = SCNBox(width: w, height: 0.9, length: w, chamferRadius: 0.35)
        let grass = SCNMaterial()
        grass.diffuse.contents = MeadowGround.texture(width: w, cols: cols)
        grass.diffuse.wrapS = .clamp
        grass.diffuse.wrapT = .clamp
        grass.lightingModel = .lambert
        let soil = Self.cliffSoilMaterial()
        island.materials = [soil, soil, soil, soil, grass, soil]  // top = grass
        let node = SCNNode(geometry: island)
        node.position = SCNVector3(0, -0.45, 0)                   // top surface at y = 0
        node.name = "island"
        scnScene.rootNode.addChildNode(node)
        islandNode = node
        buildIslandRim()
    }

    // MARK: - Island rim
    //
    // The island's body around the town plateau: an organic shoreline, layered
    // earth and rock tapering away underneath, and life on the cliffs. Nothing
    // stands on top of it — every patch of ground you can see from above is the
    // player's to build on or decorate.

    private func buildIslandRim() {
        rimNode?.removeFromParentNode()
        let root = SCNNode()
        root.name = "islandRim"

        let H = Float(cols) / 2 + 0.8                      // plateau half-size
        // Just under the plateau's top, so the two read as one lawn running out
        // to an organic coast.
        let ground: Float = -0.03
        let outline = Self.rimOutline(half: H, samples: 32)

        func lambert(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            m.lightingModel = .lambert
            return m
        }

        // Keep a thin, continuous turf edge; the body beneath is one tapered
        // mesh, so the silhouette has no stack of horizontal shelves.
        root.addChildNode(Self.rimLayer(outline, scale: 1, top: ground,
                                       depth: 0.92,
                                       topMaterial: lambert(0.54, 0.68, 0.41),
                                       sideMaterial: Self.cliffSoilMaterial(), chamfer: 0.16))
        root.addChildNode(Self.islandRock(outline: outline, half: H))

        // Everything else lives on the cliff faces and underneath — waterfalls,
        // roots, vines, a mouse. The top of the island is the player's alone:
        // fixed scenery up there, which you could neither move nor build over,
        // only got in the way.
        decorateCliffs(into: root, half: H, ground: ground)

        // Scenery, never something you tap.
        root.enumerateHierarchy { n, _ in n.categoryBitMask = Self.decorCategory }
        scnScene.rootNode.addChildNode(root)
        rimNode = root
    }

    // MARK: - Cliffs: waterfalls, roots, vines and small life
    //
    // Only the faces the camera can see get dressed — it never swings round to
    // the back, so geometry there would be wasted.

    /// Springs on the visible cliff faces: direction, height of the spring and width.
    private static let waterfalls: [(phi: Float, top: Float, width: CGFloat)] = [
        (1.8, -0.36, 0.34),
        (0.22, -0.5, 0.26),
        (1.18, -0.7, 0.2),
    ]
    /// Scale the depth with the plateau: at this camera angle a shallow taper
    /// disappears behind the near edge and reads as a floating board.
    private static func islandDepth(half: Float) -> Float { half * 1.5 + 1.5 }

    /// Muted earth with a cool lower edge, continuous across the plateau and
    /// its curved rim. World coordinates keep the subtle grain aligned.
    private static func cliffSoilMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.64, green: 0.63, blue: 0.57, alpha: 1)
        material.lightingModel = .lambert
        material.shaderModifiers = [
            .geometry: """
                #pragma varyings
                float3 cliffPosition;
                #pragma body
                out.cliffPosition = (scn_node.modelTransform * _geometry.position).xyz;
                """,
            .surface: """
                #pragma body
                float3 p = in.cliffPosition;
                float grain = sin(p.x * 21.0 + p.z * 17.0 + p.y * 29.0)
                            * sin(p.x * 11.0 - p.z * 23.0) * 0.008;
                float strata = sin(p.x * 1.7 + p.z * 1.3 + p.y * 6.0
                                   + sin(p.x * 0.7 - p.z * 0.9)) * 0.018;
                float depth = smoothstep(0.12, 0.92, -p.y);
                _surface.diffuse.rgb *= mix(float3(1.0), float3(1.03, 1.10, 1.26), depth)
                                      * (1.0 + grain + strata);
                """
        ]
        return material
    }

    private func decorateCliffs(into root: SCNNode, half H: Float, ground: Float) {
        var seed: UInt64 = 0xC11F_F5ED &+ UInt64(cols)
        func rnd() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        func lambert(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            m.lightingModel = .lambert
            return m
        }
        /// Faces turned towards the camera, which sits out along +x/+z.
        func visible(_ phi: Float) -> Bool {
            let f = Self.coastFrame(phi, half: H)
            return f.n.x + f.n.z > 0.25
        }
        // the visible arc runs roughly from the right-hand corner to the left one
        let arc: ClosedRange<Float> = -0.75...(Float.pi * 0.75 + 0.35)
        func randomVisibleAngle() -> Float {
            for _ in 0..<20 {
                let a = arc.lowerBound + rnd() * (arc.upperBound - arc.lowerBound)
                if visible(a) { return a }
            }
            return 0.4
        }

        // Springs fall freely past the cliffs and dissolve into the atmosphere.
        let falls = Self.waterfalls
        let springStone = lambert(0.57, 0.60, 0.53)
        let foam = lambert(0.83, 0.89, 0.81)
        for fall in falls where visible(fall.phi) {
            let f = Self.coastFrame(fall.phi, half: H)
            let length = Self.islandDepth(half: H) * (0.48 + 0.04 * sin(fall.phi * 3)) + fall.top
            let water = Self.waterfall(width: fall.width, length: CGFloat(length), phase: fall.phi * 2.1)
            water.simdPosition = f.p + f.n * 0.035 + SIMD3(0, fall.top - length / 2, 0)
            water.eulerAngles.y = atan2(f.n.x, f.n.z)
            root.addChildNode(water)

            // Small, weathered lips set the spring into the cliff face.
            for side: Float in [-1, 1] {
                let pebble = SCNSphere(radius: fall.width * 0.28)
                pebble.segmentCount = 6
                pebble.materials = [springStone]
                let lip = SCNNode(geometry: pebble)
                lip.simdPosition = f.p + f.t * (side * Float(fall.width) * 0.48)
                    + f.n * 0.018 + SIMD3(0, fall.top + 0.025, 0)
                lip.scale = SCNVector3(0.9, 0.5, 0.55)
                lip.eulerAngles.y = atan2(f.n.x, f.n.z)
                root.addChildNode(lip)
            }
            let froth = SCNSphere(radius: fall.width * 0.33)
            froth.segmentCount = 8
            froth.materials = [foam]
            let fn = SCNNode(geometry: froth)
            fn.simdPosition = f.p + f.n * 0.05 + SIMD3(0, fall.top + 0.015, 0)
            fn.scale = SCNVector3(1, 0.18, 0.45)
            fn.eulerAngles.y = atan2(f.n.x, f.n.z)
            root.addChildNode(fn)
        }
        func nearFall(_ phi: Float) -> Bool { falls.contains { abs($0.phi - phi) < 0.09 } }

        // Static dressing below is merged into one mesh (all direct children,
        // all low-poly).
        let dressing = SCNNode()
        let root1 = lambert(0.50, 0.50, 0.44), root2 = lambert(0.55, 0.56, 0.51)
        let vine = lambert(0.33, 0.53, 0.28), leaf = lambert(0.44, 0.66, 0.34)
        let petals = [lambert(0.97, 0.62, 0.72), lambert(0.99, 0.86, 0.38),
                      lambert(0.97, 0.95, 0.90), lambert(0.74, 0.62, 0.92)]
        let down = SIMD3<Float>(0, -1, 0)

        /// A crooked root: a few segments drooping under their own weight.
        func growRoot(from start: SIMD3<Float>, heading: SIMD3<Float>, segments: Int,
                      length: Float, radius: CGFloat, droop: Float = 0.6) {
            var p = start, dir = simd_normalize(heading)
            for i in 0..<segments {
                let bend = SIMD3<Float>((rnd() - 0.5) * 0.7, 0, (rnd() - 0.5) * 0.7)
                dir = simd_normalize(dir + down * droop + bend)
                let next = p + dir * length * (0.8 + rnd() * 0.4)
                let r = radius * CGFloat(1 - Float(i) / Float(segments + 1) * 0.6)
                dressing.addChildNode(Self.segment(from: p, to: next, radius: r,
                                                   material: i < segments / 2 ? root1 : root2))
                p = next
            }
        }

        // roots breaking out of the topsoil face in little bunches, drooping
        for _ in 0..<(8 + cols / 2) {
            let a = randomVisibleAngle()
            guard !nearFall(a) else { continue }
            let f = Self.coastFrame(a, half: H)
            let y = -0.28 - rnd() * 0.55
            for k in 0..<(1 + Int(rnd() * 3)) {
                let spread = f.t * (Float(k) - 1) * 0.05
                growRoot(from: f.p + f.n * 0.01 + spread + SIMD3(0, y - Float(k) * 0.03, 0),
                         heading: f.n + f.t * (rnd() - 0.5) * 0.8,
                         segments: 3 + Int(rnd() * 2), length: 0.085, radius: 0.014)
            }
        }
        // vines with small flowers hanging from the grass edge
        for _ in 0..<(12 + cols / 2) {
            let a = randomVisibleAngle()
            guard !nearFall(a) else { continue }
            let f = Self.coastFrame(a, half: H)
            var p = f.p + f.n * 0.022 + SIMD3(0, ground - 0.13, 0)
            let segments = 4 + Int(rnd() * 4)
            for i in 0..<segments {
                let sway = f.t * (rnd() - 0.5) * 0.07
                let next = p + SIMD3(0, -0.1 - rnd() * 0.04, 0) + sway
                dressing.addChildNode(Self.segment(from: p, to: next, radius: 0.007, material: vine))
                let leafBall = SCNSphere(radius: 0.022)
                leafBall.segmentCount = 5
                leafBall.materials = [leaf]
                let l = SCNNode(geometry: leafBall)
                l.simdPosition = next + f.t * (i % 2 == 0 ? 0.018 : -0.018) + f.n * 0.01
                l.scale = SCNVector3(1, 0.6, 0.5)
                dressing.addChildNode(l)
                if rnd() < 0.42 {
                    let bloom = SCNSphere(radius: 0.017)
                    bloom.segmentCount = 5
                    bloom.materials = [petals[Int(rnd() * 3.99)]]
                    let b = SCNNode(geometry: bloom)
                    b.simdPosition = next + f.n * 0.025 + f.t * (rnd() - 0.5) * 0.04
                    dressing.addChildNode(b)
                }
                p = next
            }
        }
        root.addChildNode(dressing.flattenedClone())

        // --- Small life on the cliff: a couple of snails and a mouse at its hole
        for (i, a) in [0.62, 2.05].enumerated() where visible(Float(a)) && !nearFall(Float(a)) {
            let f = Self.coastFrame(Float(a), half: H)
            root.addChildNode(Self.snail(frame: f, at: f.p + SIMD3(0, -0.5 - Float(i) * 0.25, 0),
                                         delay: Double(i) * 6))
        }
        let mouseAngle: Float = 0.92
        if visible(mouseAngle), !nearFall(mouseAngle) {
            let f = Self.coastFrame(mouseAngle, half: H)
            root.addChildNode(Self.mouseHole(frame: f, at: f.p + SIMD3(0, -0.42, 0)))
        }
    }

    // MARK: - Tapered stone and height atmosphere

    /// Broad, irregular stone facets beneath the turf. Every ring shares its
    /// vertices with its neighbours, so expansion never opens cracks.
    private static func islandRock(outline: [(x: Float, z: Float)], half H: Float) -> SCNNode {
        let depth = islandDepth(half: H)
        let levels: [(fraction: Float, scale: Float)] = [
            (0, 1), (0.12, 0.97), (0.33, 0.82),
            (0.58, 0.58), (0.81, 0.28), (1, 0.025)
        ]
        let count = outline.count
        var rings: [[SIMD3<Float>]] = []
        for (level, ring) in levels.enumerated() {
            rings.append(outline.enumerated().map { i, p in
                let a = Float(i) / Float(count) * 2 * Float.pi
                let t = ring.fraction
                let irregularity = level == 0 ? 0 : sin(a * 5 + Float(level) * 0.8) * 0.035
                    + sin(a * 9 + 1.2) * 0.018
                let scale = ring.scale * (1 + irregularity)
                let ripple = level == 0 ? 0 : (sin(a * 3 + Float(level)) * 0.034
                    + sin(a * 7 + 0.8) * 0.016) * depth
                return SIMD3(p.x * scale + H * 0.11 * t,
                             -0.86 - (depth - 0.86) * t + ripple,
                             p.z * scale - H * 0.04 * t)
            })
        }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        var colors: [SIMD4<Float>] = []
        func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, tint: Float) {
            var points = [a, b, c]
            var normal = simd_normalize(simd_cross(b - a, c - a))
            let centre = (a + b + c) / 3
            if simd_dot(normal, SIMD3(centre.x, 0, centre.z)) < 0 {
                points.swapAt(1, 2)
                normal = -normal
            }
            for p in points {
                vertices.append(SCNVector3(p.x, p.y, p.z))
                normals.append(SCNVector3(normal.x, normal.y, normal.z))
                let t = max(0, (-p.y - 0.86) / (depth - 0.86))
                coordinates.append(CGPoint(x: CGFloat(p.x / H), y: CGFloat(t)))
                // Match the soil's lower edge in linear color, then cool to slate.
                let blend = min(1, t * 3)
                let earth = SIMD3<Float>(0.38, 0.39, 0.36)
                let stone = SIMD3<Float>(0.43, 0.46, 0.46)
                let color = earth + (stone - earth) * blend + SIMD3(repeating: tint)
                colors.append(SIMD4(color.x, color.y, color.z, 1))
            }
        }
        for level in 0..<(rings.count - 1) {
            for i in 0..<count {
                let j = (i + 1) % count
                let tint = sin(Float(i) * 2.37 + Float(level) * 0.71) * 0.025
                triangle(rings[level][i], rings[level][j], rings[level + 1][i], tint: tint)
                triangle(rings[level][j], rings[level + 1][j], rings[level + 1][i], tint: tint)
            }
        }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color,
                                            vectorCount: colors.count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
                                            dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let indices = (0..<vertices.count).map { UInt32($0) }
        let geometry = SCNGeometry(sources: [
            SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
            SCNGeometrySource(textureCoordinates: coordinates), colorSource
        ], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .lambert
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        // SceneKit expects premultiplied color here; fading all four channels
        // blends the rock into the sky without tinting the playable ground.
        material.shaderModifiers = [.fragment: """
            #pragma transparent
            #pragma body
            float height = _surface.diffuseTexcoord.y;
            float veil = smoothstep(0.04, 0.82, height);
            _output.color *= 1.0 - veil;
            """]
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = "islandStone"
        node.castsShadow = false
        return node
    }

    /// Coast point in a direction, with its outward normal and the tangent
    /// running along the shore.
    private static func coastFrame(_ phi: Float, half H: Float)
        -> (p: SIMD3<Float>, n: SIMD3<Float>, t: SIMD3<Float>) {
        func point(_ a: Float) -> SIMD3<Float> {
            let r = coastRadius(a, half: H)
            return SIMD3(cos(a) * r, 0, sin(a) * r)
        }
        let p = point(phi)
        let t = simd_normalize(point(phi + 0.01) - point(phi - 0.01))
        var n = SIMD3<Float>(t.z, 0, -t.x)
        if simd_dot(n, p) < 0 { n = -n }
        return (p, n, t)
    }

    /// A thin low-poly cylinder between two points.
    private static func segment(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat,
                                material: SCNMaterial) -> SCNNode {
        let d = b - a
        let length = simd_length(d)
        let g = SCNCylinder(radius: radius, height: CGFloat(length))
        g.radialSegmentCount = 5
        g.materials = [material]
        let n = SCNNode(geometry: g)
        n.simdPosition = (a + b) / 2
        // a cylinder looks the same either way up, so never ask for a 180° turn
        let dir = d / max(length, 0.0001)
        n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: dir.y >= 0 ? dir : -dir)
        return n
    }

    /// A tapering, gently bowed ribbon: simple water planes and broad moving
    /// highlights fit the town's low-poly shapes without a tiled noise texture.
    private static func waterfall(width: CGFloat, length: CGFloat, phase: Float) -> SCNNode {
        let rows = 32, columns = 3
        let w = Float(width), h = Float(length)
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uv: [CGPoint] = []
        for row in 0...rows {
            let t = Float(row) / Float(rows)
            let span = w * (0.92 - 0.46 * sqrt(t))
            let bow = w * 0.48 * (1 - exp(-t * 24))
            let drift = w * 0.12 * t * t * sin(phase)
            for column in 0..<columns {
                let u = Float(column) / Float(columns - 1)
                vertices.append(SCNVector3((u - 0.5) * span + drift, h * (0.5 - t),
                                           bow + w * 0.10 * (1 - pow(2 * u - 1, 2))))
                normals.append(SCNVector3((u - 0.5) * 0.3, 0, 1))
                uv.append(CGPoint(x: CGFloat(u), y: CGFloat(t)))
            }
        }
        var indices: [UInt32] = []
        for row in 0..<rows {
            for column in 0..<(columns - 1) {
                let a = UInt32(row * columns + column), b = a + UInt32(columns)
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        let ribbon = SCNGeometry(sources: [
            SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
            SCNGeometrySource(textureCoordinates: uv)
        ], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.69, green: 0.83, blue: 0.80, alpha: 1)
        material.lightingModel = .lambert
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        let flowSpeed: Float = UIAccessibility.isReduceMotionEnabled ? 0 : 1.5
        material.shaderModifiers = [
            .surface: """
                #pragma body
                float2 uv = _surface.diffuseTexcoord;
                float centre = 1.0 - smoothstep(0.0, 0.55, abs(uv.x - 0.44));
                float flow = pow(0.5 + 0.5 * sin(uv.y * \(h) * 2.2
                                 - scn_frame.time * \(flowSpeed) + \(phase)), 6.0);
                float glint = (1.0 - smoothstep(0.04, 0.24, abs(uv.x - 0.38))) * flow;
                _surface.diffuse.rgb *= 0.92 + centre * 0.14 + glint * 0.16;
                """,
            .fragment: """
                #pragma transparent
                #pragma body
                float2 fallCoord = _surface.diffuseTexcoord;
                float edges = smoothstep(0.0, 0.22, fallCoord.x)
                            * (1.0 - smoothstep(0.78, 1.0, fallCoord.x));
                float dissolve = 1.0 - smoothstep(0.18, 0.94, fallCoord.y);
                _output.color *= edges * dissolve * 0.86;
                """
        ]
        ribbon.materials = [material]
        let node = SCNNode(geometry: ribbon)
        node.castsShadow = false
        return node
    }

    /// A snail inching back and forth across the earth face. The outer node
    /// stands in the wall's frame (local +z = out of the wall); the inner one
    /// turns round at each end.
    private static func snail(frame f: (p: SIMD3<Float>, n: SIMD3<Float>, t: SIMD3<Float>),
                              at position: SIMD3<Float>, delay: Double) -> SCNNode {
        let holder = SCNNode()
        holder.simdPosition = position + f.n * 0.004
        holder.eulerAngles.y = atan2(f.n.x, f.n.z)
        let body = SCNNode()
        holder.addChildNode(body)

        func part(_ g: SCNGeometry, _ r: CGFloat, _ gr: CGFloat, _ b: CGFloat,
                  _ p: SCNVector3, scale: SCNVector3 = SCNVector3(1, 1, 1)) {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: r, green: gr, blue: b, alpha: 1)
            m.lightingModel = .lambert
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position = p
            n.scale = scale
            body.addChildNode(n)
        }
        let foot = SCNCapsule(capRadius: 0.012, height: 0.08)
        part(foot, 0.72, 0.68, 0.58, SCNVector3(0, 0, 0.012))
        body.childNodes.last?.eulerAngles.z = .pi / 2
        let shell = SCNSphere(radius: 0.032)
        shell.segmentCount = 10
        part(shell, 0.74, 0.50, 0.28, SCNVector3(-0.008, 0.016, 0.03), scale: SCNVector3(1, 1, 0.75))
        let swirl = SCNSphere(radius: 0.016)
        swirl.segmentCount = 8
        part(swirl, 0.56, 0.36, 0.20, SCNVector3(-0.008, 0.016, 0.052), scale: SCNVector3(1, 1, 0.5))
        for dy in [0.008, -0.008] as [Float] {
            let stalk = SCNCylinder(radius: 0.003, height: 0.03)
            part(stalk, 0.72, 0.68, 0.58, SCNVector3(0.045, 0.012 + dy, 0.02))
            body.childNodes.last?.eulerAngles.z = -0.7
        }

        // Two loops with the same 43.2 s period: the holder crawls, the body turns
        // round in the pauses. No callbacks — actions run on the render thread.
        let step = f.t * 0.32
        let crawl = SCNAction.sequence([
            .moveBy(x: CGFloat(step.x), y: 0, z: CGFloat(step.z), duration: 18),
            .wait(duration: 3.6),
            .moveBy(x: CGFloat(-step.x), y: 0, z: CGFloat(-step.z), duration: 18),
            .wait(duration: 3.6),
        ])
        let turn = SCNAction.sequence([
            .wait(duration: 20),
            .rotateBy(x: 0, y: 0, z: .pi, duration: 1.6),
            .wait(duration: 20),
            .rotateBy(x: 0, y: 0, z: .pi, duration: 1.6),
        ])
        holder.runAction(.sequence([.wait(duration: delay), .repeatForever(crawl)]))
        body.runAction(.sequence([.wait(duration: delay), .repeatForever(turn)]))
        return holder
    }

    /// A burrow in the earth face; now and then a mouse pokes its head out.
    private static func mouseHole(frame f: (p: SIMD3<Float>, n: SIMD3<Float>, t: SIMD3<Float>),
                                  at position: SIMD3<Float>) -> SCNNode {
        let holder = SCNNode()
        holder.simdPosition = position
        holder.eulerAngles.y = atan2(f.n.x, f.n.z)

        func mat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            m.lightingModel = .lambert
            return m
        }
        let hole = SCNCylinder(radius: 0.06, height: 0.01)
        hole.radialSegmentCount = 12
        hole.materials = [mat(0.16, 0.12, 0.10)]
        let h = SCNNode(geometry: hole)
        h.eulerAngles.x = .pi / 2
        h.position = SCNVector3(0, 0, 0.008)
        h.scale = SCNVector3(1, 1, 0.8)
        holder.addChildNode(h)

        // Starts tucked behind the face, where the earth hides it.
        let head = SCNNode()
        head.position = SCNVector3(0, -0.005, -0.06)
        holder.addChildNode(head)
        let skull = SCNSphere(radius: 0.036)
        skull.segmentCount = 10
        skull.materials = [mat(0.58, 0.52, 0.48)]
        let sk = SCNNode(geometry: skull)
        sk.scale = SCNVector3(1, 0.9, 1.15)
        head.addChildNode(sk)
        for x in [-0.026, 0.026] as [Float] {
            let ear = SCNSphere(radius: 0.017)
            ear.segmentCount = 8
            ear.materials = [mat(0.80, 0.62, 0.62)]
            let e = SCNNode(geometry: ear)
            e.position = SCNVector3(x, 0.03, -0.005)
            e.scale = SCNVector3(1, 1, 0.4)
            head.addChildNode(e)
            let eye = SCNSphere(radius: 0.006)
            eye.segmentCount = 6
            eye.materials = [mat(0.08, 0.07, 0.07)]
            let ey = SCNNode(geometry: eye)
            ey.position = SCNVector3(x * 0.55, 0.01, 0.034)
            head.addChildNode(ey)
        }
        let nose = SCNSphere(radius: 0.008)
        nose.segmentCount = 6
        nose.materials = [mat(0.92, 0.55, 0.60)]
        let ns = SCNNode(geometry: nose)
        ns.position = SCNVector3(0, -0.004, 0.044)
        head.addChildNode(ns)

        let peek = SCNAction.sequence([
            .wait(duration: 5, withRange: 6),
            .moveBy(x: 0, y: 0, z: 0.075, duration: 0.35),
            .wait(duration: 1.8, withRange: 1.2),
            .moveBy(x: 0, y: 0, z: -0.075, duration: 0.3),
        ])
        peek.timingMode = .easeInEaseOut
        head.runAction(.repeatForever(peek))
        return holder
    }

    /// How far the coast sits beyond the town plateau, by direction (radians,
    /// measured in the ground plane from +x towards +z). Kept to a thin, wobbly
    /// shoreline: wide enough that the island doesn't look cut with a ruler,
    /// too narrow for anything to stand on it.
    private static func rimMargin(_ phi: Float) -> Float {
        0.38 + 0.12 * sin(3 * phi + 1.3) + 0.08 * sin(5 * phi + 0.4) + 0.05 * sin(9 * phi + 2.1)
    }

    private static func distanceToSquare(_ x: Float, _ z: Float, half H: Float) -> Float {
        let dx = max(abs(x) - H, 0), dz = max(abs(z) - H, 0)
        return (dx * dx + dz * dz).squareRoot()
    }

    /// Distance from the centre to the coast in a direction: the point whose
    /// distance to the plateau equals the margin there. Measuring from the square
    /// rather than the centre is what rounds the corners off naturally.
    private static func coastRadius(_ phi: Float, half H: Float) -> Float {
        let ux = cos(phi), uz = sin(phi), m = rimMargin(phi)
        var lo: Float = 0, hi: Float = 2 * H + 3 * m + 1
        for _ in 0..<32 {
            let mid = (lo + hi) / 2
            if distanceToSquare(ux * mid, uz * mid, half: H) < m { lo = mid } else { hi = mid }
        }
        return lo
    }

    private static func rimOutline(half H: Float, samples n: Int) -> [(x: Float, z: Float)] {
        (0..<n).map { k in
            let phi = Float(k) / Float(n) * 2 * .pi
            let r = coastRadius(phi, half: H)
            return (cos(phi) * r, sin(phi) * r)
        }
    }

    /// One slab of island: the outline extruded downwards from `top`.
    private static func rimLayer(_ outline: [(x: Float, z: Float)], scale: Float, top: Float,
                                 depth: CGFloat, topMaterial: SCNMaterial,
                                 sideMaterial: SCNMaterial, chamfer: CGFloat) -> SCNNode {
        let path = UIBezierPath()
        for (i, p) in outline.enumerated() {
            // The shape is drawn in XY and laid flat below: path y becomes world −z.
            let pt = CGPoint(x: CGFloat(p.x * scale), y: CGFloat(-p.z * scale))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = chamfer
        shape.chamferMode = .front
        // Elements: front (the top once laid flat), back, sides, front chamfer
        shape.materials = [topMaterial, sideMaterial, sideMaterial, topMaterial]
        let node = SCNNode(geometry: shape)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, top - Float(depth) / 2, 0)
        return node
    }


    private var meadowSamples: [SCNNode] = []
    private var meadowRefreshScheduled = false

    private func scatterGroundDetails() {
        meadowSamples = MeadowGround.details(cols: cols)
        refreshGroundDetails()
    }

    /// Coalesce placement/loading changes and merge the sparse scenery into a few material batches.
    private func refreshGroundDetails() {
        guard !meadowRefreshScheduled else { return }
        meadowRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.meadowRefreshScheduled = false
            self.rebuildMeadowDetails()
        }
    }

    private func rebuildMeadowDetails() {
        var occupied = Set<SIMD2<Int>>()
        for building in buildingNodes {
            for o in building.occupiedOffsets { occupied.insert(SIMD2(building.gridX+o.dx,building.gridY+o.dy)) }
        }
        var corners: [SCNVector3] = []
        var bowls: [SCNVector3] = []
        for decoration in decorationNodes {
            if decoration.type == .doghouse,
               let bowl = decoration.childNode(withName: "bowl", recursively: true) {
                bowls.append(bowl.worldPosition)
            }
            if decoration.isCornerAnchor {
                corners.append(cornerToWorld(cx: decoration.gridX, cy: decoration.gridY))
            } else {
                let fp = decoration.type.footprint
                for x in 0..<fp.w { for z in 0..<fp.l { occupied.insert(SIMD2(decoration.gridX+x,decoration.gridY+z)) } }
            }
        }
        let group = SCNNode()
        for sample in meadowSamples {
            let cell = worldToGrid(sample.position)
            guard !occupied.contains(SIMD2(cell.col,cell.row)),
                  !corners.contains(where: { p in
                      let dx = p.x-sample.position.x, dz = p.z-sample.position.z
                      return dx*dx+dz*dz < 0.32*0.32
                  }),
                  !bowls.contains(where: { p in
                      let dx = p.x-sample.position.x, dz = p.z-sample.position.z
                      return dx*dx+dz*dz < 0.34*0.34
                  }) else { continue }
            group.addChildNode(sample.clone())
        }
        scnScene.rootNode.childNodes.filter { $0.name == "groundDetail" }.forEach { $0.removeFromParentNode() }
        // Commit the detached patches' transforms before SceneKit bakes them;
        // otherwise freshly cloned patches can all collapse at the map origin.
        scnScene.rootNode.addChildNode(group)
        SCNTransaction.flush()
        let merged = group.flattenedClone()
        group.removeFromParentNode()
        merged.name = "groundDetail"
        merged.enumerateHierarchy { n,_ in n.categoryBitMask = Self.decorCategory; n.castsShadow = false }
        scnScene.rootNode.addChildNode(merged)
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
        refreshGroundDetails()
        node.nightLighting?.apply(buildingLightPhase)
        refreshLocalBuildingLights()
        refreshRoadAccess()

        if animated {
            node.scale = SCNVector3(0.01, 0.01, 0.01)
            let pop = SCNAction.sequence([
                .scale(to: 1.12, duration: 0.24),
                .scale(to: 1.0,  duration: 0.12)
            ])
            pop.timingMode = .easeOut
            node.runAction(pop)
            moveCamera(to: node.position)
            // Action blocks run on SceneKit's render thread; adding the confetti
            // from there raced the main thread building the town.
            let spot = node.position
            scnScene.rootNode.runAction(.sequence([
                .wait(duration: 0.5),
                .run { [weak self] _ in
                    DispatchQueue.main.async { self?.celebrate(at: spot) }
                }
            ]))
        }
        return node
    }

    func moveCamera(to p: SCNVector3) {
        let move = SCNAction.move(to: SCNVector3(p.x, 0, p.z), duration: 0.5)
        move.timingMode = .easeInEaseOut
        cameraRig.runAction(.sequence([move, .run { [weak self] _ in
            DispatchQueue.main.async { self?.refreshLocalBuildingLights() }
        }]))
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
        refreshGroundDetails()
        if type == .road { refreshRoadAccess() }
        if type == .birdFeeder { node.startFeederVisits() }
        if type == .firePit { node.setFireLit(isAfterDark); onAtmosphereChanged?() }
        if type == .streetLamp {
            node.streetLighting?.apply(buildingLightPhase)
            refreshLocalBuildingLights()
        }
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
        if node.type == .streetLamp {
            node.streetLighting?.setLocalLightEnabled(false)
            refreshLocalBuildingLights()
        }
        if node.type == .firePit { onAtmosphereChanged?() }
        refreshGroundDetails()
        node.runAction(.sequence([
            .group([.scale(to: 0.01, duration: 0.18), .fadeOut(duration: 0.18)]),
            .removeFromParentNode()
        ]))
        if node.type == .road { refreshRoadAccess() }
    }

    func removeBuilding(_ node: BuildingNode) {
        buildingNodes.removeAll { $0 === node }
        refreshGroundDetails()
        refreshLocalBuildingLights()
        refreshRoadAccess()
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
                let phase = DaylightPhase(hour: ScreenshotMode.currentHour())
                return phase == .night || phase == .dusk
            }
        )
        // A doghouse to sleep in, and a filled bowl to trot over to.
        node.findBed = { [weak self] animal in self?.freeKennel(for: animal) }
        node.findBowl = { [weak self] animal in
            guard animal.kind.usesDoghouse else { return nil }   // it's dog food
            return self?.filledBowl(for: animal)
        }
        node.playerFacingYaw = { [weak self] animal in
            guard let self else { return animal.eulerAngles.y }
            let camera = self.cameraNode.presentation.worldPosition
            let pet = animal.worldPosition
            return atan2(camera.x - pet.x, camera.z - pet.z)
        }

        let cell = randomWalkableLandCell()
        node.place(col: cell.col, row: cell.row)
        scnScene.rootNode.addChildNode(node)
        animalNodes.append(node)
        // Load the downloaded glTF; adoptRig adds the model and starts it living.
        AnimalModelLoader.loadRig(kind) { [weak self, weak node] visual, clips in
            node?.adoptRig(visual: visual, clips: clips)
            self?.scheduleWarmUp()
        }
        return node
    }

    /// Fired when a pet finishes the food in a bowl, so the model layer can
    /// clear the stored `hasFood` flag.
    var onBowlEmptied: ((PlacedDecoration) -> Bool)?

    /// Pick the nearest reachable free doorway, rather than the first house
    /// in the array. A house is reserved as soon as its pet starts travelling.
    private func freeKennel(for animal: AnimalNode) -> AnimalKennelDestination? {
        guard animal.kind.usesDoghouse else { return nil }
        let claims = Set(animalNodes.filter { $0 !== animal }.compactMap(\.claimedKennelID))
        var best: (destination: AnimalKennelDestination, distance: Int)?
        for house in decorationNodes where house.type == .doghouse {
            let id = ObjectIdentifier(house)
            guard !claims.contains(id), let bed = house.doghouseBed else { continue }
            let cell = AnimalCell(col: house.gridX, row: house.gridY)
            let entrance = AnimalCell(col: cell.col + Int(sin(bed.yaw).rounded()),
                                      row: cell.row + Int(cos(bed.yaw).rounded()))
            let land: (AnimalCell) -> Bool = { [weak self] cell in
                guard let self else { return false }
                return self.isAnimalWalkable(col: cell.col, row: cell.row)
                    && !self.isWater(col: cell.col, row: cell.row)
            }
            guard land(entrance), let route = AnimalNavigation.route(
                from: AnimalCell(col: animal.col, row: animal.row), to: [entrance], isWalkable: land
            ), best == nil || route.count < best!.distance else { continue }
            let world = SCNVector3(house.position.x + bed.offset.x, bed.offset.y,
                                   house.position.z + bed.offset.z)
            let destination = AnimalKennelDestination(id: id, cell: cell, entrance: entrance,
                                                      world: world, yaw: bed.yaw) { [weak self, weak house] in
                guard let self, let house, self.decorationNodes.contains(where: { $0 === house }),
                      house.gridX == cell.col, house.gridY == cell.row,
                      abs(house.eulerAngles.y - bed.yaw) < 0.01 else { return false }
                return true
            }
            best = (destination, route.count)
        }
        return best?.destination
    }

    /// One reachable bowl per dog. The reservation covers walking and eating;
    /// moving/storing the kennel invalidates the trip without consuming food.
    private func filledBowl(for animal: AnimalNode) -> AnimalBowlDestination? {
        let claims = Set(animalNodes.filter { $0 !== animal }.compactMap(\.claimedBowlID))
        var best: (destination: AnimalBowlDestination, distance: Int)?
        for house in decorationNodes where house.type == .doghouse && house.bowlHasFood {
            let id = ObjectIdentifier(house)
            guard !claims.contains(id), let bowl = house.childNode(withName: "bowl", recursively: true) else { continue }
            let cell = AnimalCell(col: house.gridX, row: house.gridY)
            let yaw = house.eulerAngles.y
            let entrance = AnimalCell(col: cell.col + Int(sin(yaw).rounded()),
                                      row: cell.row + Int(cos(yaw).rounded()))
            let land: (AnimalCell) -> Bool = { [weak self] cell in
                guard let self else { return false }
                return self.isAnimalWalkable(col: cell.col, row: cell.row) && !self.isWater(col: cell.col, row: cell.row)
            }
            guard land(entrance), let route = AnimalNavigation.route(
                from: AnimalCell(col: animal.col, row: animal.row), to: [entrance], isWalkable: land),
                best == nil || route.count < best!.distance else { continue }
            let position = house.position
            let bowlWorld = bowl.worldPosition
            let reach = DogFeedingMotion.muzzleReach(for: animal.kind)
            let standing = SCNVector3(bowlWorld.x + sin(yaw) * reach, 0, bowlWorld.z + cos(yaw) * reach)
            let valid: () -> Bool = { [weak self, weak house] in
                guard let self, let house, self.decorationNodes.contains(where: { $0 === house }),
                      house.bowlHasFood, house.gridX == cell.col, house.gridY == cell.row,
                      abs(house.eulerAngles.y - yaw) < 0.01,
                      hypot(house.position.x - position.x, house.position.z - position.z) < 0.01 else { return false }
                return land(entrance)
            }
            let destination = AnimalBowlDestination(id: id, entrance: entrance, standingWorld: standing,
                yaw: yaw + .pi, isValid: valid,
                updateProgress: { [weak house] progress in house?.setBowlMealProgress(progress) },
                consume: { [weak self, weak house] in
                    guard valid(), let self, let house, let decoration = house.associatedDecoration,
                          self.onBowlEmptied?(decoration) == true else { return false }
                    house.setBowlFilled(false)
                    return true
                })
            best = (destination, route.count)
        }
        return best?.destination
    }

    /// A filled bowl gets noticed promptly, including by a sleeping pet.
    func notifyBowlFilled() {
        let candidates = animalNodes.filter(\.canNoticeFood).compactMap { animal -> (AnimalNode, Int)? in
            guard let bowl = filledBowl(for: animal) else { return nil }
            let distance = abs(animal.col - bowl.entrance.col) + abs(animal.row - bowl.entrance.row)
            return (animal, distance)
        }
        candidates.min { $0.1 < $1.1 }?.0.noticeFood()
    }

    func removeAnimal(_ node: AnimalNode) {
        node.stopLiving()
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
        SoundManager.shared.playRotate()
        b.toggleRotation()
        refreshGroundDetails()
        refreshRoadAccess()
    }

    // MARK: - Road auto-tiling

    /// Recompute from grid state, never from in-flight drag/rotation animations.
    /// Layout caching in each road avoids rebuilding unaffected geometry.
    func refreshRoadAccess() {
        let roads = decorationNodes.filter { $0.type == .road }
        let cells = Set(roads.map { SIMD2($0.gridX, $0.gridY) })
        var connections: [SIMD2<Int>: [RoadEntranceConnection]] = [:]
        for building in buildingNodes {
            let anchor = SIMD2(building.gridX, building.gridY)
            for entrance in building.roadEntrances {
                let end = BuildingRoadEntrance.rotate(entrance.point, steps: building.rotationSteps)
                let direction = BuildingRoadEntrance.rotate(entrance.outward, steps: building.rotationSteps)
                // A centred two-cell entrance uses the first available approach;
                // ordinary doors have exactly one adjacent tile on their front.
                for localCell in entrance.roadCells {
                    let offset = BuildingRoadEntrance.rotate(localCell, steps: building.rotationSteps)
                    let cell = anchor &+ offset
                    guard cells.contains(cell) else { continue }
                    connections[cell, default: []].append(RoadEntranceConnection(
                        end: end - SIMD2(Float(offset.x), Float(offset.y)),
                        outward: direction, width: entrance.width))
                    break
                }
            }
        }
        for road in roads {
            let cell = SIMD2(road.gridX, road.gridY)
            road.rebuildRoad(n: cells.contains(cell &+ SIMD2(0,-1)),
                             e: cells.contains(cell &+ SIMD2(1,0)),
                             s: cells.contains(cell &+ SIMD2(0,1)),
                             w: cells.contains(cell &+ SIMD2(-1,0)),
                             entrances: connections[cell] ?? [])
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
        let hits = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue,
            .categoryBitMask: Self.touchableCategory,
        ])
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
    private func captureGroundBasis() {
        guard let o  = groundPoint(at: .zero),
              let px = groundPoint(at: CGPoint(x: 200, y: 0)),
              let pz = groundPoint(at: CGPoint(x: 0, y: 200))
        else { groundBasis = nil; return }
        groundBasis = (o,
                       SCNVector3((px.x - o.x) / 200, 0, (px.z - o.z) / 200),
                       SCNVector3((pz.x - o.x) / 200, 0, (pz.z - o.z) / 200))
    }

    /// Ground point via the cached basis when a gesture is in flight, otherwise
    /// the exact (slow) unprojection.
    private func fastGroundPoint(at p: CGPoint) -> SCNVector3? {
        guard let b = groundBasis else { return groundPoint(at: p) }
        let x = Float(p.x), y = Float(p.y)
        return SCNVector3(b.o.x + x * b.dx.x + y * b.dz.x, 0,
                          b.o.z + x * b.dx.z + y * b.dz.z)
    }

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
        let hits = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue,
            .categoryBitMask: Self.touchableCategory,
        ])
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
            SoundManager.shared.playRotate()
            d.toggleRotation()
        default:
            break
        }
    }

    /// The map camera's current orthographic scale (smaller = closer).
    var cameraZoom: Double { cameraNode.camera?.orthographicScale ?? 7.5 }

    func handlePinch(scale: CGFloat, began: inout CGFloat) {
        guard let cam = cameraNode.camera else { return }
        if began == 0 { began = cam.orthographicScale }
        cam.orthographicScale = min(16, max(3.5, began / Double(scale)))
        SoundManager.shared.setZoom(orthographicScale: cam.orthographicScale)
    }

    /// One paint step of a road stroke — converts the touch to a grid cell and
    /// notifies once per newly entered cell.
    func paintStroke(at point: CGPoint) {
        if groundBasis == nil { captureGroundBasis() }
        guard let g = fastGroundPoint(at: point) else { return }
        let cell = worldToGrid(g)
        if let last = lastPaintedCell, last == cell { return }
        lastPaintedCell = cell
        onPaintCell?(cell.col, cell.row)
    }

    func endPaintStroke() {
        lastPaintedCell = nil
        groundBasis = nil
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
        captureGroundBasis()
        // One hit test, reused. This used to run `occupantHit` twice and then
        // `animalHit` on top — three full-scene ray casts per press.
        let occupant = occupantHit(at: point)
        // Pets are picked up and carried like anything else on the map.
        if occupant == nil, let a = animalHit(at: point) {
            draggedAnimal = a
            cameraPanEnabled = false
            a.beginCarry()
            a.runAction(.move(to: SCNVector3(a.position.x, 0.5, a.position.z), duration: 0.12))
            return
        }
        guard let b = occupant,
              let g = groundPoint(at: point) else { return }
        draggedNode = b
        dragOffset  = SCNVector3(b.position.x - g.x, 0, b.position.z - g.z)
        dragOffsets = occupiedOffsets(of: b)
        dragBounds  = offsetsBounds(of: b)
        lastGhostCell = nil
        lastGhostValid = nil
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
        ghost.categoryBitMask = Self.decorCategory
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
        if let a = draggedAnimal, let g = fastGroundPoint(at: point) {
            a.position = SCNVector3(g.x, 0.5, g.z)
            return
        }
        guard let b = draggedNode, let g = fastGroundPoint(at: point) else { return }
        b.position = SCNVector3(g.x + dragOffset.x, 0.45, g.z + dragOffset.z)
        let cell = worldToGrid(SCNVector3(b.position.x, 0, b.position.z))
        updateGhost(col: cell.col, row: cell.row)
    }

    func dragEnded(at point: CGPoint) {
        defer { groundBasis = nil }
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
            refreshGroundDetails()
            dn.associatedDecoration?.isCornerAnchor = dn.isCornerAnchor
            dn.associatedDecoration?.gridX = dn.gridX
            dn.associatedDecoration?.gridY = dn.gridY
            let dest = dn.isCornerAnchor
                ? cornerToWorld(cx: dn.gridX, cy: dn.gridY)
                : gridToWorld(col: dn.gridX, row: dn.gridY)
            let settle = SCNAction.move(to: dest, duration: 0.18)
            settle.timingMode = .easeOut
            if dn.type == .streetLamp {
                dn.runAction(.sequence([settle, .run { [weak self] _ in
                    DispatchQueue.main.async { self?.refreshLocalBuildingLights() }
                }]))
            } else {
                dn.runAction(settle)
            }
            return
        }

        let cell = worldToGrid(SCNVector3(b.position.x, 0, b.position.z))
        let valid = canPlace(offsets: occupiedOffsets(of: b),
                             at: cell.col, row: cell.row, excluding: b)

        if valid {
            Haptics.drop()
            b.gridX = cell.col
            b.gridY = cell.row
            switch b {
            case let bn as BuildingNode:
                bn.associatedBuilding?.gridX = cell.col
                bn.associatedBuilding?.gridY = cell.row
                refreshLocalBuildingLights()
                refreshRoadAccess()
            case let dn as DecorationNode:
                dn.associatedDecoration?.gridX = cell.col
                dn.associatedDecoration?.gridY = cell.row
                if dn.type == .road {
                    refreshRoadAccess()
                }
            default:
                break
            }
        } else {
            Haptics.warning()
        }
        refreshGroundDetails()
        let dest = gridToWorld(col: b.gridX, row: b.gridY)
        let settle = SCNAction.move(to: dest, duration: 0.18)
        settle.timingMode = .easeOut
        b.runAction(settle)
    }

    // MARK: - Placement hints (soft dots on free buildable cells)

    /// Quietly shows where building is possible — tiny translucent dots that
    /// appear only while placing or dragging, so they never fight the scenery.
    /// Requests the hint lattice. Entering placement mode sets three properties
    /// in a row and each one used to rebuild the whole thing, so the work is
    /// coalesced onto the next tick and runs once.
    private func showPlacementHints(_ show: Bool) {
        pendingHints = show
        guard !hintsRebuildScheduled else { return }
        hintsRebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hintsRebuildScheduled = false
            self.rebuildPlacementHints(self.pendingHints)
        }
    }

    /// What the lattice actually depends on. The node being dragged is left out
    /// of the occupancy, so putting a tree down and picking the same one up
    /// again produces an identical key — which is the whole point.
    private struct HintsKey: Equatable {
        let cols: Int
        let showCorners: Bool
        let takenTiles: Set<Int>
        let takenCorners: Set<Int>
    }

    private func rebuildPlacementHints(_ show: Bool) {
        hintsNode?.removeFromParentNode()
        hintsNode = nil
        guard show else { return }

        // Occupancy in one pass. The old loop asked `hasOccupant` per tile and
        // that rescanned every building and decoration, so a full island cost
        // tens of thousands of comparisons every time you picked something up.
        var takenTiles = Set<Int>()
        for b in buildingNodes where b !== draggedNode {
            for o in b.occupiedOffsets {
                takenTiles.insert(tileKey(b.gridX + o.dx, b.gridY + o.dy))
            }
        }
        for d in decorationNodes where d !== draggedNode && !d.isCornerAnchor {
            let fp = d.type.footprint
            for dx in 0..<fp.w {
                for dy in 0..<fp.l { takenTiles.insert(tileKey(d.gridX + dx, d.gridY + dy)) }
            }
        }

        // Show the corner lattice whenever greenery is in play — both when
        // placing a new one and when dragging an existing one around.
        let draggingGreenery = (draggedNode as? DecorationNode)?.type.canUseCornerAnchor ?? false
        let showCorners = placingUsesAnchors || draggingGreenery
        var takenCorners = Set<Int>()
        if showCorners {
            for d in decorationNodes where d !== draggedNode && d.isCornerAnchor {
                takenCorners.insert(tileKey(d.gridX, d.gridY))
            }
        }

        let key = HintsKey(cols: cols, showCorners: showCorners,
                           takenTiles: takenTiles, takenCorners: takenCorners)

        // Nothing about the lattice changed since last time, so put the one we
        // already built back on screen. Dropping a tree and picking it straight
        // back up is the common case, and it used to rebuild and re-merge over a
        // thousand dots each round.
        if key == cachedHintsKey, let cached = cachedHints {
            cached.removeAllActions()
            cached.opacity = 0
            cached.runAction(.fadeOpacity(to: 1, duration: 0.22))
            scnScene.rootNode.addChildNode(cached)
            hintsNode = cached
            return
        }

        let group = SCNNode()
        for col in 0..<cols {
            for row in 0..<rows {
                guard !takenTiles.contains(tileKey(col, row)) else { continue }
                let n = SCNNode(geometry: Self.tileHintGeometry)
                let p = gridToWorld(col: col, row: row)
                n.position = SCNVector3(p.x, 0.02, p.z)
                n.eulerAngles.x = -.pi / 2
                group.addChildNode(n)
            }
        }

        if showCorners {
            for cx in 0...cols {
                for cy in 0...rows {
                    guard !takenCorners.contains(tileKey(cx, cy)) else { continue }
                    let n = SCNNode(geometry: Self.cornerHintGeometry)
                    let p = cornerToWorld(cx: cx, cy: cy)
                    n.position = SCNVector3(p.x, 0.02, p.z)
                    n.eulerAngles.x = -.pi / 2
                    group.addChildNode(n)
                }
            }
        }

        // Merge the dots into one node. All of them share a geometry, so this
        // collapses to a couple of draw calls — otherwise SceneKit walks and
        // draws a thousand separate dots on every frame of the drag, which is
        // what made moving a building feel like it was chugging.
        let flattened = group.flattenedClone()
        flattened.enumerateHierarchy { n, _ in n.categoryBitMask = Self.decorCategory }
        flattened.opacity = 0
        flattened.runAction(.fadeOpacity(to: 1, duration: 0.22))
        scnScene.rootNode.addChildNode(flattened)
        hintsNode = flattened
        cachedHints = flattened
        cachedHintsKey = key
    }

    /// Grid key that stays unique for the tile lattice and the corner lattice
    /// alike (both are at most a few dozen wide).
    private func tileKey(_ col: Int, _ row: Int) -> Int { col &* 4096 &+ row }

    private func updateGhost(col: Int, row: Int) {
        guard let ghost = ghostNode, let dragged = draggedNode else { return }
        // Touch moves arrive up to 120 times a second; the target cell changes
        // maybe once per tile crossed. Rescanning every building and decoration
        // on each event — and handing SceneKit a freshly built UIColor each
        // time — was costing whole milliseconds per touch.
        guard lastGhostCell?.col != col || lastGhostCell?.row != row else { return }
        lastGhostCell = (col, row)

        let valid = canPlace(offsets: dragOffsets, at: col, row: row, excluding: dragged)
        if valid != lastGhostValid {
            lastGhostValid = valid
            ghost.geometry?.firstMaterial?.diffuse.contents =
                valid ? Self.ghostOKColor : Self.ghostBadColor
        }
        let p = gridToWorld(col: col, row: row)
        ghost.position = SCNVector3(p.x + dragBounds.midX, 0.02, p.z + dragBounds.midY)
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
    let roadEntrances: [BuildingRoadEntrance]
    private(set) var nightLighting: BuildingNightLighting?

    init(type: BuildingType, gridX: Int, gridY: Int, isComplete: Bool = true,
         rotation: Int = 0, style: BuildingStyle = BuildingStyle()) {
        self.type = type
        self.gridX = gridX
        self.gridY = gridY
        self.isComplete = isComplete
        self.rotationSteps = rotation
        let variant = (abs(gridX) * 3 + abs(gridY) * 5) % 3
        self.roadEntrances = type.roadEntrances(variant: variant)
        super.init()
        let model = BuildingFactory.node(for: type, variant: variant, style: style)
        addChildNode(model)
        let fp = type.footprint
        addChildNode(contactShadowNode(radius: 0.42, cellsX: fp.w, cellsZ: fp.l))
        if isComplete {
            nightLighting = BuildingNightLighting(model: model, parent: self, footprint: fp, entrances: roadEntrances)
        }
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

/// Anything covering more than one cell gets a rounded oblong spanning its
/// whole footprint. Two translucent layers fake a soft falloff without a
/// texture, keeping the contact shadow cheap and consistent with low-poly art.
func contactShadowNode(radius: CGFloat, cellsX: Int = 1, cellsZ: Int = 1) -> SCNNode {
    let root = SCNNode()
    let width = radius * 2 + CGFloat(cellsX - 1)
    let depth = radius * 2 + CGFloat(cellsZ - 1)

    func layer(inset: CGFloat, alpha: CGFloat, y: CGFloat) -> SCNNode {
        let g = SCNPlane(width: max(0.05, width - inset * 2),
                         height: max(0.05, depth - inset * 2))
        g.cornerRadius = max(0.025, radius - inset)
        g.firstMaterial?.diffuse.contents = UIColor(red: 0.08, green: 0.12, blue: 0.07, alpha: alpha)
        g.firstMaterial?.lightingModel = .constant
        g.firstMaterial?.writesToDepthBuffer = false
        let node = SCNNode(geometry: g)
        node.eulerAngles.x = -.pi / 2
        node.position.y = Float(y)
        node.castsShadow = false
        return node
    }

    root.addChildNode(layer(inset: 0, alpha: 0.045, y: 0.0012))
    root.addChildNode(layer(inset: 0.07, alpha: 0.085, y: 0.0018))
    // Centred on the footprint, not on the anchor cell.
    root.position = SCNVector3(CGFloat(cellsX - 1) / 2, 0, CGFloat(cellsZ - 1) / 2)
    return root
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
    private(set) var streetLighting: StreetLampLighting?

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
        if type == .streetLamp { streetLighting = StreetLampLighting(parent: self) }
        if let r = Self.shadowRadius(for: type) {
            let fp = type.footprint
            addChildNode(contactShadowNode(radius: r, cellsX: fp.w, cellsZ: fp.l))
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

        let plane = SCNPlane(width: 0.27, height: 0.093)
        plane.materials = [mat]
        let n = SCNNode(geometry: plane)
        n.name = "namePlate"
        n.position = SCNVector3(0, 0.560, 0.319)  // on the gable, clear of the dog’s opening
        addChildNode(n)
    }

    /// Doghouse bowl: show or hide the kibble.
    func setBowlFilled(_ filled: Bool) {
        guard type == .doghouse else { return }
        let changed = bowlHasFood != filled
        bowlHasFood = filled
        guard let food = childNode(withName: "bowlFood", recursively: true) else { return }
        food.isHidden = !filled
        if changed || !filled { food.childNodes.forEach { $0.isHidden = false } }
    }

    /// Visual portions only. The persisted full/empty flag changes on the final bite.
    func setBowlMealProgress(_ progress: Double) {
        guard bowlHasFood, let food = childNode(withName: "bowlFood", recursively: true) else { return }
        let count = food.childNodes.count
        let eaten = Int((Double(count) * min(1, max(0, progress)) + 0.00001).rounded(.down))
        for (index, granule) in food.childNodes.enumerated() { granule.isHidden = index < eaten }
    }

    /// Where a pet should curl up inside this doghouse (world space offset from
    /// the node), plus the facing that looks out of the opening.
    var doghouseBed: (offset: SCNVector3, yaw: Float)? {
        guard type == .doghouse else { return nil }
        let yaw = eulerAngles.y
        // Rest in the doorway with the body inside and the front paws on the
        // low entrance mat. Its top is 0.031 above the map, including the deck.
        let depth: Float = 0.10
        return (SCNVector3(depth * sin(yaw), 0.031, depth * cos(yaw)), yaw)
    }

    /// Krmítko: a small bird drops in every now and then, hops, and leaves.
    func startFeederVisits() {
        guard type == .birdFeeder, !UIAccessibility.isReduceMotionEnabled else { return }
        let bird = AmbientBirdNode(kind:.sparrow,flying:false)
        bird.name = "feederBird"
        bird.scale = SCNVector3(0.55,0.55,0.55)
        bird.startPecking()
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
        case .poplar:     0.14
        case .fruitTree:  0.22
        case .bush:       0.14
        case .bench:      0.17
        case .streetLamp: 0.09
        case .fountain:   0.32
        case .doghouse:   0.28
        case .birdFeeder: 0.12
        case .firePit:    0.30
        case .pumpkins:      0.17
        case .scarecrow:     0.14
        case .christmasTree: 0.26
        case .snowman:       0.16
        case .road, .pond: nil    // flat, sit in the ground already
        }
    }
    required init?(coder: NSCoder) { nil }

    private struct RoadLayout: Equatable {
        let n: Bool, e: Bool, s: Bool, w: Bool
        let entrances: [RoadEntranceConnection]
    }
    private var roadLayout: RoadLayout?

    /// Rebuild only changed road joins or approaches; normal drags keep the mesh.
    func rebuildRoad(n: Bool, e: Bool, s: Bool, w: Bool, entrances: [RoadEntranceConnection] = []) {
        guard type == .road else { return }
        let layout = RoadLayout(n: n, e: e, s: s, w: w, entrances: entrances)
        guard roadLayout != layout else { return }
        roadLayout = layout
        childNodes.filter { $0.name != "selectionRing" }.forEach { $0.removeFromParentNode() }
        DecorationFactory.buildRoad(self, n: n, e: e, s: s, w: w, entrances: entrances)
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
        case .tent:       buildTent(root, f)
        case .cottage:    buildCottage(root, f, variant)
        case .house:      buildHouse(root, f, variant)
        case .barn:       buildBarn(root, f)
        case .farm:       buildFarm(root, f)
        case .homestead:  buildHomestead(root, f)
        case .stables:    buildStables(root, f)
        case .shop:       buildShop(root, f)
        case .flowerShop: buildFlowerShop(root, f)
        case .cafe:
            CafeBuildingModel.build(into: root,
                facade: facadeMat(.plaster, 0.93, 0.85, 0.73, f),
                roof: roofMat(0.43, 0.51, 0.48, f),
                stone: texMat(.stone, 0.70, 0.67, 0.59, f), glass: glassMat())
        case .post:       buildPost(root, f)
        case .school:     buildSchool(root, f)
        case .tower:      buildTower(root, f)
        case .tavern:     buildTavern(root, f)
        case .blacksmith: buildBlacksmith(root, f)
        case .market:     buildMarket(root, f)
        case .townhall:   buildTownhall(root, f)
        case .church:     buildChurch(root, f)
        case .fireStation:   buildFireStation(root, f)
        case .policeStation: buildPoliceStation(root, f)
        case .hospital:      buildHospital(root, f)
        case .fortress:   buildFortress(root, f)
        case .cathedral:  buildCathedral(root, f)
        case .chateau:    buildChateau(root, f)
        case .hauntedHouse:     buildHauntedHouse(root, f)
        case .gingerbreadHouse: buildGingerbreadHouse(root, f)
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
        m.name = BuildingNightLighting.windowMaterialName
        m.diffuse.contents  = UIColor(red: 0.99, green: 0.88, blue: 0.55, alpha: 1)
        m.emission.contents = UIColor(red: 0.45, green: 0.36, blue: 0.14, alpha: 1)
        m.lightingModel = .lambert
        return m
    }

    private static func glassMat() -> SCNMaterial {
        let m = SCNMaterial()
        m.name = BuildingNightLighting.windowMaterialName
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

    /// An open stone well with a working-looking windlass and a low timber canopy.
    private static func buildWell(_ r: SCNNode) {
        let stone = facadeMat(nil,0.69,0.67,0.58)
        let pale = mat(0.79,0.76,0.65)
        let shade = mat(0.61,0.61,0.54)
        let wood = texMat(.planks,0.51,0.39,0.27)
        let cutWood = mat(0.64,0.50,0.33)
        let iron = mat(0.32,0.36,0.35)
        let rope = mat(0.78,0.68,0.47)
        let roof = roofMat(0.61,0.39,0.29)
        // Individual wedge stones leave a real opening; the water sits below the rim.
        func ring(inner: CGFloat, outer: CGFloat, y: CGFloat, height: CGFloat, offset: CGFloat, coping: Bool) {
            for i in 0..<12 {
                let a = CGFloat(i) * .pi/6 + offset + 0.012
                let b = CGFloat(i+1) * .pi/6 + offset - 0.012
                let path = UIBezierPath()
                path.move(to:CGPoint(x:cos(a)*outer,y:sin(a)*outer))
                path.addLine(to:CGPoint(x:cos(b)*outer,y:sin(b)*outer))
                path.addLine(to:CGPoint(x:cos(b)*inner,y:sin(b)*inner))
                path.addLine(to:CGPoint(x:cos(a)*inner,y:sin(a)*inner)); path.close()
                let geometry = SCNShape(path:path,extrusionDepth:height)
                geometry.chamferRadius = 0.003
                geometry.materials = [coping ? pale : (i%4 == 0 ? shade : stone)]
                let node = SCNNode(geometry:geometry)
                node.eulerAngles.x = -.pi/2; node.position.y = Float(y+height/2)
                r.addChildNode(node)
            }
        }
        ring(inner:0.176,outer:0.286,y:0.018,height:0.041,offset:0,coping:false)
        ring(inner:0.184,outer:0.266,y:0.062,height:0.093,offset:.pi/12,coping:false)
        ring(inner:0.184,outer:0.266,y:0.158,height:0.093,offset:0,coping:false)
        ring(inner:0.177,outer:0.287,y:0.254,height:0.048,offset:.pi/12,coping:true)
        let water = mat(0.29,0.56,0.59)
        water.specular.contents = UIColor(white:0.6,alpha:1); water.shininess = 0.45
        cylinder(r,r:0.182,h:0.012,y:0.187,material:water)
        let ripple = SCNTorus(ringRadius:0.085,pipeRadius:0.002)
        ripple.ringSegmentCount = 24; ripple.pipeSegmentCount = 4; ripple.materials = [mat(0.52,0.71,0.69)]
        let rippleNode = SCNNode(geometry:ripple); rippleNode.position.y = 0.201; r.addChildNode(rippleNode)
        box(r,w:0.30,h:0.026,l:0.15,y:0,z:0.314,material:shade,chamfer:0.012)
        for x: CGFloat in [-0.296,0.296] {
            box(r,w:0.104,h:0.071,l:0.112,x:x,material:shade,chamfer:0.009)
            box(r,w:0.062,h:0.664,l:0.070,x:x,y:0.058,material:wood,chamfer:0.005)
            box(r,w:0.071,h:0.036,l:0.078,x:x,y:0.12,material:iron,chamfer:0.003)
            box(r,w:0.083,h:0.052,l:0.080,x:x,y:0.519,material:cutWood,chamfer:0.004)
            for side: CGFloat in [-1,1] {
                let brace = box(r,w:0.035,h:0.18,l:0.037,x:x,y:0.57,z:side*0.092,material:wood,chamfer:0.003)
                brace.eulerAngles.x = Float(side) * .pi/4
            }
        }
        let axle = SCNCylinder(radius:0.027,height:0.716); axle.radialSegmentCount = 12; axle.materials = [cutWood]
        let axleNode = SCNNode(geometry:axle); axleNode.eulerAngles.z = .pi/2; axleNode.position.y = 0.555; r.addChildNode(axleNode)
        for i in -3...3 {
            let coil = SCNTorus(ringRadius:0.030,pipeRadius:0.005); coil.ringSegmentCount = 12; coil.pipeSegmentCount = 5; coil.materials = [rope]
            let node = SCNNode(geometry:coil); node.eulerAngles.z = .pi/2; node.position = SCNVector3(Float(i)*0.011,0.555,0); r.addChildNode(node)
        }
        cylinder(r,r:0.005,h:0.40,y:0.137,z:0.032,material:rope)
        box(r,w:0.020,h:0.111,l:0.024,x:0.362,y:0.451,material:iron,chamfer:0.003)
        let handle = SCNCylinder(radius:0.014,height:0.073); handle.radialSegmentCount = 8; handle.materials = [cutWood]
        let handleNode = SCNNode(geometry:handle); handleNode.eulerAngles.z = .pi/2; handleNode.position = SCNVector3(0.389,0.456,0); r.addChildNode(handleNode)
        box(r,w:0.66,h:0.043,l:0.075,y:0.69,material:wood,chamfer:0.005)
        let canopy = SCNNode(); canopy.eulerAngles.y = .pi/2; r.addChildNode(canopy)
        roofShell(canopy,span:0.44,depth:0.67,rise:0.18,y:0.735,wall:wood,roof:roof)
        for z: CGFloat in [-0.268,0.268] {
            box(r,w:0.78,h:0.028,l:0.027,y:0.691,z:z,material:cutWood,chamfer:0.004)
        }
        // A little open stave bucket beside the approach, with dark water and an iron handle.
        let bucket = SCNNode(); bucket.position = SCNVector3(-0.33,0.018,0.267); r.addChildNode(bucket)
        let tub = SCNTube(innerRadius:0.044,outerRadius:0.055,height:0.084)
        tub.radialSegmentCount = 10; tub.materials = [wood]
        let tubNode = SCNNode(geometry:tub); tubNode.position.y = 0.042; bucket.addChildNode(tubNode)
        cylinder(bucket,r:0.043,h:0.007,y:0.055,material:water)
        for y: CGFloat in [0.017,0.072] {
            let hoop = SCNTorus(ringRadius:0.055,pipeRadius:0.004); hoop.ringSegmentCount = 10; hoop.pipeSegmentCount = 4; hoop.materials = [iron]
            let node = SCNNode(geometry:hoop); node.position.y = Float(y); bucket.addChildNode(node)
        }
        for x: CGFloat in [-0.049,0.049] { box(bucket,w:0.006,h:0.073,l:0.006,x:x,y:0.065,material:iron,chamfer:0.002) }
        box(bucket,w:0.104,h:0.008,l:0.009,y:0.135,material:iron,chamfer:0.003)
        // One modest lantern ties the well into the town's evening lighting.
        box(r,w:0.061,h:0.080,l:0.049,x:-0.294,y:0.566,z:0.065,material:glassMat(),chamfer:0.004)
        for y: CGFloat in [0.556,0.646] { box(r,w:0.079,h:0.013,l:0.065,x:-0.294,y:y,z:0.065,material:iron,chamfer:0.004) }
        for x: CGFloat in [-0.322,-0.266] { box(r,w:0.006,h:0.080,l:0.008,x:x,y:0.568,z:0.093,material:iron,chamfer:0.001) }
    }

    /// A low cottage with a real gable, readable windows and a stone doorstep.
    /// Roof panels sit above the walls; no hidden lower prism can cover the door.
    private static func buildCottage(_ r: SCNNode, _ f: CGFloat, _ v: Int) {
        let body = facadeMat(.plaster, 0.90, 0.85, 0.73, f)
        let trim = mat(0.95, 0.91, 0.81, f)
        let timber = mat(0.49, 0.40, 0.31, f)
        let shutters = mat(0.40, 0.51, 0.43, f)
        let base = texMat(.stone, 0.62, 0.62, 0.55, f)
        let roofDefaults: [(CGFloat, CGFloat, CGFloat)] = [
            (0.73, 0.40, 0.29), (0.45, 0.55, 0.40), (0.57, 0.43, 0.33)
        ]
        let rd = roofDefaults[v % roofDefaults.count]
        let roof = roofMat(rd.0, rd.1, rd.2, f)
        let mirror: CGFloat = v % 3 == 1 ? -1 : 1

        box(r, w: 0.72, h: 0.06, l: 0.60, material: base, chamfer: 0.018)
        box(r, w: 0.68, h: 0.44, l: 0.56, y: 0.06, material: body, chamfer: 0.006)

        // Plastered end walls under two thin roof slopes. Ridge runs along Z,
        // presenting the cottage's gable to the street.
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: -0.34, y: 0))
        profile.addLine(to: CGPoint(x: 0, y: 0.34))
        profile.addLine(to: CGPoint(x: 0.34, y: 0))
        profile.close()
        let gable = SCNShape(path: profile, extrusionDepth: 0.56)
        gable.materials = [body]
        let gableNode = SCNNode(geometry: gable)
        gableNode.position.y = 0.50
        r.addChildNode(gableNode)
        for side: CGFloat in [-1, 1] {
            let panel = SCNBox(width: 0.4 * 2.squareRoot(), height: 0.036,
                               length: 0.72, chamferRadius: 0.008)
            panel.materials = [roof]
            let slope = SCNNode(geometry: panel)
            slope.position = SCNVector3(side * 0.20, 0.650, 0)
            slope.eulerAngles.z = Float(-side) * .pi / 4
            r.addChildNode(slope)
        }
        box(r, w: 0.055, h: 0.035, l: 0.74, y: 0.830, material: roof, chamfer: 0.012)

        // A framed, raised entry with a single generous doorstep.
        let entryX = mirror * -0.16
        box(r, w: 0.19, h: 0.31, l: 0.026, x: entryX, y: 0.06, z: 0.287,
            material: timber, chamfer: 0.007)
        box(r, w: 0.135, h: 0.267, l: 0.022, x: entryX, y: 0.067, z: 0.304,
            material: doorMat, chamfer: 0.006)
        box(r, w: 0.24, h: 0.05, l: 0.14, x: entryX, z: 0.34, material: base, chamfer: 0.014)

        func framedWindow(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat, h: CGFloat) {
            let outward: CGFloat = z >= 0 ? 1 : -1
            window(r, x: x, y: y, z: z, w: w + 0.045, h: h + 0.045, material: timber)
            window(r, x: x, y: y, z: z + outward * 0.018, w: w, h: h)
            box(r, w: 0.012, h: h, l: 0.012, x: x, y: y - h / 2,
                z: z + outward * 0.039, material: trim, chamfer: 0.002)
        }
        let windowX = mirror * 0.15
        framedWindow(x: windowX, y: 0.29, z: 0.287, w: 0.14, h: 0.15)
        for side: CGFloat in [-1, 1] {
            box(r, w: 0.035, h: 0.18, l: 0.025, x: windowX + side * 0.112,
                y: 0.20, z: 0.297, material: shutters, chamfer: 0.005)
        }
        framedWindow(x: 0, y: 0.635, z: 0.287, w: 0.075, h: 0.095)
        framedWindow(x: 0.12, y: 0.29, z: -0.287, w: 0.14, h: 0.15)

        // Windows on both side walls keep rotated cottages equally legible.
        for side: CGFloat in [-1, 1] {
            window(r, x: side * 0.347, y: 0.29, z: -0.03, w: 0.19, h: 0.195,
                   onXFace: true, material: timber)
            window(r, x: side * 0.365, y: 0.29, z: -0.03, w: 0.145, h: 0.15, onXFace: true)
            box(r, w: 0.012, h: 0.15, l: 0.012, x: side * 0.384, y: 0.215, z: -0.03,
                material: trim, chamfer: 0.002)
        }

        // A planted sill gives the little house one warm, domestic detail.
        box(r, w: 0.21, h: 0.045, l: 0.075, x: windowX, y: 0.12, z: 0.315,
            material: timber, chamfer: 0.01)
        box(r, w: 0.185, h: 0.04, l: 0.07, x: windowX, y: 0.163, z: 0.322,
            material: mat(0.40, 0.58, 0.35, f), chamfer: 0.018)
        for dx: CGFloat in [-0.045, 0.045] {
            let flower = SCNSphere(radius: 0.019)
            flower.segmentCount = 6
            flower.materials = [mat(0.91, 0.76, 0.53)]
            let bloom = SCNNode(geometry: flower)
            bloom.position = SCNVector3(windowX + dx, 0.207, 0.33)
            r.addChildNode(bloom)
        }

        let chimneyX = mirror * -0.21
        box(r, w: 0.115, h: 0.38, l: 0.13, x: chimneyX, y: 0.61, z: -0.12,
            material: base, chamfer: 0.01)
        box(r, w: 0.155, h: 0.04, l: 0.17, x: chimneyX, y: 0.99, z: -0.12,
            material: stoneMat, chamfer: 0.009)
        smoke(r, x: chimneyX, y: 1.045, z: -0.12)
    }

    /// A two-storey family home with a broad roof, bay window and timber balcony.
    /// The sideways ridge and layered facade distinguish it from the low cottage.
    private static func buildHouse(_ r: SCNNode, _ f: CGFloat, _ v: Int) {
        let body = facadeMat(.plaster, 0.91, 0.86, 0.75, f)
        let trim = mat(0.96, 0.92, 0.83, f)
        let timber = mat(0.49, 0.40, 0.31, f)
        let shutters = mat(0.43, 0.54, 0.47, f)
        let base = texMat(.stone, 0.64, 0.63, 0.56, f)
        let glass = glassMat()
        let roofDefaults: [(CGFloat, CGFloat, CGFloat)] = [
            (0.67, 0.38, 0.29), (0.38, 0.47, 0.59), (0.45, 0.55, 0.41),
        ]
        let rd = roofDefaults[v % roofDefaults.count]
        let roof = roofMat(rd.0, rd.1, rd.2, f)
        let mirror: CGFloat = v % 3 == 1 ? -1 : 1

        box(r, w: 0.76, h: 0.065, l: 0.62, material: base, chamfer: 0.016)
        box(r, w: 0.72, h: 0.76, l: 0.58, y: 0.065, material: body, chamfer: 0.006)
        box(r, w: 0.744, h: 0.032, l: 0.604, y: 0.446, material: trim, chamfer: 0.005)
        box(r, w: 0.76, h: 0.028, l: 0.62, y: 0.797, material: trim, chamfer: 0.005)

        // Closed plaster gables and thin roof panels, with no roof prism
        // extending down through the upper windows. The ridge runs along X.
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: -0.29, y: 0))
        profile.addLine(to: CGPoint(x: 0, y: 0.2465))
        profile.addLine(to: CGPoint(x: 0.29, y: 0))
        profile.close()
        let gable = SCNShape(path: profile, extrusionDepth: 0.72)
        gable.materials = [body]
        let ends = SCNNode(geometry: gable)
        ends.position.y = 0.825
        ends.eulerAngles.y = .pi / 2
        r.addChildNode(ends)
        for side: CGFloat in [-1, 1] {
            let panel = SCNBox(width: 0.86, height: 0.034,
                               length: sqrt(0.36 * 0.36 + 0.306 * 0.306), chamferRadius: 0.006)
            panel.materials = [roof]
            let slope = SCNNode(geometry: panel)
            slope.position = SCNVector3(0, 0.9335, side * 0.18)
            slope.eulerAngles.x = Float(side * atan(0.85))
            r.addChildNode(slope)
        }
        box(r, w: 0.88, h: 0.032, l: 0.047, y: 1.072, material: roof, chamfer: 0.01)

        // Local +Z facade details can be reused on all four walls.
        func framedWindow(on face: SCNNode, x: CGFloat, y: CGFloat,
                          w: CGFloat = 0.13, h: CGFloat = 0.18, withShutters: Bool = false) {
            window(face, x: x, y: y, z: 0.009, w: w + 0.044, h: h + 0.044, material: timber)
            window(face, x: x, y: y, z: 0.027, w: w, h: h, material: glass)
            box(face, w: 0.012, h: h, l: 0.012, x: x, y: y - h / 2, z: 0.046,
                material: trim, chamfer: 0.002)
            box(face, w: w + 0.064, h: 0.022, l: 0.06, x: x, y: y - h / 2 - 0.035,
                z: 0.02, material: trim, chamfer: 0.004)
            if withShutters {
                for side: CGFloat in [-1, 1] {
                    box(face, w: 0.033, h: h + 0.03, l: 0.024,
                        x: x + side * (w / 2 + 0.045), y: y - h / 2 - 0.015,
                        z: 0.015, material: shutters, chamfer: 0.004)
                }
            }
        }
        let front = SCNNode()
        front.position.z = 0.29
        r.addChildNode(front)
        let entryX = mirror * -0.175
        let bayX = mirror * 0.165
        box(front, w: 0.185, h: 0.30, l: 0.028, x: entryX, y: 0.065, z: 0.013,
            material: timber, chamfer: 0.007)
        box(front, w: 0.137, h: 0.257, l: 0.022, x: entryX, y: 0.073, z: 0.033,
            material: doorMat, chamfer: 0.005)
        box(front, w: 0.071, h: 0.065, l: 0.012, x: entryX, y: 0.239, z: 0.05,
            material: glass, chamfer: 0.004)
        box(r, w: 0.245, h: 0.05, l: 0.155, x: entryX, z: 0.357,
            material: base, chamfer: 0.012)
        let porch = box(r, w: 0.265, h: 0.027, l: 0.18, x: entryX, y: 0.388, z: 0.346,
                        material: roof, chamfer: 0.005)
        porch.eulerAngles.x = 0.22
        for side: CGFloat in [-1, 1] {
            box(r, w: 0.022, h: 0.063, l: 0.063, x: entryX + side * 0.096,
                y: 0.328, z: 0.316, material: timber, chamfer: 0.004)
        }

        // A shallow bay supports the balcony, keeping its silhouette compact.
        box(r, w: 0.265, h: 0.275, l: 0.11, x: bayX, y: 0.115, z: 0.319,
            material: trim, chamfer: 0.008)
        let bay = SCNNode()
        bay.position = SCNVector3(bayX, 0, 0.375)
        r.addChildNode(bay)
        framedWindow(on: bay, x: 0, y: 0.267, w: 0.183, h: 0.163)
        box(r, w: 0.303, h: 0.03, l: 0.16, x: bayX, y: 0.392, z: 0.33,
            material: roof, chamfer: 0.007)
        framedWindow(on: front, x: entryX, y: 0.636, withShutters: true)
        framedWindow(on: front, x: bayX, y: 0.626, w: 0.133, h: 0.232)
        box(r, w: 0.31, h: 0.032, l: 0.15, x: bayX, y: 0.482, z: 0.346,
            material: timber, chamfer: 0.006)
        for dx: CGFloat in [-0.137, -0.046, 0.046, 0.137] {
            box(r, w: 0.018, h: 0.104, l: 0.018, x: bayX + dx, y: 0.514, z: 0.409,
                material: timber, chamfer: 0.003)
        }
        box(r, w: 0.315, h: 0.022, l: 0.027, x: bayX, y: 0.611, z: 0.409,
            material: timber, chamfer: 0.004)
        for side: CGFloat in [-1, 1] {
            box(r, w: 0.023, h: 0.022, l: 0.125, x: bayX + side * 0.14,
                y: 0.611, z: 0.349, material: timber, chamfer: 0.003)
        }

        for side: CGFloat in [-1, 1] {
            let wall = SCNNode()
            wall.position.x = Float(side * 0.36)
            wall.eulerAngles.y = Float(side) * .pi / 2
            r.addChildNode(wall)
            for y: CGFloat in [0.27, 0.636] {
                framedWindow(on: wall, x: 0, y: y, w: 0.16, withShutters: true)
            }
            framedWindow(on: wall, x: 0, y: 0.903, w: 0.065, h: 0.078)
        }
        let rear = SCNNode()
        rear.position.z = -0.29
        rear.eulerAngles.y = .pi
        r.addChildNode(rear)
        for x: CGFloat in [-0.175, 0.175] {
            for y: CGFloat in [0.27, 0.636] {
                framedWindow(on: rear, x: x, y: y, withShutters: y > 0.5)
            }
        }

        // A small planted balcony box adds warmth without covering the railing.
        box(r, w: 0.16, h: 0.04, l: 0.06, x: bayX, y: 0.557, z: 0.43,
            material: timber, chamfer: 0.006)
        box(r, w: 0.145, h: 0.032, l: 0.053, x: bayX, y: 0.595, z: 0.431,
            material: mat(0.40, 0.56, 0.35, f), chamfer: 0.015)
        for dx: CGFloat in [-0.04, 0.035] {
            let flower = SCNSphere(radius: 0.015)
            flower.segmentCount = 6
            flower.materials = [mat(0.91, 0.71, 0.49)]
            let bloom = SCNNode(geometry: flower)
            bloom.position = SCNVector3(bayX + dx, 0.633, 0.437)
            r.addChildNode(bloom)
        }
        let chimneyX = mirror * -0.235
        box(r, w: 0.11, h: 0.29, l: 0.12, x: chimneyX, y: 0.936, z: -0.12,
            material: base, chamfer: 0.007)
        box(r, w: 0.15, h: 0.037, l: 0.16, x: chimneyX, y: 1.226, z: -0.12,
            material: stoneMat, chamfer: 0.008)
        smoke(r, x: chimneyX, y: 1.276, z: -0.12)
    }

    /// A boarded barn with a real two-pitch roof, split doors and a working hayloft.
    private static func buildBarn(_ r: SCNNode, _ f: CGFloat) {
        let planks = facadeMat(.planks, 0.69, 0.38, 0.30, f)
        let trim = mat(0.93, 0.88, 0.75, f)
        let wood = mat(0.46, 0.34, 0.24, f)
        let doorWood = texMat(.planks, 0.53, 0.29, 0.23, f)
        let base = texMat(.stone, 0.64, 0.61, 0.53, f)
        let roof = roofMat(0.43, 0.39, 0.34, f)
        let dark = mat(0.27, 0.25, 0.21)
        let windowGlass = mat(0.27, 0.25, 0.21)
        windowGlass.name = BuildingNightLighting.windowMaterialName
        let hay = mat(0.83, 0.71, 0.43, f)
        box(r, w: 0.80, h: 0.065, l: 0.66, material: base, chamfer: 0.014)
        box(r, w: 0.76, h: 0.40, l: 0.62, y: 0.065, material: planks, chamfer: 0.005)
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: -0.38, y: 0))
        profile.addLine(to: CGPoint(x: -0.285, y: 0.25))
        profile.addLine(to: CGPoint(x: 0, y: 0.43))
        profile.addLine(to: CGPoint(x: 0.285, y: 0.25))
        profile.addLine(to: CGPoint(x: 0.38, y: 0))
        profile.close()
        let gable = SCNShape(path: profile, extrusionDepth: 0.62)
        gable.materials = [planks]
        let ends = SCNNode(geometry: gable)
        ends.position.y = 0.465
        r.addChildNode(ends)
        // Four thin slopes follow the wall profile; roof color never paints the gables.
        for side: CGFloat in [-1, 1] {
            let points: [(CGFloat, CGFloat)] = [(0, 0.911), (side * 0.285, 0.731), (side * 0.408, 0.407)]
            for i in 0..<2 {
                let a = points[i], b = points[i + 1]
                let dx = b.0 - a.0, dy = b.1 - a.1
                let panel = SCNBox(width: sqrt(dx * dx + dy * dy), height: 0.03, length: 0.74, chamferRadius: 0.004)
                panel.materials = [roof]
                let node = SCNNode(geometry: panel)
                node.position = SCNVector3((a.0 + b.0) / 2, (a.1 + b.1) / 2, 0)
                node.eulerAngles.z = Float(atan2(dy, dx))
                r.addChildNode(node)
            }
        }
        box(r, w: 0.046, h: 0.029, l: 0.756, y: 0.9, material: roof, chamfer: 0.008)
        for face: CGFloat in [-1, 1] {
            for x: CGFloat in [-0.357, 0.357] {
                box(r, w: 0.03, h: 0.397, l: 0.027, x: x, y: 0.068, z: face * 0.317, material: trim, chamfer: 0.003)
            }
            box(r, w: 0.715, h: 0.027, l: 0.025, y: 0.438, z: face * 0.318, material: trim, chamfer: 0.003)
            box(r, w: 0.48, h: 0.372, l: 0.026, y: 0.065, z: face * 0.321, material: trim, chamfer: 0.005)
            box(r, w: 0.434, h: 0.33, l: 0.024, y: 0.073, z: face * 0.339, material: dark, chamfer: 0.003)
            for side: CGFloat in [-1, 1] {
                let x = side * 0.109
                box(r, w: 0.206, h: 0.314, l: 0.022, x: x, y: 0.078, z: face * 0.355, material: doorWood, chamfer: 0.003)
                for y: CGFloat in [0.09, 0.365] {
                    box(r, w: 0.198, h: 0.017, l: 0.012, x: x, y: y, z: face * 0.373, material: trim, chamfer: 0.002)
                }
                for slope: CGFloat in [-1, 1] {
                    let brace = box(r, w: sqrt(0.184 * 0.184 + 0.247 * 0.247), h: 0.016, l: 0.012,
                                    x: x, y: 0.224, z: face * 0.373, material: trim, chamfer: 0.002)
                    brace.eulerAngles.z = Float(slope * atan2(0.247, 0.184))
                }
            }
            box(r, w: 0.019, h: 0.326, l: 0.013, y: 0.075, z: face * 0.375, material: trim, chamfer: 0.002)
            box(r, w: 0.216, h: 0.188, l: 0.025, y: 0.544, z: face * 0.322, material: trim, chamfer: 0.004)
            box(r, w: 0.167, h: 0.143, l: 0.021, y: 0.556, z: face * 0.342, material: dark, chamfer: 0.003)
        }
        box(r, w: 0.50, h: 0.038, l: 0.11, z: 0.366, material: base, chamfer: 0.01)
        box(r, w: 0.135, h: 0.047, l: 0.04, y: 0.557, z: 0.358, material: hay, chamfer: 0.006)
        // Small shutters sit beside the open loft, leaving the opening readable.
        for side: CGFloat in [-1, 1] {
            let shutter = box(r, w: 0.069, h: 0.145, l: 0.018, x: side * 0.144, y: 0.555, z: 0.343, material: doorWood, chamfer: 0.003)
            shutter.eulerAngles.y = Float(side * 0.28)
        }
        box(r, w: 0.03, h: 0.027, l: 0.16, y: 0.782, z: 0.354, material: wood, chamfer: 0.003)
        cylinder(r, r: 0.005, h: 0.113, y: 0.673, z: 0.416, material: wood)
        for side: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.x = side * 0.38
            wall.eulerAngles.y = side * .pi / 2
            r.addChildNode(wall)
            for x: CGFloat in [-0.15, 0.15] {
                shopPane(wall, x: x, y: 0.277, w: 0.09, h: 0.11, frame: trim, sill: trim, glass: windowGlass)
            }
        }
        box(r, w: 0.10, h: 0.075, l: 0.10, x: 0.321, y: 0.012, z: 0.381, material: hay, chamfer: 0.009)
        box(r, w: 0.014, h: 0.077, l: 0.104, x: 0.321, y: 0.012, z: 0.381, material: trim, chamfer: 0.002)
    }

    /// A low village grocery: broad glazing, a shallow hip roof and produce crates.
    private static func buildShop(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.90, 0.84, 0.71, f)
        let trim = mat(0.96, 0.92, 0.82, f)
        let teal = mat(0.34, 0.53, 0.47, f)
        let wood = mat(0.51, 0.40, 0.29, f)
        let stone = texMat(.stone, 0.64, 0.62, 0.55, f)
        let roof = roofMat(0.40, 0.47, 0.43, f)
        let glass = glassMat()
        box(r, w: 0.76, h: 0.055, l: 0.60, material: stone, chamfer: 0.015)
        box(r, w: 0.72, h: 0.545, l: 0.56, y: 0.055, material: body, chamfer: 0.006)
        box(r, w: 0.755, h: 0.032, l: 0.595, y: 0.574, material: trim, chamfer: 0.006)
        box(r, w: 0.79, h: 0.027, l: 0.63, y: 0.606, material: roof, chamfer: 0.008)
        pyramidRoof(r, w: 0.79, h: 0.145, l: 0.63, y: 0.633, material: roof)
        for x: CGFloat in [-0.34, 0.34] {
            box(r, w: 0.027, h: 0.49, l: 0.024, x: x, y: 0.075, z: 0.287, material: trim, chamfer: 0.003)
        }
        let front = SCNNode()
        front.position.z = 0.28
        r.addChildNode(front)
        shopPane(front, x: 0.115, y: 0.27, w: 0.295, h: 0.255, frame: teal, sill: trim, glass: glass)
        box(front, w: 0.172, h: 0.34, l: 0.029, x: -0.225, y: 0.055, z: 0.01, material: wood, chamfer: 0.006)
        box(front, w: 0.126, h: 0.295, l: 0.023, x: -0.225, y: 0.063, z: 0.031, material: teal, chamfer: 0.005)
        box(front, w: 0.084, h: 0.15, l: 0.012, x: -0.225, y: 0.174, z: 0.049, material: glass, chamfer: 0.003)
        box(r, w: 0.215, h: 0.043, l: 0.14, x: -0.225, z: 0.34, material: stone, chamfer: 0.012)
        let awning = SCNNode()
        awning.position = SCNVector3(0, 0.455, 0.345)
        awning.eulerAngles.x = 0.20
        r.addChildNode(awning)
        for i in 0..<5 {
            let color = i % 2 == 0 ? teal : trim
            let x = CGFloat(i - 2) * 0.138
            box(awning, w: 0.138, h: 0.022, l: 0.18, x: x, y: -0.011, material: color, chamfer: 0.004)
            box(awning, w: 0.138, h: 0.035, l: 0.014, x: x, y: -0.037, z: 0.088, material: color, chamfer: 0.004)
        }
        // A bag emblem carries the shop identity without tiny lettering.
        box(front, w: 0.18, h: 0.116, l: 0.024, y: 0.482, z: 0.01, material: teal, chamfer: 0.009)
        box(front, w: 0.068, h: 0.063, l: 0.012, y: 0.499, z: 0.03, material: trim, chamfer: 0.005)
        for x: CGFloat in [-0.019, 0.019] {
            box(front, w: 0.009, h: 0.027, l: 0.009, x: x, y: 0.555, z: 0.031, material: trim, chamfer: 0.003)
        }
        box(front, w: 0.045, h: 0.009, l: 0.009, y: 0.576, z: 0.031, material: trim, chamfer: 0.003)
        for side: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.x = side * 0.36
            wall.eulerAngles.y = side * .pi / 2
            r.addChildNode(wall)
            shopPane(wall, x: 0, y: 0.285, w: 0.23, h: 0.23, frame: teal, sill: trim, glass: glass)
        }
        let rear = SCNNode()
        rear.position.z = -0.28
        rear.eulerAngles.y = .pi
        r.addChildNode(rear)
        for x: CGFloat in [-0.17, 0.17] {
            shopPane(rear, x: x, y: 0.285, w: 0.13, h: 0.19, frame: teal, sill: trim, glass: glass)
        }
        let produce = [mat(0.76, 0.40, 0.29, f), mat(0.63, 0.68, 0.36, f)]
        for (i, x) in [CGFloat(0.025), 0.217].enumerated() {
            box(r, w: 0.16, h: 0.085, l: 0.11, x: x, y: 0.009, z: 0.396, material: wood, chamfer: 0.005)
            box(r, w: 0.138, h: 0.008, l: 0.089, x: x, y: 0.085, z: 0.396,
                material: mat(0.35, 0.29, 0.23), chamfer: 0.002)
            for y: CGFloat in [0.025, 0.066] {
                box(r, w: 0.165, h: 0.012, l: 0.114, x: x, y: y, z: 0.396, material: trim, chamfer: 0.002)
            }
            for (dx, dz) in [(-0.035, -0.02), (0.035, -0.02), (0.0, 0.027)] {
                let fruit = SCNSphere(radius: 0.026)
                fruit.segmentCount = 8
                fruit.materials = [produce[i]]
                let n = SCNNode(geometry: fruit)
                n.position = SCNVector3(x + CGFloat(dx), 0.107, 0.396 + CGFloat(dz))
                r.addChildNode(n)
            }
        }
    }

    /// A closed gable with thin overhanging slopes; local ridge runs along Z.
    private static func roofShell(_ parent: SCNNode, span: CGFloat, depth: CGFloat,
                                  rise: CGFloat, y: CGFloat, wall: SCNMaterial, roof: SCNMaterial) {
        let half = span / 2
        let pitch = rise / half
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: -half, y: 0))
        profile.addLine(to: CGPoint(x: 0, y: rise))
        profile.addLine(to: CGPoint(x: half, y: 0))
        profile.close()
        let shape = SCNShape(path: profile, extrusionDepth: depth)
        shape.materials = [wall]
        let end = SCNNode(geometry: shape)
        end.position.y = Float(y)
        parent.addChildNode(end)
        let reach = half + 0.045
        for side: CGFloat in [-1, 1] {
            let panel = SCNBox(width: reach * sqrt(1 + pitch * pitch), height: 0.03,
                               length: depth + 0.10, chamferRadius: 0.005)
            panel.materials = [roof]
            let slope = SCNNode(geometry: panel)
            slope.position = SCNVector3(side * reach / 2, y + rise - reach * pitch / 2 + 0.014, 0)
            slope.eulerAngles.z = Float(-side * atan(pitch))
            parent.addChildNode(slope)
        }
        box(parent, w: 0.045, h: 0.03, l: depth + 0.115, y: y + rise,
            material: roof, chamfer: 0.008)
    }

    /// Two cells: a warm farmhouse and an orderly kitchen garden beside it.
    private static func buildFarm(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.89, 0.81, 0.64, f)
        let trim = mat(0.95, 0.91, 0.80, f)
        let wood = mat(0.51, 0.40, 0.29, f)
        let sage = mat(0.43, 0.54, 0.41, f)
        let stone = texMat(.stone, 0.64, 0.62, 0.54, f)
        let roof = roofMat(0.46, 0.55, 0.41, f)
        box(r, w: 0.73, h: 0.055, l: 0.62, material: stone, chamfer: 0.014)
        box(r, w: 0.68, h: 0.435, l: 0.57, y: 0.055, material: body, chamfer: 0.006)
        roofShell(r, span: 0.68, depth: 0.57, rise: 0.30, y: 0.49, wall: body, roof: roof)
        // A quiet timber frame and a wide painted, split farm door.
        for x: CGFloat in [-0.315, 0.315] {
            box(r, w: 0.032, h: 0.435, l: 0.027, x: x, y: 0.055, z: 0.29, material: wood, chamfer: 0.003)
        }
        box(r, w: 0.65, h: 0.03, l: 0.026, y: 0.455, z: 0.294, material: wood, chamfer: 0.003)
        box(r, w: 0.235, h: 0.33, l: 0.03, x: -0.15, y: 0.055, z: 0.294, material: wood, chamfer: 0.005)
        box(r, w: 0.186, h: 0.287, l: 0.023, x: -0.15, y: 0.062, z: 0.315, material: sage, chamfer: 0.004)
        box(r, w: 0.18, h: 0.014, l: 0.012, x: -0.15, y: 0.20, z: 0.331, material: trim, chamfer: 0.002)
        box(r, w: 0.27, h: 0.045, l: 0.14, x: -0.15, z: 0.337, material: stone, chamfer: 0.01)
        func farmWindow(_ parent: SCNNode, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
            window(parent, x: x, y: y, z: 0.008, w: w + 0.045, h: h + 0.045, material: wood)
            window(parent, x: x, y: y, z: 0.026, w: w, h: h, material: glassMat())
            box(parent, w: 0.012, h: h, l: 0.012, x: x, y: y - h / 2, z: 0.045, material: trim, chamfer: 0.002)
            box(parent, w: w + 0.07, h: 0.025, l: 0.065, x: x, y: y - h / 2 - 0.035, z: 0.025, material: trim, chamfer: 0.004)
        }
        let front = SCNNode()
        front.position.z = 0.285
        r.addChildNode(front)
        farmWindow(front, x: 0.16, y: 0.285, w: 0.12, h: 0.155)
        for x: CGFloat in [0.057, 0.263] {
            box(front, w: 0.03, h: 0.18, l: 0.025, x: x, y: 0.195, z: 0.013, material: sage, chamfer: 0.004)
        }
        farmWindow(front, x: 0, y: 0.609, w: 0.075, h: 0.085)
        for side: CGFloat in [-1, 1] {
            let wall = SCNNode()
            wall.position.x = Float(side * 0.34)
            wall.eulerAngles.y = Float(side) * .pi / 2
            r.addChildNode(wall)
            farmWindow(wall, x: -0.035, y: 0.275, w: 0.15, h: 0.16)
        }
        let rear = SCNNode()
        rear.position.z = -0.285
        rear.eulerAngles.y = .pi
        r.addChildNode(rear)
        farmWindow(rear, x: 0.11, y: 0.275, w: 0.15, h: 0.16)
        box(r, w: 0.11, h: 0.28, l: 0.12, x: -0.21, y: 0.585, z: -0.12, material: stone, chamfer: 0.007)
        box(r, w: 0.15, h: 0.035, l: 0.16, x: -0.21, y: 0.865, z: -0.12, material: stoneMat, chamfer: 0.008)
        smoke(r, x: -0.21, y: 0.915, z: -0.12)

        // A harvest crate sits beside the entrance, below the window.
        box(r, w: 0.18, h: 0.085, l: 0.12, x: 0.18, y: 0.008, z: 0.37, material: wood, chamfer: 0.006)
        for y: CGFloat in [0.025, 0.066] {
            box(r, w: 0.185, h: 0.012, l: 0.126, x: 0.18, y: y, z: 0.37, material: trim, chamfer: 0.002)
        }
        for x: CGFloat in [0.13, 0.22] {
            let g = SCNSphere(radius: 0.034)
            g.segmentCount = 6
            g.materials = [mat(0.81, 0.56, 0.26, f)]
            let crop = SCNNode(geometry: g)
            crop.position = SCNVector3(x, 0.099, 0.37)
            r.addChildNode(crop)
        }

        let field = SCNNode()
        field.position.x = 1
        r.addChildNode(field)
        box(field, w: 0.83, h: 0.028, l: 0.82, material: mat(0.53, 0.43, 0.31, f), chamfer: 0.025)
        let greens = [mat(0.43, 0.59, 0.34, f), mat(0.58, 0.67, 0.38, f)]
        for row in 0..<4 {
            let z = CGFloat(row) * 0.19 - 0.285
            box(field, w: 0.72, h: 0.027, l: 0.11, y: 0.026, z: z,
                material: mat(0.43, 0.34, 0.24, f), chamfer: 0.016)
            for col in 0..<5 {
                let x = CGFloat(col) * 0.145 - 0.29
                let foliage = SCNSphere(radius: 0.053)
                foliage.segmentCount = 6
                foliage.materials = [greens[row % 2]]
                let plant = SCNNode(geometry: foliage)
                plant.position = SCNVector3(x, 0.077, z)
                plant.scale = SCNVector3(1, 0.72, 0.85)
                field.addChildNode(plant)
                if row == 1 || row == 3 {
                    let pumpkin = SCNSphere(radius: 0.036)
                    pumpkin.segmentCount = 8
                    pumpkin.materials = [mat(0.84, 0.53, 0.24, f)]
                    let fruit = SCNNode(geometry: pumpkin)
                    fruit.position = SCNVector3(x + 0.018, 0.077, z + 0.033)
                    fruit.scale.y = 0.78
                    field.addChildNode(fruit)
                }
            }
        }
        // Open toward the farmhouse; the other three edges have two low rails.
        for side: CGFloat in [-1, 1] {
            for x: CGFloat in [-0.43, 0, 0.43] {
                box(field, w: 0.03, h: 0.17, l: 0.03, x: x, z: side * 0.435, material: wood, chamfer: 0.004)
            }
            for y: CGFloat in [0.058, 0.119] {
                box(field, w: 0.87, h: 0.02, l: 0.02, y: y, z: side * 0.435, material: wood, chamfer: 0.003)
            }
        }
        box(field, w: 0.03, h: 0.17, l: 0.03, x: 0.435, material: wood, chamfer: 0.004)
        for y: CGFloat in [0.058, 0.119] {
            box(field, w: 0.02, h: 0.02, l: 0.87, x: 0.435, y: y, material: wood, chamfer: 0.003)
        }
    }

    /// Two-cell stables: a deeper barn faces a separate, spacious horse paddock.
    private static func buildStables(_ r: SCNNode, _ f: CGFloat) {
        let boards = facadeMat(.planks, 0.62, 0.48, 0.33, f)
        let trim = mat(0.91, 0.85, 0.70, f)
        let wood = mat(0.48, 0.37, 0.27, f)
        let stone = texMat(.stone, 0.63, 0.61, 0.53, f)
        let roof = roofMat(0.39, 0.47, 0.51, f)
        let stable = SCNNode()
        stable.eulerAngles.y = .pi / 2
        stable.scale.y = 1.15
        r.addChildNode(stable)
        box(stable, w: 0.85, h: 0.045, l: 0.625, material: stone, chamfer: 0.01)
        box(stable, w: 0.81, h: 0.365, l: 0.58, y: 0.045, material: boards, chamfer: 0.005)
        let roofRoot = SCNNode()
        roofRoot.eulerAngles.y = .pi / 2
        stable.addChildNode(roofRoot)
        roofShell(roofRoot, span: 0.58, depth: 0.81, rise: 0.25, y: 0.41, wall: boards, roof: roof)
        for x: CGFloat in [-0.385, 0, 0.385] {
            box(stable, w: 0.032, h: 0.37, l: 0.025, x: x, y: 0.045, z: 0.296, material: trim, chamfer: 0.003)
        }
        box(stable, w: 0.81, h: 0.032, l: 0.026, y: 0.365, z: 0.298, material: trim, chamfer: 0.003)
        for x: CGFloat in [-0.20, 0.20] {
            box(stable, w: 0.26, h: 0.298, l: 0.026, x: x, y: 0.048, z: 0.299, material: trim, chamfer: 0.004)
            box(stable, w: 0.214, h: 0.255, l: 0.019, x: x, y: 0.057, z: 0.32,
                material: mat(0.26, 0.24, 0.20), chamfer: 0.003)
            box(stable, w: 0.21, h: 0.147, l: 0.024, x: x, y: 0.06, z: 0.333, material: wood, chamfer: 0.003)
            box(stable, w: 0.225, h: 0.019, l: 0.035, x: x, y: 0.20, z: 0.34, material: trim, chamfer: 0.003)
            for side: CGFloat in [-1, 1] {
                let brace = box(stable, w: 0.222, h: 0.016, l: 0.012, x: x, y: 0.126, z: 0.353, material: trim, chamfer: 0.002)
                brace.eulerAngles.z = Float(side * 0.51)
            }
        }
        for side: CGFloat in [-1, 1] {
            window(stable, x: side * 0.411, y: 0.25, z: 0, w: 0.15, h: 0.15, onXFace: true, material: trim)
            window(stable, x: side * 0.429, y: 0.25, z: 0, w: 0.106, h: 0.107, onXFace: true, material: glassMat())
        }
        for x: CGFloat in [-0.23, 0.23] {
            window(stable, x: x, y: 0.25, z: -0.30, w: 0.15, h: 0.15, material: trim)
            window(stable, x: x, y: 0.25, z: -0.318, w: 0.106, h: 0.107, material: glassMat())
        }
        // A little vent breaks the roof silhouette without making another tower.
        box(stable, w: 0.12, h: 0.085, l: 0.10, y: 0.645, material: wood, chamfer: 0.004)
        for y: CGFloat in [0.668, 0.697] {
            box(stable, w: 0.126, h: 0.011, l: 0.107, y: y, material: trim, chamfer: 0.002)
        }
        pyramidRoof(stable, w: 0.175, h: 0.065, l: 0.15, y: 0.73, material: roof)

        // The second cell is a full paddock, open toward the two stall doors.
        let paddock = SCNNode()
        paddock.position.x = 1
        r.addChildNode(paddock)
        box(paddock, w: 1.08, h: 0.016, l: 0.85, x: -0.10, y: 0.002,
            material: mat(0.71, 0.66, 0.50, f), chamfer: 0.04)
        for side: CGFloat in [-1, 1] {
            for x: CGFloat in [-0.56, -0.06, 0.43] {
                box(paddock, w: 0.034, h: 0.19, l: 0.034, x: x, z: side * 0.435,
                    material: wood, chamfer: 0.004)
            }
            for y: CGFloat in [0.062, 0.14] {
                if side < 0 {
                    box(paddock, w: 1.0, h: 0.023, l: 0.023, x: -0.065, y: y, z: side * 0.435,
                        material: trim, chamfer: 0.004)
                } else {
                    for (x, width) in [(CGFloat(-0.516), CGFloat(0.10)), (CGFloat(0.125), CGFloat(0.61))] {
                        box(paddock, w: width, h: 0.023, l: 0.023, x: x, y: y, z: 0.435,
                            material: trim, chamfer: 0.004)
                    }
                }
            }
        }
        for x: CGFloat in [-0.46, -0.18] {
            box(paddock, w: 0.034, h: 0.19, l: 0.034, x: x, z: 0.435, material: wood, chamfer: 0.004)
        }
        box(paddock, w: 0.034, h: 0.19, l: 0.034, x: 0.43, material: wood, chamfer: 0.004)
        for y: CGFloat in [0.062, 0.14] {
            box(paddock, w: 0.023, h: 0.023, l: 0.87, x: 0.43, y: y, material: trim, chamfer: 0.004)
        }
        box(paddock, w: 0.16, h: 0.10, l: 0.29, x: 0.285, y: 0.019, z: -0.215,
            material: stone, chamfer: 0.018)
        box(paddock, w: 0.113, h: 0.008, l: 0.239, x: 0.285, y: 0.115, z: -0.215,
            material: mat(0.42, 0.64, 0.68), chamfer: 0.009)
        box(paddock, w: 0.18, h: 0.10, l: 0.14, x: -0.40, y: 0.018, z: -0.27,
            material: mat(0.77, 0.65, 0.37, f), chamfer: 0.015)

        // A wrapper scales the normalized shop model and its ground offset together.
        // No wandering behaviour: this horse belongs inside the decorative paddock.
        let resident = SCNNode()
        resident.name = "stableHorse"
        resident.position = SCNVector3(-0.07, 0.020, 0.09)
        resident.eulerAngles.y = .pi / 2
        resident.scale = SCNVector3(0.72, 0.72, 0.72)
        paddock.addChildNode(resident)
        AnimalModelLoader.loadRig(.horse) { [weak resident] visual, clips in
            guard let resident else { return }
            resident.addChildNode(visual)
            AnimalNode.disableShadows(visual)
            resident.addChildNode(contactShadowNode(radius: 0.24))
            if !UIAccessibility.isReduceMotionEnabled { clips["idle"]?.play() }
        }
    }

    /// Framed glazing on a facade node whose local +Z points out from the wall.
    private static func shopPane(_ wall: SCNNode, x: CGFloat, y: CGFloat,
                                 w: CGFloat, h: CGFloat, frame: SCNMaterial, sill: SCNMaterial,
                                 glass: SCNMaterial) {
        window(wall, x: x, y: y, z: 0.009, w: w + 0.045, h: h + 0.045, material: frame)
        window(wall, x: x, y: y, z: 0.028, w: w, h: h, material: glass)
        box(wall, w: 0.012, h: h, l: 0.012, x: x, y: y - h / 2, z: 0.046, material: sill, chamfer: 0.002)
        box(wall, w: w + 0.066, h: 0.022, l: 0.06, x: x, y: y - h / 2 - 0.034,
            z: 0.023, material: sill, chamfer: 0.004)
    }

    /// A compact florist with a clear entrance, a striped canopy and real bouquets.
    private static func buildFlowerShop(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.92, 0.85, 0.77, f)
        let trim = mat(0.96, 0.92, 0.83, f)
        let wood = mat(0.48, 0.40, 0.33, f)
        let sage = mat(0.43, 0.55, 0.47, f)
        let pink = mat(0.76, 0.49, 0.53, f)
        let stone = texMat(.stone, 0.64, 0.62, 0.56, f)
        let roof = roofMat(0.53, 0.43, 0.49, f)
        let glass = glassMat()
        box(r, w: 0.74, h: 0.05, l: 0.60, material: stone, chamfer: 0.015)
        box(r, w: 0.70, h: 0.54, l: 0.56, y: 0.05, material: body, chamfer: 0.006)
        box(r, w: 0.724, h: 0.028, l: 0.584, y: 0.55, material: trim, chamfer: 0.005)
        let roofRoot = SCNNode()
        roofRoot.eulerAngles.y = .pi / 2
        r.addChildNode(roofRoot)
        roofShell(roofRoot, span: 0.56, depth: 0.70, rise: 0.25, y: 0.59, wall: body, roof: roof)
        let front = SCNNode()
        front.position.z = 0.28
        r.addChildNode(front)
        shopPane(front, x: 0.12, y: 0.268, w: 0.29, h: 0.245, frame: sage, sill: trim, glass: glass)
        box(front, w: 0.175, h: 0.34, l: 0.03, x: -0.225, y: 0.05, z: 0.012, material: wood, chamfer: 0.006)
        box(front, w: 0.127, h: 0.294, l: 0.023, x: -0.225, y: 0.058, z: 0.034, material: sage, chamfer: 0.004)
        box(front, w: 0.084, h: 0.144, l: 0.012, x: -0.225, y: 0.173, z: 0.05, material: glass, chamfer: 0.003)
        box(r, w: 0.21, h: 0.04, l: 0.135, x: -0.225, z: 0.337, material: stone, chamfer: 0.011)

        // The fabric slopes away from the wall; the lower edge sits above the glazing.
        let awning = SCNNode()
        awning.position = SCNVector3(0, 0.445, 0.342)
        awning.eulerAngles.x = 0.22
        r.addChildNode(awning)
        for i in 0..<5 {
            let color = i % 2 == 0 ? pink : trim
            let x = CGFloat(i - 2) * 0.136
            box(awning, w: 0.136, h: 0.022, l: 0.18, x: x, y: -0.011, material: color, chamfer: 0.004)
            box(awning, w: 0.136, h: 0.033, l: 0.014, x: x, y: -0.035, z: 0.088, material: color, chamfer: 0.005)
        }
        // Simple five-petal shop emblem, legible without lettering.
        box(front, w: 0.155, h: 0.096, l: 0.022, y: 0.48, z: 0.012, material: sage, chamfer: 0.012)
        for i in 0..<5 {
            let angle = CGFloat(i) * .pi * 2 / 5
            let petal = SCNSphere(radius: 0.017)
            petal.segmentCount = 8
            petal.materials = [trim]
            let n = SCNNode(geometry: petal)
            n.position = SCNVector3(sin(angle) * 0.022, 0.528 + cos(angle) * 0.022, 0.03)
            n.scale.z = 0.35
            front.addChildNode(n)
        }
        let heart = SCNSphere(radius: 0.011)
        heart.segmentCount = 8
        heart.materials = [mat(0.86, 0.68, 0.35, f)]
        let centre = SCNNode(geometry: heart)
        centre.position = SCNVector3(0, 0.528, 0.039)
        centre.scale.z = 0.4
        front.addChildNode(centre)

        for side: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.x = side * 0.35
            wall.eulerAngles.y = side * .pi / 2
            r.addChildNode(wall)
            shopPane(wall, x: -0.025, y: 0.285, w: 0.19, h: 0.21, frame: sage, sill: trim, glass: glass)
            shopPane(wall, x: 0, y: 0.692, w: 0.065, h: 0.075, frame: wood, sill: trim, glass: glass)
        }
        let rear = SCNNode()
        rear.position.z = -0.28
        rear.eulerAngles.y = .pi
        r.addChildNode(rear)
        shopPane(rear, x: 0, y: 0.285, w: 0.21, h: 0.21, frame: sage, sill: trim, glass: glass)

        let leaf = mat(0.40, 0.56, 0.36, f)
        let petals = [pink, mat(0.89, 0.72, 0.40, f), mat(0.65, 0.49, 0.65, f)]
        func bouquet(x: CGFloat, z: CGFloat, y: CGFloat, color: SCNMaterial) {
            cylinder(r, r: 0.008, h: 0.065, x: x, y: y, z: z, material: leaf)
            for side: CGFloat in [-1, 1] {
                let geometry = SCNSphere(radius: 0.026)
                geometry.segmentCount = 6
                geometry.materials = [leaf]
                let n = SCNNode(geometry: geometry)
                n.position = SCNVector3(x + side * 0.016, y + 0.025, z)
                n.scale = SCNVector3(1, 0.48, 0.6)
                n.eulerAngles.z = Float(side * 0.45)
                r.addChildNode(n)
            }
            for (dx, dz, dy) in [(-0.016, 0.0, 0.064), (0.015, 0.007, 0.069), (0.0, -0.012, 0.084)] {
                let head = SCNSphere(radius: 0.021)
                head.segmentCount = 6
                head.materials = [color]
                let n = SCNNode(geometry: head)
                n.position = SCNVector3(x + CGFloat(dx), y + CGFloat(dy), z + CGFloat(dz))
                r.addChildNode(n)
            }
        }
        box(r, w: 0.30, h: 0.067, l: 0.09, x: 0.12, y: 0.014, z: 0.405, material: wood, chamfer: 0.008)
        box(r, w: 0.277, h: 0.007, l: 0.067, x: 0.12, y: 0.078, z: 0.405, material: mat(0.36, 0.30, 0.23), chamfer: 0.003)
        for (i, x) in [CGFloat(0.025), 0.12, 0.215].enumerated() {
            bouquet(x: x, z: 0.405, y: 0.085, color: petals[i])
        }
        // A side display keeps flowers visible when the shop is rotated.
        box(r, w: 0.073, h: 0.06, l: 0.26, x: 0.395, y: 0.013, z: -0.035, material: wood, chamfer: 0.007)
        for (i, z) in [CGFloat(-0.12), -0.035, 0.05].enumerated() {
            bouquet(x: 0.395, z: z, y: 0.074, color: petals[(i + 1) % 3])
        }
    }

    /// A village post office: ochre walls, a projecting postal gable and a
    /// freestanding blue letterbox. Side emblems stay readable after rotation.
    private static func buildPost(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.90, 0.77, 0.51, f)
        let trim = mat(0.95, 0.91, 0.81, f)
        let base = texMat(.stone, 0.63, 0.62, 0.56, f)
        let roof = roofMat(0.37, 0.43, 0.51, f)
        let postalBlue = mat(0.29, 0.46, 0.61, f)
        let timber = mat(0.49, 0.39, 0.29, f)
        let glass = glassMat()

        box(r, w: 0.78, h: 0.065, l: 0.60, material: base, chamfer: 0.018)
        box(r, w: 0.74, h: 0.515, l: 0.56, y: 0.065, material: body, chamfer: 0.007)
        box(r, w: 0.77, h: 0.032, l: 0.59, y: 0.58, material: trim, chamfer: 0.008)
        pyramidRoof(r, w: 0.84, h: 0.26, l: 0.66, y: 0.612, material: roof)

        // The entrance rises through the hipped roof as a small street gable.
        box(r, w: 0.33, h: 0.595, l: 0.15, y: 0.065, z: 0.29,
            material: trim, chamfer: 0.006)
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: -0.18, y: 0))
        profile.addLine(to: CGPoint(x: 0, y: 0.18))
        profile.addLine(to: CGPoint(x: 0.18, y: 0))
        profile.close()
        let pediment = SCNShape(path: profile, extrusionDepth: 0.40)
        pediment.materials = [trim]
        let gable = SCNNode(geometry: pediment)
        gable.position = SCNVector3(0, 0.66, 0.19)
        r.addChildNode(gable)
        for side: CGFloat in [-1, 1] {
            let panel = SCNBox(width: 0.21 * 2.squareRoot(), height: 0.025,
                               length: 0.43, chamferRadius: 0.004)
            panel.materials = [roof]
            let slope = SCNNode(geometry: panel)
            slope.position = SCNVector3(side * 0.105, 0.744, 0.20)
            slope.eulerAngles.z = Float(-side) * .pi / 4
            r.addChildNode(slope)
        }
        box(r, w: 0.038, h: 0.026, l: 0.44, y: 0.833, z: 0.20, material: roof, chamfer: 0.008)
        box(r, w: 0.27, h: 0.05, l: 0.14, z: 0.37, material: base, chamfer: 0.012)
        box(r, w: 0.205, h: 0.345, l: 0.025, y: 0.065, z: 0.371, material: timber, chamfer: 0.007)
        box(r, w: 0.15, h: 0.292, l: 0.024, y: 0.07, z: 0.389, material: doorMat, chamfer: 0.006)
        window(r, x: 0, y: 0.448, z: 0.373, w: 0.14, h: 0.065, material: postalBlue)
        window(r, x: 0, y: 0.448, z: 0.391, w: 0.11, h: 0.042, material: glass)

        func envelope(at position: SCNVector3, yaw: Float, scale: Float = 1) {
            let sign = SCNNode()
            sign.position = position
            sign.eulerAngles.y = yaw
            sign.scale = SCNVector3(scale, scale, scale)
            box(sign, w: 0.23, h: 0.14, l: 0.022, y: -0.07, material: postalBlue, chamfer: 0.012)
            box(sign, w: 0.166, h: 0.092, l: 0.015, y: -0.046, z: 0.018, material: trim, chamfer: 0.004)
            for side: CGFloat in [-1, 1] {
                let dx = side * 0.076, dy: CGFloat = 0.047
                let fold = SCNBox(width: sqrt(dx * dx + dy * dy), height: 0.008,
                                  length: 0.008, chamferRadius: 0.002)
                fold.materials = [postalBlue]
                let line = SCNNode(geometry: fold)
                line.position = SCNVector3(dx / 2, 0.014, 0.030)
                line.eulerAngles.z = Float(atan2(dy, dx))
                sign.addChildNode(line)
            }
            r.addChildNode(sign)
        }
        envelope(at: SCNVector3(0, 0.565, 0.379), yaw: 0)

        // Framed windows around the whole building, including the rear wall.
        for side: CGFloat in [-1, 1] {
            for face: CGFloat in [-1, 1] {
                window(r, x: side * 0.263, y: 0.31, z: face * 0.289,
                       w: 0.145, h: 0.22, material: trim)
                window(r, x: side * 0.263, y: 0.31, z: face * 0.307,
                       w: 0.103, h: 0.175, material: glass)
                box(r, w: 0.011, h: 0.175, l: 0.012, x: side * 0.263, y: 0.2225,
                    z: face * 0.328, material: trim, chamfer: 0.002)
            }
            for z: CGFloat in [-0.14, 0.14] {
                window(r, x: side * 0.377, y: 0.31, z: z, w: 0.15, h: 0.22,
                       onXFace: true, material: trim)
                window(r, x: side * 0.395, y: 0.31, z: z, w: 0.108, h: 0.175,
                       onXFace: true, material: glass)
                box(r, w: 0.012, h: 0.175, l: 0.011, x: side * 0.416, y: 0.2225,
                    z: z, material: trim, chamfer: 0.002)
            }
            envelope(at: SCNVector3(side * 0.384, 0.513, 0), yaw: Float(side) * .pi / 2, scale: 0.79)
        }

        // Raised mailbox, with a visible slot and a pale collection label.
        box(r, w: 0.10, h: 0.035, l: 0.10, x: 0.315, z: 0.365, material: base, chamfer: 0.008)
        box(r, w: 0.035, h: 0.19, l: 0.035, x: 0.315, y: 0.035, z: 0.365, material: postalBlue)
        box(r, w: 0.125, h: 0.17, l: 0.13, x: 0.315, y: 0.205, z: 0.365,
            material: postalBlue, chamfer: 0.024)
        box(r, w: 0.082, h: 0.012, l: 0.008, x: 0.315, y: 0.326, z: 0.433,
            material: mat(0.17, 0.25, 0.31), chamfer: 0.003)
        box(r, w: 0.063, h: 0.038, l: 0.008, x: 0.315, y: 0.255, z: 0.433,
            material: trim, chamfer: 0.003)
    }

    /// A symmetrical brick school with a book over the entry and an open bell cupola.
    private static func buildSchool(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.stone, 0.74, 0.48, 0.39, f)
        let trim = mat(0.95, 0.91, 0.81, f)
        let stone = texMat(.stone, 0.64, 0.62, 0.55, f)
        let timber = mat(0.48, 0.38, 0.29, f)
        let slate = mat(0.36, 0.46, 0.54, f)
        let roof = roofMat(0.39, 0.44, 0.51, f)
        let glass = glassMat()
        box(r, w: 0.88, h: 0.07, l: 0.64, material: stone, chamfer: 0.014)
        box(r, w: 0.84, h: 0.54, l: 0.60, y: 0.07, material: body, chamfer: 0.005)
        box(r, w: 0.872, h: 0.033, l: 0.63, y: 0.572, material: trim, chamfer: 0.005)
        for x: CGFloat in [-0.401, 0.401] {
            for z: CGFloat in [-0.292, 0.292] {
                box(r, w: 0.034, h: 0.505, l: 0.034, x: x, y: 0.07, z: z, material: trim, chamfer: 0.003)
            }
        }
        let roofRoot = SCNNode()
        roofRoot.eulerAngles.y = .pi / 2
        r.addChildNode(roofRoot)
        roofShell(roofRoot, span: 0.60, depth: 0.84, rise: 0.22, y: 0.61, wall: body, roof: roof)

        // Entry projects toward the street; its gable extends into the main roof.
        box(r, w: 0.255, h: 0.535, l: 0.15, y: 0.07, z: 0.34, material: trim, chamfer: 0.006)
        let portico = SCNNode()
        portico.position.z = 0.20
        r.addChildNode(portico)
        roofShell(portico, span: 0.27, depth: 0.36, rise: 0.12, y: 0.605, wall: trim, roof: roof)
        box(r, w: 0.193, h: 0.337, l: 0.023, y: 0.074, z: 0.423, material: timber, chamfer: 0.006)
        box(r, w: 0.143, h: 0.292, l: 0.02, y: 0.081, z: 0.44, material: slate, chamfer: 0.005)
        box(r, w: 0.012, h: 0.287, l: 0.011, y: 0.083, z: 0.455, material: trim, chamfer: 0.002)
        box(r, w: 0.30, h: 0.034, l: 0.14, z: 0.399, material: stone, chamfer: 0.01)
        box(r, w: 0.252, h: 0.036, l: 0.102, y: 0.034, z: 0.395, material: stone, chamfer: 0.009)
        box(r, w: 0.177, h: 0.102, l: 0.015, y: 0.446, z: 0.428, material: slate, chamfer: 0.007)
        for side: CGFloat in [-1, 1] {
            let page = box(r, w: 0.059, h: 0.064, l: 0.012, x: side * 0.032, y: 0.463, z: 0.441,
                           material: trim, chamfer: 0.002)
            page.eulerAngles.z = Float(side * 0.10)
        }
        for face: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.z = face * 0.30
            wall.eulerAngles.y = face > 0 ? 0 : .pi
            r.addChildNode(wall)
            let positions: [CGFloat] = face > 0 ? [-0.282, 0.282] : [-0.282, 0, 0.282]
            for x in positions {
                shopPane(wall, x: x, y: 0.323, w: 0.13, h: 0.257, frame: trim, sill: trim, glass: glass)
                box(wall, w: 0.13, h: 0.011, l: 0.012, x: x, y: 0.352, z: 0.046, material: trim, chamfer: 0.002)
            }
        }
        for side: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.x = side * 0.42
            wall.eulerAngles.y = side * .pi / 2
            r.addChildNode(wall)
            for x: CGFloat in [-0.15, 0.15] {
                shopPane(wall, x: x, y: 0.323, w: 0.105, h: 0.257, frame: trim, sill: trim, glass: glass)
                box(wall, w: 0.105, h: 0.011, l: 0.012, x: x, y: 0.352, z: 0.046, material: trim, chamfer: 0.002)
            }
        }
        // The bell has a flared body, rim, clapper and a visible suspension.
        box(r, w: 0.195, h: 0.129, l: 0.18, y: 0.748, material: trim, chamfer: 0.005)
        for x: CGFloat in [-0.079, 0.079] {
            for z: CGFloat in [-0.071, 0.071] {
                box(r, w: 0.022, h: 0.193, l: 0.022, x: x, y: 0.877, z: z, material: trim, chamfer: 0.003)
            }
        }
        let brass = mat(0.80, 0.63, 0.31, f)
        cylinder(r, r: 0.009, h: 0.055, y: 1.01, material: timber)
        let bell = SCNCone(topRadius: 0.021, bottomRadius: 0.047, height: 0.067)
        bell.radialSegmentCount = 10
        bell.materials = [brass]
        let bellNode = SCNNode(geometry: bell)
        bellNode.position.y = 0.984
        r.addChildNode(bellNode)
        let lip = cylinder(r, r: 0.053, h: 0.014, y: 0.942, material: brass)
        (lip.geometry as? SCNCylinder)?.radialSegmentCount = 10
        let clapper = SCNSphere(radius: 0.012)
        clapper.segmentCount = 8
        clapper.materials = [timber]
        let clapperNode = SCNNode(geometry: clapper)
        clapperNode.position.y = 0.935
        r.addChildNode(clapperNode)
        box(r, w: 0.201, h: 0.021, l: 0.187, y: 1.056, material: trim, chamfer: 0.005)
        pyramidRoof(r, w: 0.245, h: 0.135, l: 0.23, y: 1.077, material: roof)
        cylinder(r, r: 0.008, h: 0.04, y: 1.208, material: brass)
    }

    /// A faceted stone watchtower with a genuinely open timber lookout.
    /// The railing and the space below the roof form its recognisable silhouette.
    private static func buildTower(_ r: SCNNode, _ f: CGFloat) {
        let stone = facadeMat(.stone, 0.67, 0.65, 0.59, f)
        let trim = mat(0.73, 0.70, 0.62, f)
        let timber = mat(0.48, 0.37, 0.27, f)
        let rail = mat(0.62, 0.49, 0.34, f)
        let roof = roofMat(0.37, 0.45, 0.53, f)
        let recess = mat(0.24, 0.29, 0.28)
        recess.name = BuildingNightLighting.windowMaterialName
        func drum(radius: CGFloat, height: CGFloat, y: CGFloat, material: SCNMaterial) {
            let geometry = SCNCylinder(radius: radius, height: height)
            geometry.radialSegmentCount = 8
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.position.y = Float(y + height / 2)
            r.addChildNode(node)
        }
        func beam(_ a: SIMD3<Float>, _ b: SIMD3<Float>, thickness: CGFloat, material: SCNMaterial) {
            let delta = b - a
            let geometry = SCNBox(width: thickness, height: CGFloat(simd_length(delta)),
                                  length: thickness, chamferRadius: 0.003)
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.simdPosition = (a + b) / 2
            node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(delta))
            r.addChildNode(node)
        }

        drum(radius: 0.275, height: 0.065, y: 0, material: stone)
        drum(radius: 0.248, height: 0.035, y: 0.065, material: trim)
        let shaft = SCNCone(topRadius: 0.20, bottomRadius: 0.235, height: 0.79)
        shaft.radialSegmentCount = 8
        shaft.materials = [stone]
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position.y = 0.495
        r.addChildNode(shaftNode)
        drum(radius: 0.226, height: 0.035, y: 0.835, material: trim)

        // Four quiet, dark arrow slits with a light stone surround.
        for i in 0..<4 {
            let face = SCNNode()
            face.eulerAngles.y = Float(i) * .pi / 2
            box(face, w: 0.10, h: 0.205, l: 0.026, y: 0.405, z: 0.211,
                material: trim, chamfer: 0.006)
            box(face, w: 0.043, h: 0.145, l: 0.012, y: 0.435, z: 0.231,
                material: recess, chamfer: 0.004)
            r.addChildNode(face)
        }
        box(r, w: 0.175, h: 0.27, l: 0.032, y: 0.085, z: 0.217, material: trim, chamfer: 0.012)
        box(r, w: 0.12, h: 0.218, l: 0.016, y: 0.092, z: 0.241, material: timber, chamfer: 0.008)
        box(r, w: 0.205, h: 0.04, l: 0.105, z: 0.273, material: stone, chamfer: 0.012)

        drum(radius: 0.335, height: 0.05, y: 0.875, material: timber)
        drum(radius: 0.317, height: 0.016, y: 0.925, material: rail)
        for i in 0..<8 {
            let a = Float(i) * .pi / 4
            let next = Float(i + 1) * .pi / 4
            let direction = SIMD3<Float>(sin(a), 0, cos(a))
            let nextDirection = SIMD3<Float>(sin(next), 0, cos(next))
            beam(direction * 0.205 + SIMD3(0, 0.735, 0),
                 direction * 0.286 + SIMD3(0, 0.887, 0), thickness: 0.035, material: timber)
            beam(direction * 0.275 + SIMD3(0, 0.94, 0),
                 direction * 0.275 + SIMD3(0, 1.385, 0), thickness: 0.034, material: timber)
            for height: Float in [0.975, 1.06] {
                beam(direction * 0.294 + SIMD3(0, height, 0),
                     nextDirection * 0.294 + SIMD3(0, height, 0), thickness: 0.022, material: rail)
            }
        }

        // An octagonal roof stays narrow enough to expose the front gallery.
        drum(radius: 0.315, height: 0.025, y: 1.37, material: timber)
        let canopy = SCNCone(topRadius: 0, bottomRadius: 0.325, height: 0.32)
        canopy.radialSegmentCount = 8
        canopy.materials = [roof]
        let canopyNode = SCNNode(geometry: canopy)
        canopyNode.position.y = 1.555
        r.addChildNode(canopyNode)
        cylinder(r, r: 0.009, h: 0.165, y: 1.71, material: trim)

        let flagPath = UIBezierPath()
        flagPath.move(to: CGPoint(x: 0, y: 0))
        flagPath.addLine(to: CGPoint(x: 0.135, y: 0))
        flagPath.addLine(to: CGPoint(x: 0.103, y: 0.034))
        flagPath.addLine(to: CGPoint(x: 0.135, y: 0.068))
        flagPath.addLine(to: CGPoint(x: 0, y: 0.068))
        flagPath.close()
        let flag = SCNShape(path: flagPath, extrusionDepth: 0.008)
        flag.materials = [mat(0.84, 0.37, 0.28, f)]
        let pennant = SCNNode(geometry: flag)
        pennant.position = SCNVector3(0.012, 1.795, 0)
        r.addChildNode(pennant)
    }

    /// A timber-framed village inn and a furnished beer garden on the second tile.
    private static func buildTavern(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.88, 0.79, 0.62, f)
        let trim = mat(0.95, 0.90, 0.78, f)
        let wood = mat(0.46, 0.34, 0.25, f)
        let boards = texMat(.planks, 0.63, 0.48, 0.32, f)
        let stone = texMat(.stone, 0.63, 0.60, 0.53, f)
        let roof = roofMat(0.37, 0.47, 0.55, f)
        let glass = windowMat()
        box(r, w: 0.80, h: 0.075, l: 0.66, material: stone, chamfer: 0.016)
        box(r, w: 0.76, h: 0.68, l: 0.62, y: 0.075, material: body, chamfer: 0.006)
        let roofRoot = SCNNode()
        roofRoot.eulerAngles.y = .pi / 2
        r.addChildNode(roofRoot)
        roofShell(roofRoot, span: 0.62, depth: 0.76, rise: 0.29, y: 0.755, wall: body, roof: roof)
        for face: CGFloat in [-1, 1] {
            for x: CGFloat in [-0.36, 0, 0.36] {
                box(r, w: 0.032, h: 0.665, l: 0.026, x: x, y: 0.075, z: face * 0.316, material: wood, chamfer: 0.003)
            }
            for y: CGFloat in [0.092, 0.429, 0.708] {
                box(r, w: 0.746, h: 0.03, l: 0.027, y: y, z: face * 0.317, material: wood, chamfer: 0.003)
            }
        }
        let front = SCNNode()
        front.position.z = 0.31
        r.addChildNode(front)
        box(front, w: 0.207, h: 0.326, l: 0.028, x: -0.18, y: 0.075, z: 0.01, material: wood, chamfer: 0.007)
        box(front, w: 0.153, h: 0.28, l: 0.024, x: -0.18, y: 0.084, z: 0.031, material: doorMat, chamfer: 0.006)
        box(front, w: 0.09, h: 0.069, l: 0.014, x: -0.18, y: 0.273, z: 0.049, material: glass, chamfer: 0.004)
        box(r, w: 0.26, h: 0.046, l: 0.14, x: -0.18, z: 0.369, material: stone, chamfer: 0.011)
        shopPane(front, x: 0.18, y: 0.267, w: 0.18, h: 0.19, frame: wood, sill: trim, glass: glass)
        for x: CGFloat in [-0.18, 0.18] {
            shopPane(front, x: x, y: 0.571, w: 0.13, h: 0.156, frame: wood, sill: trim, glass: glass)
        }
        for side: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.x = side * 0.38
            wall.eulerAngles.y = side * .pi / 2
            r.addChildNode(wall)
            for y: CGFloat in [0.267, 0.571] {
                shopPane(wall, x: 0, y: y, w: 0.20, h: 0.166, frame: wood, sill: trim, glass: glass)
            }
            shopPane(wall, x: 0, y: 0.862, w: 0.072, h: 0.087, frame: wood, sill: trim, glass: glass)
            box(wall, w: 0.60, h: 0.03, l: 0.026, y: 0.429, z: 0.006, material: wood, chamfer: 0.003)
        }
        let rear = SCNNode()
        rear.position.z = -0.31
        rear.eulerAngles.y = .pi
        r.addChildNode(rear)
        for x: CGFloat in [-0.18, 0.18] {
            for y: CGFloat in [0.267, 0.571] {
                shopPane(rear, x: x, y: y, w: 0.13, h: 0.156, frame: wood, sill: trim, glass: glass)
            }
        }
        box(r, w: 0.125, h: 0.30, l: 0.14, x: -0.245, y: 0.91, z: -0.12, material: stone, chamfer: 0.007)
        box(r, w: 0.167, h: 0.04, l: 0.18, x: -0.245, y: 1.21, z: -0.12, material: stoneMat, chamfer: 0.008)
        smoke(r, x: -0.245, y: 1.265, z: -0.12)

        // Suspended, framed sign with a small sculpted tankard.
        box(r, w: 0.028, h: 0.18, l: 0.027, x: 0.34, y: 0.44, z: 0.328, material: wood, chamfer: 0.003)
        box(r, w: 0.027, h: 0.025, l: 0.15, x: 0.34, y: 0.599, z: 0.383, material: wood, chamfer: 0.003)
        box(r, w: 0.165, h: 0.145, l: 0.026, x: 0.34, y: 0.44, z: 0.429, material: trim, chamfer: 0.012)
        box(r, w: 0.138, h: 0.119, l: 0.011, x: 0.34, y: 0.453, z: 0.447, material: wood, chamfer: 0.008)
        let gold = mat(0.86, 0.66, 0.31, f)
        cylinder(r, r: 0.026, h: 0.062, x: 0.329, y: 0.477, z: 0.466, material: gold)
        let handle = SCNTorus(ringRadius: 0.017, pipeRadius: 0.0045)
        handle.ringSegmentCount = 10
        handle.pipeSegmentCount = 4
        handle.materials = [gold]
        let loop = SCNNode(geometry: handle)
        loop.position = SCNVector3(0.363, 0.507, 0.468)
        loop.eulerAngles.x = .pi / 2
        r.addChildNode(loop)
        for dx: CGFloat in [-0.016, 0, 0.016] {
            let foam = SCNSphere(radius: 0.012)
            foam.segmentCount = 6
            foam.materials = [trim]
            let n = SCNNode(geometry: foam)
            n.position = SCNVector3(0.329 + dx, 0.539, 0.466)
            r.addChildNode(n)
        }

        let patio = SCNNode()
        patio.position.x = 1
        r.addChildNode(patio)
        box(patio, w: 0.87, h: 0.035, l: 0.87, material: stone, chamfer: 0.014)
        for i in 0..<8 {
            box(patio, w: 0.103, h: 0.018, l: 0.83, x: -0.371 + CGFloat(i) * 0.106, y: 0.035,
                material: boards, chamfer: 0.003)
        }
        // Rear cafe table and two stools, sheltered by a faceted parasol.
        cylinder(patio, r: 0.028, h: 0.205, x: -0.115, y: 0.053, z: -0.19, material: wood)
        let table = cylinder(patio, r: 0.148, h: 0.026, x: -0.115, y: 0.258, z: -0.19, material: boards)
        (table.geometry as? SCNCylinder)?.radialSegmentCount = 12
        for x: CGFloat in [-0.335, 0.105] {
            cylinder(patio, r: 0.042, h: 0.125, x: x, y: 0.053, z: -0.19, material: wood)
            let seat = cylinder(patio, r: 0.063, h: 0.025, x: x, y: 0.178, z: -0.19, material: boards)
            (seat.geometry as? SCNCylinder)?.radialSegmentCount = 10
        }
        cylinder(patio, r: 0.012, h: 0.63, x: -0.115, y: 0.053, z: -0.19, material: trim)
        let parasol = SCNCone(topRadius: 0, bottomRadius: 0.267, height: 0.135)
        parasol.radialSegmentCount = 8
        parasol.materials = [mat(0.72, 0.42, 0.33, f)]
        let canopy = SCNNode(geometry: parasol)
        canopy.position = SCNVector3(-0.115, 0.69, -0.19)
        patio.addChildNode(canopy)
        // Front table with two benches: recognizable seating even at map scale.
        for x: CGFloat in [-0.115, 0.235] {
            box(patio, w: 0.035, h: 0.205, l: 0.12, x: x, y: 0.053, z: 0.235, material: wood, chamfer: 0.004)
        }
        box(patio, w: 0.49, h: 0.027, l: 0.17, x: 0.06, y: 0.258, z: 0.235, material: boards, chamfer: 0.006)
        for z: CGFloat in [0.075, 0.39] {
            for x: CGFloat in [-0.115, 0.235] {
                box(patio, w: 0.025, h: 0.117, l: 0.04, x: x, y: 0.053, z: z, material: wood, chamfer: 0.003)
            }
            box(patio, w: 0.48, h: 0.025, l: 0.07, x: 0.06, y: 0.17, z: z, material: boards, chamfer: 0.005)
        }
        for z: CGFloat in [-0.415, 0, 0.415] {
            box(patio, w: 0.032, h: 0.18, l: 0.032, x: 0.422, y: 0.035, z: z, material: wood, chamfer: 0.004)
        }
        for x: CGFloat in [-0.415, 0.0] {
            box(patio, w: 0.032, h: 0.18, l: 0.032, x: x, y: 0.035, z: -0.422, material: wood, chamfer: 0.004)
        }
        for y: CGFloat in [0.103, 0.171] {
            box(patio, w: 0.022, h: 0.021, l: 0.84, x: 0.422, y: y, material: wood, chamfer: 0.003)
            box(patio, w: 0.84, h: 0.021, l: 0.022, y: y, z: -0.422, material: wood, chamfer: 0.003)
        }
        let barrel = cylinder(patio, r: 0.068, h: 0.17, x: 0.30, y: 0.053, z: -0.305, material: boards)
        (barrel.geometry as? SCNCylinder)?.radialSegmentCount = 10
        for y: CGFloat in [0.087, 0.184] {
            let hoop = cylinder(patio, r: 0.071, h: 0.012, x: 0.30, y: y, z: -0.305, material: stoneMat)
            (hoop.geometry as? SCNCylinder)?.radialSegmentCount = 10
        }
    }

    /// Gentle low-poly chimney smoke; skipped when Reduce Motion is on. SceneKit
    /// particle systems use a square default sprite, so small faceted spheres
    /// match the town much better and remain cheap at this scale.
    private static func smoke(_ parent: SCNNode, x: CGFloat, y: CGFloat, z: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let emitter = SCNNode()
        emitter.position = SCNVector3(x, y, z)

        for i in 0..<3 {
            let sphere = SCNSphere(radius: 0.036 + CGFloat(i) * 0.004)
            sphere.segmentCount = 8
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.86, green: 0.88, blue: 0.84, alpha: 0.24)
            material.lightingModel = .constant
            material.writesToDepthBuffer = false
            sphere.materials = [material]

            let puff = SCNNode(geometry: sphere)
            puff.opacity = 0
            emitter.addChildNode(puff)

            let delay = Double(i) * 0.9
            let drift = CGFloat(0.07 + Double(i) * 0.012)
            let rise = SCNAction.moveBy(x: drift, y: 0.42, z: -drift * 0.25, duration: 2.45)
            rise.timingMode = .easeOut
            let grow = SCNAction.scale(to: 2.15, duration: 2.45)
            grow.timingMode = .easeOut
            let soften = SCNAction.sequence([.wait(duration: 1.15), .fadeOut(duration: 1.3)])
            let reset = SCNAction.group([
                .move(to: SCNVector3Zero, duration: 0),
                .scale(to: 1, duration: 0),
            ])
            puff.runAction(.repeatForever(.sequence([
                .wait(duration: delay),
                .fadeOpacity(to: 0.82, duration: 0.3),
                .group([rise, grow, soften]),
                reset,
                .wait(duration: 0.25 + Double(2 - i) * 0.9),
            ])))
        }
        parent.addChildNode(emitter)
    }

    /// A stone workshop and open forge; the chimney, coals and anvil carry its identity.
    private static func buildBlacksmith(_ r: SCNNode, _ f: CGFloat) {
        let stone = facadeMat(.stone, 0.62, 0.60, 0.54, f)
        let trim = mat(0.77, 0.73, 0.63, f)
        let timber = mat(0.46, 0.35, 0.25, f)
        let soot = texMat(.stone, 0.39, 0.39, 0.36, f)
        let iron = mat(0.30, 0.34, 0.34, f)
        let roof = roofMat(0.38, 0.42, 0.42, f)
        box(r, w: 0.89, h: 0.035, l: 0.72, material: stone, chamfer: 0.018)
        let house = SCNNode()
        house.position.x = -0.21
        r.addChildNode(house)
        box(house, w: 0.46, h: 0.64, l: 0.58, y: 0.055, material: stone, chamfer: 0.006)
        roofShell(house, span: 0.46, depth: 0.58, rise: 0.255, y: 0.695, wall: stone, roof: roof)
        let front = SCNNode()
        front.position.z = 0.29
        house.addChildNode(front)
        box(front, w: 0.233, h: 0.365, l: 0.028, y: 0.055, z: 0.01, material: trim, chamfer: 0.006)
        box(front, w: 0.18, h: 0.314, l: 0.023, y: 0.065, z: 0.031, material: timber, chamfer: 0.005)
        for y: CGFloat in [0.117, 0.30] {
            box(front, w: 0.168, h: 0.018, l: 0.012, y: y, z: 0.049, material: iron, chamfer: 0.002)
        }
        box(house, w: 0.27, h: 0.04, l: 0.13, z: 0.345, material: trim, chamfer: 0.01)
        shopPane(front, x: 0, y: 0.546, w: 0.105, h: 0.115, frame: timber, sill: trim, glass: glassMat())
        let rear = SCNNode()
        rear.position.z = -0.29
        rear.eulerAngles.y = .pi
        house.addChildNode(rear)
        shopPane(rear, x: 0, y: 0.37, w: 0.14, h: 0.18, frame: timber, sill: trim, glass: glassMat())
        let side = SCNNode()
        side.position.x = -0.23
        side.eulerAngles.y = -.pi / 2
        house.addChildNode(side)
        shopPane(side, x: 0, y: 0.37, w: 0.18, h: 0.18, frame: timber, sill: trim, glass: glassMat())

        // Raised lean-to keeps the glowing hearth visible from the map camera.
        for z: CGFloat in [-0.277, 0.116] {
            box(r, w: 0.063, h: 0.055, l: 0.063, x: 0.411, y: 0.035, z: z, material: trim, chamfer: 0.007)
            box(r, w: 0.036, h: 0.49, l: 0.036, x: 0.411, y: 0.086, z: z, material: timber, chamfer: 0.004)
        }
        box(r, w: 0.035, h: 0.031, l: 0.45, x: 0.411, y: 0.555, z: -0.081, material: timber, chamfer: 0.003)
        let leanTo = SCNBox(width: 0.479, height: 0.03, length: 0.48, chamferRadius: 0.005)
        leanTo.materials = [roof]
        let cover = SCNNode(geometry: leanTo)
        cover.position = SCNVector3(0.21, 0.651, -0.08)
        cover.eulerAngles.z = -0.295
        r.addChildNode(cover)

        // Firebox sides, blackened recess and a tapered hood joined to the chimney.
        box(r, w: 0.26, h: 0.14, l: 0.23, x: 0.225, y: 0.035, z: -0.142, material: soot, chamfer: 0.01)
        box(r, w: 0.24, h: 0.22, l: 0.031, x: 0.225, y: 0.175, z: -0.24, material: soot, chamfer: 0.003)
        for x: CGFloat in [0.115, 0.335] {
            box(r, w: 0.035, h: 0.22, l: 0.20, x: x, y: 0.175, z: -0.14, material: soot, chamfer: 0.004)
        }
        let coals = mat(0.87, 0.36, 0.12)
        coals.emission.contents = UIColor(red: 0.85, green: 0.25, blue: 0.045, alpha: 1)
        box(r, w: 0.167, h: 0.018, l: 0.14, x: 0.225, y: 0.174, z: -0.125, material: coals, chamfer: 0.005)
        for (x, z) in [(0.178, -0.12), (0.23, -0.17), (0.273, -0.10)] {
            let ember = SCNSphere(radius: 0.022)
            ember.segmentCount = 6
            ember.materials = [coals]
            let n = SCNNode(geometry: ember)
            n.position = SCNVector3(x, 0.201, z)
            n.scale.y = 0.65
            r.addChildNode(n)
        }
        box(r, w: 0.265, h: 0.03, l: 0.04, x: 0.225, y: 0.363, z: -0.026, material: iron, chamfer: 0.004)
        pyramidRoof(r, w: 0.285, h: 0.24, l: 0.265, x: 0.225, y: 0.386, z: -0.142, material: soot)
        box(r, w: 0.14, h: 0.61, l: 0.15, x: 0.225, y: 0.58, z: -0.142, material: soot, chamfer: 0.005)
        box(r, w: 0.19, h: 0.04, l: 0.20, x: 0.225, y: 1.19, z: -0.142, material: stone, chamfer: 0.007)
        box(r, w: 0.115, h: 0.008, l: 0.125, x: 0.225, y: 1.23, z: -0.142, material: iron, chamfer: 0.003)
        smoke(r, x: 0.225, y: 1.255, z: -0.142)

        // Anvil on a timber stump, with a narrow waist and a pointed horn.
        let stump = cylinder(r, r: 0.078, h: 0.117, x: 0.225, y: 0.035, z: 0.276, material: timber)
        (stump.geometry as? SCNCylinder)?.radialSegmentCount = 10
        box(r, w: 0.139, h: 0.032, l: 0.095, x: 0.225, y: 0.15, z: 0.276, material: iron, chamfer: 0.007)
        box(r, w: 0.064, h: 0.051, l: 0.057, x: 0.225, y: 0.182, z: 0.276, material: iron, chamfer: 0.008)
        box(r, w: 0.161, h: 0.033, l: 0.075, x: 0.215, y: 0.233, z: 0.276, material: iron, chamfer: 0.005)
        let horn = SCNCone(topRadius: 0, bottomRadius: 0.029, height: 0.078)
        horn.radialSegmentCount = 6
        horn.materials = [iron]
        let tip = SCNNode(geometry: horn)
        tip.position = SCNVector3(0.329, 0.249, 0.276)
        tip.eulerAngles.z = -.pi / 2
        r.addChildNode(tip)
        box(r, w: 0.016, h: 0.013, l: 0.096, x: 0.18, y: 0.268, z: 0.285, material: timber, chamfer: 0.003)
        box(r, w: 0.052, h: 0.028, l: 0.026, x: 0.18, y: 0.272, z: 0.245, material: iron, chamfer: 0.005)
    }

    /// An open market pavilion with two stocked counters and a pitched canvas canopy.
    private static func buildMarket(_ r: SCNNode, _ f: CGFloat) {
        let timber = mat(0.48, 0.36, 0.25, f)
        let boards = facadeMat(.planks, 0.64, 0.49, 0.32, f)
        let trim = mat(0.94, 0.89, 0.77, f)
        let canvas = roofMat(0.74, 0.43, 0.34, f)
        let base = texMat(.stone, 0.66, 0.62, 0.52, f)
        box(r, w: 0.87, h: 0.04, l: 0.82, material: base, chamfer: 0.016)
        for x: CGFloat in [-0.365, 0.365] {
            for z: CGFloat in [-0.31, 0.31] {
                box(r, w: 0.057, h: 0.038, l: 0.057, x: x, y: 0.04, z: z, material: base, chamfer: 0.005)
                box(r, w: 0.034, h: 0.555, l: 0.034, x: x, y: 0.06, z: z, material: timber, chamfer: 0.003)
                let brace = box(r, w: 0.13, h: 0.022, l: 0.024, x: x > 0 ? x - 0.04 : x + 0.04,
                                y: 0.548, z: z, material: timber, chamfer: 0.003)
                brace.eulerAngles.z = x > 0 ? -.pi / 4 : .pi / 4
            }
        }
        for z: CGFloat in [-0.31, 0.31] {
            box(r, w: 0.77, h: 0.028, l: 0.028, y: 0.6, z: z, material: timber, chamfer: 0.004)
        }
        // Real roof slopes replace the old single tilted slab. Both edges carry a hem.
        for i in 0..<6 {
            let x = (CGFloat(i) - 2.5) * 0.145
            let color = i % 2 == 0 ? canvas : trim
            for side: CGFloat in [-1, 1] {
                let panel = SCNBox(width: 0.145, height: 0.021, length: sqrt(0.395 * 0.395 + 0.17 * 0.17), chamferRadius: 0.003)
                panel.materials = [color]
                let n = SCNNode(geometry: panel)
                n.position = SCNVector3(x, 0.705, side * 0.1975)
                n.eulerAngles.x = Float(side * atan2(0.17, 0.395))
                r.addChildNode(n)
                box(r, w: 0.145, h: 0.047, l: 0.015, x: x, y: 0.575, z: side * 0.394, material: color, chamfer: 0.004)
            }
        }
        box(r, w: 0.88, h: 0.024, l: 0.035, y: 0.78, material: trim, chamfer: 0.007)
        let produce = [mat(0.76, 0.39, 0.29, f), mat(0.58, 0.65, 0.37, f), mat(0.88, 0.69, 0.35, f)]
        for face: CGFloat in [-1, 1] {
            box(r, w: 0.70, h: 0.19, l: 0.16, y: 0.04, z: face * 0.237, material: boards, chamfer: 0.007)
            box(r, w: 0.735, h: 0.026, l: 0.195, y: 0.23, z: face * 0.237, material: timber, chamfer: 0.005)
            for y: CGFloat in [0.062, 0.186] {
                box(r, w: 0.69, h: 0.016, l: 0.014, y: y, z: face * 0.322, material: trim, chamfer: 0.003)
            }
            for (i, x) in [CGFloat(-0.23), 0, 0.23].enumerated() {
                box(r, w: 0.188, h: 0.038, l: 0.139, x: x, y: 0.256, z: face * 0.24, material: boards, chamfer: 0.005)
                box(r, w: 0.164, h: 0.005, l: 0.115, x: x, y: 0.288, z: face * 0.24,
                    material: mat(0.39, 0.31, 0.23), chamfer: 0.002)
                if face > 0 {
                    for (dx, dz) in [(-0.045, -0.023), (0.04, -0.023), (0.0, 0.032)] {
                        let fruit = SCNSphere(radius: 0.028)
                        fruit.segmentCount = 8
                        fruit.materials = [produce[i]]
                        let n = SCNNode(geometry: fruit)
                        n.position = SCNVector3(x + CGFloat(dx), 0.314, face * 0.24 + CGFloat(dz))
                        r.addChildNode(n)
                    }
                } else {
                    for dx: CGFloat in [-0.045, 0.045] {
                        let loaf = SCNCapsule(capRadius: 0.022, height: 0.10)
                        loaf.radialSegmentCount = 8
                        loaf.heightSegmentCount = 1
                        loaf.materials = [mat(0.80, 0.62, 0.35, f)]
                        let n = SCNNode(geometry: loaf)
                        n.position = SCNVector3(x + dx, 0.313, -0.24)
                        n.eulerAngles.x = .pi / 2
                        r.addChildNode(n)
                    }
                }
            }
        }
        // A low basket on the open side leaves the central aisle uncluttered.
        let basket = cylinder(r, r: 0.066, h: 0.083, x: 0.351, y: 0.04, material: boards)
        (basket.geometry as? SCNCylinder)?.radialSegmentCount = 10
        let rim = cylinder(r, r: 0.071, h: 0.014, x: 0.351, y: 0.113, material: trim)
        (rim.geometry as? SCNCylinder)?.radialSegmentCount = 10
        let goods = SCNSphere(radius: 0.05)
        goods.segmentCount = 8
        goods.materials = [produce[1]]
        let leaf = SCNNode(geometry: goods)
        leaf.position = SCNVector3(0.351, 0.138, 0)
        leaf.scale.y = 0.6
        r.addChildNode(leaf)
    }

    /// The cheapest thing you can put down — a striped ridge tent, no walls.
    private static func buildTent(_ r: SCNNode, _ f: CGFloat) {
        let red   = mat(0.84, 0.25, 0.22, f)
        let white = mat(0.97, 0.95, 0.92, f)
        let dark  = mat(0.24, 0.19, 0.16)

        // Steeper than a 45° roof, so it reads as a tent and not as a wedge:
        // the panels are placed by hand rather than borrowing `gableRoof`.
        let halfW:  CGFloat = 0.22
        let height: CGFloat = 0.36
        let depth:  CGFloat = 0.54
        let slant = sqrt(halfW * halfW + height * height)
        let lean  = Float(atan2(height, halfW))

        // Stripes have to be real panels — at this size a texture would vanish
        // into the flat shading the rest of the town uses.
        let stripes = 7
        let step = depth / CGFloat(stripes)
        for i in 0..<stripes {
            let z = -depth / 2 + step * (CGFloat(i) + 0.5)
            let m = i % 2 == 0 ? red : white
            for side in [-1.0, 1.0] as [CGFloat] {
                let g = SCNBox(width: slant, height: 0.022, length: step, chamferRadius: 0.004)
                g.materials = [m]
                let n = SCNNode(geometry: g)
                n.position = SCNVector3(side * halfW / 2, height / 2, z)
                n.eulerAngles.z = side < 0 ? lean : (.pi - lean)
                r.addChildNode(n)
            }
        }

        /// Triangular end wall. `door` cuts a tent-shaped opening out of it.
        func gable(z: CGFloat, inset: CGFloat, material: SCNMaterial, door: Bool = false) {
            let hw = halfW - inset
            let h  = height - inset * 1.6
            let p = UIBezierPath()
            p.move(to: CGPoint(x: -hw, y: 0))
            p.addLine(to: CGPoint(x: hw, y: 0))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.close()
            if door {
                let dw: CGFloat = 0.075, dh: CGFloat = 0.21
                p.move(to: CGPoint(x: -dw, y: 0))
                p.addLine(to: CGPoint(x: dw, y: 0))
                p.addLine(to: CGPoint(x: dw, y: dh * 0.55))
                p.addLine(to: CGPoint(x: 0, y: dh))
                p.addLine(to: CGPoint(x: -dw, y: dh * 0.55))
                p.close()
                p.usesEvenOddFillRule = true
            }
            let g = SCNShape(path: p, extrusionDepth: 0.02)
            g.materials = [material]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(0, 0, z)
            r.addChildNode(n)
        }
        // Both ends closed. An open front left the silhouette reading as a flat
        // striped ramp from the isometric camera — a solid triangle with a small
        // doorway is what makes it a tent at a glance. Dark inside for depth.
        gable(z: -depth / 2 - 0.006, inset: 0, material: red)
        gable(z: -depth / 2 + 0.04, inset: 0.015, material: dark)
        gable(z:  depth / 2 + 0.006, inset: 0, material: red, door: true)

        // Ridge pole poking out at both ends, guy lines pegged into the grass
        box(r, w: 0.022, h: 0.022, l: depth + 0.12, y: height - 0.035,
            material: woodMat, chamfer: 0.008)
        for (px, pz) in [(-0.3, 0.28), (0.3, 0.28), (-0.3, -0.28), (0.3, -0.28)] as [(CGFloat, CGFloat)] {
            box(r, w: 0.022, h: 0.055, l: 0.022, x: px, z: pz, material: woodMat, chamfer: 0.008)
        }

        // A crate of kit left outside
        box(r, w: 0.1, h: 0.09, l: 0.1, x: 0.31, z: 0.09, material: woodMat)
    }

    /// A substantial timber-framed home with a separate, open hay shelter.
    /// The sheltered working yard gives the two-cell estate its own silhouette.
    private static func buildHomestead(_ r: SCNNode, _ f: CGFloat) {
        let plaster = facadeMat(.plaster, 0.92, 0.86, 0.73, f)
        let trim = mat(0.96, 0.91, 0.80, f)
        let roof = roofMat(0.65, 0.38, 0.29, f)
        let base = texMat(.stone, 0.65, 0.62, 0.54, f)
        let timber = mat(0.47, 0.36, 0.26, f)
        let boards = texMat(.planks, 0.62, 0.48, 0.31, f)
        let sage = mat(0.43, 0.54, 0.45, f)
        let hay = mat(0.80, 0.68, 0.40, f)
        let straw = mat(0.89, 0.78, 0.51, f)
        let glass = glassMat()

        box(r, w: 0.78, h: 0.085, l: 0.65, material: base, chamfer: 0.016)
        box(r, w: 0.73, h: 0.525, l: 0.59, y: 0.085, material: plaster, chamfer: 0.006)
        roofShell(r, span: 0.73, depth: 0.59, rise: 0.345, y: 0.61, wall: plaster, roof: roof)

        // Framing follows the facade and the actual pitch of the gable.
        func beam(_ parent: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>, width: CGFloat) {
            let delta = b - a
            let geometry = SCNBox(width: width, height: CGFloat(simd_length(delta)), length: width, chamferRadius: 0.002)
            geometry.materials = [timber]
            let n = SCNNode(geometry: geometry)
            n.simdPosition = (a + b) / 2
            n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(delta))
            parent.addChildNode(n)
        }
        for face: CGFloat in [-1, 1] {
            let z = face * 0.30
            for x: CGFloat in [-0.344, 0.344] {
                box(r, w: 0.034, h: 0.525, l: 0.027, x: x, y: 0.085, z: z, material: timber, chamfer: 0.003)
            }
            box(r, w: 0.71, h: 0.032, l: 0.027, y: 0.572, z: z, material: timber, chamfer: 0.003)
            box(r, w: 0.032, h: 0.09, l: 0.025, y: 0.845, z: z, material: timber, chamfer: 0.003)
            for side: Float in [-1, 1] {
                beam(r, from: SIMD3(side * 0.302, 0.613, Float(z)),
                     to: SIMD3(side * 0.065, 0.864, Float(z)), width: 0.023)
            }
        }

        // Centered entry: broad stone steps and a small canopy on timber brackets.
        box(r, w: 0.208, h: 0.35, l: 0.029, y: 0.085, z: 0.305, material: timber, chamfer: 0.006)
        box(r, w: 0.158, h: 0.305, l: 0.025, y: 0.093, z: 0.326, material: sage, chamfer: 0.005)
        box(r, w: 0.084, h: 0.068, l: 0.013, y: 0.286, z: 0.345, material: glass, chamfer: 0.004)
        box(r, w: 0.29, h: 0.039, l: 0.175, z: 0.361, material: base, chamfer: 0.01)
        box(r, w: 0.245, h: 0.045, l: 0.12, y: 0.039, z: 0.341, material: base, chamfer: 0.009)
        let canopy = box(r, w: 0.29, h: 0.027, l: 0.16, y: 0.454, z: 0.347, material: roof, chamfer: 0.005)
        canopy.eulerAngles.x = 0.22
        for x: CGFloat in [-0.105, 0.105] {
            box(r, w: 0.024, h: 0.066, l: 0.06, x: x, y: 0.392, z: 0.32, material: timber, chamfer: 0.003)
        }
        func framedWindow(_ wall: SCNNode, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, shutters: Bool = true) {
            window(wall, x: x, y: y, z: 0.008, w: w + 0.042, h: h + 0.042, material: timber)
            window(wall, x: x, y: y, z: 0.026, w: w, h: h, material: glass)
            box(wall, w: 0.011, h: h, l: 0.012, x: x, y: y - h / 2, z: 0.045, material: trim, chamfer: 0.002)
            box(wall, w: w + 0.059, h: 0.023, l: 0.061, x: x, y: y - h / 2 - 0.034, z: 0.023, material: trim, chamfer: 0.004)
            if shutters {
                for side: CGFloat in [-1, 1] {
                    box(wall, w: 0.029, h: h + 0.03, l: 0.024, x: x + side * (w / 2 + 0.043),
                        y: y - h / 2 - 0.015, z: 0.013, material: sage, chamfer: 0.004)
                }
            }
        }
        for face: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.z = face * 0.295
            wall.eulerAngles.y = face > 0 ? 0 : .pi
            r.addChildNode(wall)
            for x: CGFloat in [-0.239, 0.239] {
                framedWindow(wall, x: x, y: 0.327, w: 0.086, h: 0.166)
            }
            framedWindow(wall, x: 0, y: 0.743, w: 0.105, h: 0.115, shutters: false)
        }
        for side: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.x = side * 0.365
            wall.eulerAngles.y = side * .pi / 2
            r.addChildNode(wall)
            framedWindow(wall, x: 0, y: 0.327, w: 0.17, h: 0.18)
        }
        box(r, w: 0.12, h: 0.34, l: 0.13, x: -0.22, y: 0.72, z: -0.14, material: base, chamfer: 0.007)
        box(r, w: 0.16, h: 0.038, l: 0.17, x: -0.22, y: 1.06, z: -0.14, material: stoneMat, chamfer: 0.008)
        smoke(r, x: -0.22, y: 1.11, z: -0.14)

        // A barrel beside the house, where the courtyard meets the side wall.
        let barrel = cylinder(r, r: 0.063, h: 0.15, x: 0.427, y: 0.005, z: 0.19, material: boards)
        (barrel.geometry as? SCNCylinder)?.radialSegmentCount = 10
        for y: CGFloat in [0.033, 0.113] {
            let hoop = cylinder(r, r: 0.066, h: 0.014, x: 0.427, y: y, z: 0.19, material: mat(0.42, 0.44, 0.40, f))
            (hoop.geometry as? SCNCylinder)?.radialSegmentCount = 10
        }

        let yard = SCNNode()
        yard.position.x = 1
        r.addChildNode(yard)
        box(yard, w: 0.86, h: 0.027, l: 0.86, material: mat(0.72, 0.65, 0.50, f), chamfer: 0.035)
        let shed = SCNNode()
        shed.position.z = -0.15
        yard.addChildNode(shed)
        // Tall enough to see the stored hay through the front opening.
        for x: CGFloat in [-0.277, 0.277] {
            for z: CGFloat in [-0.155, 0.155] {
                box(shed, w: 0.063, h: 0.045, l: 0.063, x: x, y: 0.027, z: z, material: base, chamfer: 0.008)
                box(shed, w: 0.041, h: 0.408, l: 0.041, x: x, y: 0.06, z: z, material: timber, chamfer: 0.004)
                let direction: Float = x < 0 ? 1 : -1
                beam(shed, from: SIMD3(Float(x), 0.34, Float(z)),
                     to: SIMD3(Float(x) + direction * 0.10, 0.45, Float(z)), width: 0.025)
            }
        }
        box(shed, w: 0.595, h: 0.036, l: 0.032, y: 0.432, z: 0.158, material: timber, chamfer: 0.003)
        box(shed, w: 0.595, h: 0.036, l: 0.032, y: 0.432, z: -0.158, material: timber, chamfer: 0.003)
        box(shed, w: 0.57, h: 0.20, l: 0.028, y: 0.04, z: -0.158, material: boards, chamfer: 0.004)
        let shedRoof = SCNNode()
        shedRoof.eulerAngles.y = .pi / 2
        shed.addChildNode(shedRoof)
        roofShell(shedRoof, span: 0.34, depth: 0.61, rise: 0.17, y: 0.468, wall: boards, roof: roof)
        for x: CGFloat in [-0.137, 0.137] {
            box(shed, w: 0.235, h: 0.115, l: 0.23, x: x, y: 0.03, z: -0.017, material: hay, chamfer: 0.014)
            for dx: CGFloat in [-0.065, 0.065] {
                box(shed, w: 0.012, h: 0.116, l: 0.234, x: x + dx, y: 0.031, z: -0.017, material: straw, chamfer: 0.003)
            }
        }
        box(shed, w: 0.225, h: 0.105, l: 0.21, y: 0.145, z: -0.028, material: straw, chamfer: 0.013)
        for x: CGFloat in [-0.061, 0.061] {
            box(shed, w: 0.011, h: 0.107, l: 0.214, x: x, y: 0.145, z: -0.028, material: hay, chamfer: 0.003)
        }

        // Faceted round bales, grounded after rotation and showing their cut ends.
        for (x, z) in [(CGFloat(-0.15), CGFloat(0.275)), (CGFloat(0.19), CGFloat(0.23))] {
            let roll = SCNCylinder(radius: 0.087, height: 0.15)
            roll.radialSegmentCount = 12
            roll.materials = [hay]
            let bale = SCNNode(geometry: roll)
            bale.position = SCNVector3(x, 0.114, z)
            bale.eulerAngles.z = .pi / 2
            yard.addChildNode(bale)
            for side: CGFloat in [-1, 1] {
                let end = SCNCylinder(radius: 0.063, height: 0.003)
                end.radialSegmentCount = 12
                end.materials = [straw]
                let disk = SCNNode(geometry: end)
                disk.position.y = Float(side * 0.076)
                bale.addChildNode(disk)
            }
        }
        // A low perimeter, with a gap in the front for the farmyard entrance.
        for x: CGFloat in [-0.425, -0.12, 0.425] {
            box(yard, w: 0.031, h: 0.165, l: 0.031, x: x, y: 0.027, z: 0.43, material: timber, chamfer: 0.004)
        }
        for z: CGFloat in [-0.42, 0, 0.43] {
            box(yard, w: 0.031, h: 0.165, l: 0.031, x: 0.43, y: 0.027, z: z, material: timber, chamfer: 0.004)
        }
        for y: CGFloat in [0.08, 0.14] {
            box(yard, w: 0.30, h: 0.02, l: 0.02, x: -0.273, y: y, z: 0.43, material: timber, chamfer: 0.003)
            box(yard, w: 0.02, h: 0.02, l: 0.86, x: 0.43, y: y, material: timber, chamfer: 0.003)
        }
    }

    /// A compact volunteer fire station: twin carriage doors, hose tower and a brass crest.
    private static func buildFireStation(_ r: SCNNode, _ f: CGFloat) {
        let brick = facadeMat(.stone,0.72,0.46,0.36,f)
        let trim = mat(0.95,0.89,0.76,f)
        let stone = texMat(.stone,0.63,0.61,0.54,f)
        let red = mat(0.63,0.29,0.25,f)
        let timber = mat(0.43,0.36,0.29,f)
        let iron = mat(0.33,0.38,0.39,f)
        let gold = mat(0.82,0.66,0.36,f)
        let roof = roofMat(0.37,0.43,0.48,f)
        let glass = glassMat()
        box(r,w:0.84,h:0.06,l:0.65,material:stone,chamfer:0.014)
        box(r,w:0.79,h:0.62,l:0.59,y:0.06,material:brick,chamfer:0.005)
        box(r,w:0.815,h:0.032,l:0.62,y:0.653,material:trim,chamfer:0.004)
        let roofRoot = SCNNode(); roofRoot.eulerAngles.y = .pi/2; r.addChildNode(roofRoot)
        roofShell(roofRoot,span:0.59,depth:0.79,rise:0.245,y:0.685,wall:brick,roof:roof)
        box(r,w:0.83,h:0.028,l:0.175,z:0.352,material:stone,chamfer:0.008)
        let front = SCNNode(); front.position.z = 0.295; r.addChildNode(front)
        for x: CGFloat in [-0.19,0.19] {
            box(front,w:0.335,h:0.398,l:0.028,x:x,y:0.059,z:0.011,material:trim,chamfer:0.009)
            box(front,w:0.282,h:0.353,l:0.02,x:x,y:0.067,z:0.032,material:timber,chamfer:0.004)
            for side: CGFloat in [-1,1] {
                let leaf = x+side*0.068
                box(front,w:0.128,h:0.332,l:0.021,x:leaf,y:0.073,z:0.047,material:red,chamfer:0.003)
                for dx: CGFloat in [-0.031,0.031] {
                    box(front,w:0.004,h:0.223,l:0.006,x:leaf+dx,y:0.08,z:0.060,material:timber,chamfer:0.001)
                }
                window(front,x:leaf,y:0.354,z:0.061,w:0.096,h:0.058,material:glass)
                box(front,w:0.006,h:0.057,l:0.009,x:leaf,y:0.325,z:0.08,material:trim,chamfer:0.001)
                for y: CGFloat in [0.11,0.282] {
                    box(front,w:0.12,h:0.013,l:0.010,x:leaf,y:y,z:0.066,material:iron,chamfer:0.002)
                }
                box(front,w:0.008,h:0.032,l:0.011,x:x+side*0.021,y:0.196,z:0.070,material:gold,chamfer:0.002)
            }
            box(front,w:0.34,h:0.023,l:0.050,x:x,y:0.459,z:0.019,material:stone,chamfer:0.004)
            shopPane(front,x:x,y:0.562,w:0.135,h:0.11,frame:trim,sill:trim,glass:glass)
        }
        for x: CGFloat in [-0.379,0,0.379] {
            box(front,w:0.031,h:0.60,l:0.033,x:x,y:0.06,z:0.009,material:trim,chamfer:0.003)
        }
        // A small shield and helmet, legible at map scale without miniature text.
        let shield = UIBezierPath(); shield.move(to:CGPoint(x:-0.063,y:0.055)); shield.addLine(to:CGPoint(x:0.063,y:0.055))
        shield.addLine(to:CGPoint(x:0.054,y:-0.025)); shield.addLine(to:CGPoint(x:0,y:-0.067))
        shield.addLine(to:CGPoint(x:-0.054,y:-0.025)); shield.close()
        let crest = SCNShape(path:shield,extrusionDepth:0.015); crest.materials = [red]
        let crestNode = SCNNode(geometry:crest); crestNode.position = SCNVector3(0,0.562,0.043); front.addChildNode(crestNode)
        let helmet = SCNSphere(radius:0.034); helmet.segmentCount = 10; helmet.materials = [gold]
        let helmetNode = SCNNode(geometry:helmet); helmetNode.position = SCNVector3(0,0.565,0.063); helmetNode.scale = SCNVector3(1,0.70,0.32); front.addChildNode(helmetNode)
        box(front,w:0.086,h:0.012,l:0.012,y:0.545,z:0.068,material:gold,chamfer:0.003)
        for side: Float in [-1,1] {
            let wall = SCNNode(); wall.position.x = side*0.395; wall.eulerAngles.y = side * .pi/2; r.addChildNode(wall)
            shopPane(wall,x:0.05,y:0.40,w:0.16,h:0.19,frame:trim,sill:trim,glass:glass)
            shopPane(wall,x:0,y:0.768,w:0.075,h:0.085,frame:trim,sill:trim,glass:glass)
        }
        let rear = SCNNode(); rear.position.z = -0.295; rear.eulerAngles.y = .pi; r.addChildNode(rear)
        shopPane(rear,x:0.15,y:0.385,w:0.16,h:0.19,frame:trim,sill:trim,glass:glass)
        // The tall drying tower interrupts the low roof and reads from every side.
        let tower = SCNNode(); tower.position = SCNVector3(0.245,0,-0.245); r.addChildNode(tower)
        box(tower,w:0.26,h:1.18,l:0.25,y:0.06,material:brick,chamfer:0.005)
        for x: CGFloat in [-0.12,0.12] {
            for z: CGFloat in [-0.115,0.115] { box(tower,w:0.022,h:1.14,l:0.022,x:x,y:0.075,z:z,material:trim,chamfer:0.002) }
        }
        for side in 0..<4 {
            let wall = SCNNode(); wall.eulerAngles.y = Float(side) * .pi/2; tower.addChildNode(wall)
            box(wall,w:0.149,h:0.225,l:0.019,y:0.945,z:0.135,material:trim,chamfer:0.006)
            box(wall,w:0.110,h:0.181,l:0.013,y:0.968,z:0.151,material:timber,chamfer:0.003)
            for y: CGFloat in [0.984,1.025,1.066,1.107] {
                let slat = box(wall,w:0.118,h:0.018,l:0.027,y:y,z:0.161,material:iron,chamfer:0.002)
                slat.eulerAngles.x = 0.22
            }
        }
        box(tower,w:0.307,h:0.038,l:0.297,y:1.226,material:trim,chamfer:0.006)
        pyramidRoof(tower,w:0.35,h:0.15,l:0.34,y:1.264,material:roof)
        // A coiled hose on the clear side wall; quiet practical detail, no visual clutter.
        let hose = SCNTorus(ringRadius:0.055,pipeRadius:0.013); hose.ringSegmentCount = 16; hose.pipeSegmentCount = 6
        hose.materials = [mat(0.75,0.65,0.46,f)]
        let hoseNode = SCNNode(geometry:hose); hoseNode.position = SCNVector3(-0.419,0.22,0.06); hoseNode.eulerAngles.z = .pi/2; r.addChildNode(hoseNode)
        box(r,w:0.028,h:0.065,l:0.022,x:-0.423,y:0.24,z:0.06,material:iron,chamfer:0.003)
        cylinder(r,r:0.023,h:0.092,x:-0.372,y:0.031,z:0.408,material:red)
        cylinder(r,r:0.031,h:0.019,x:-0.372,y:0.121,z:0.408,material:red)
        box(r,w:0.073,h:0.02,l:0.024,x:-0.372,y:0.083,z:0.408,material:iron,chamfer:0.006)
    }

    /// A small civic police house, with a blue entry, a brass badge and warm evening windows.
    private static func buildPoliceStation(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster,0.64,0.72,0.76,f)
        let trim = mat(0.94,0.90,0.79,f)
        let stone = texMat(.stone,0.62,0.63,0.59,f)
        let blue = mat(0.28,0.40,0.52,f)
        let iron = mat(0.31,0.36,0.39,f)
        let gold = mat(0.84,0.69,0.39,f)
        let roof = roofMat(0.34,0.42,0.50,f)
        let glass = glassMat()
        box(r,w:0.80,h:0.068,l:0.64,material:stone,chamfer:0.014)
        box(r,w:0.75,h:0.71,l:0.58,y:0.068,material:body,chamfer:0.006)
        box(r,w:0.772,h:0.035,l:0.604,y:0.434,material:trim,chamfer:0.004)
        box(r,w:0.798,h:0.041,l:0.625,y:0.755,material:trim,chamfer:0.005)
        roofShell(r,span:0.75,depth:0.58,rise:0.30,y:0.795,wall:body,roof:roof)
        // Pale corner quoins give the service building weight without a heavy texture.
        for x: CGFloat in [-0.357,0.357] {
            for z: CGFloat in [-0.279,0.279] {
                for i in 0..<7 {
                    box(r,w:i%2 == 0 ? 0.071 : 0.053,h:0.061,l:i%2 == 0 ? 0.047 : 0.067,x:x,y:0.082+CGFloat(i)*0.095,z:z,material:trim,chamfer:0.003)
                }
            }
        }
        let front = SCNNode(); front.position.z = 0.29; r.addChildNode(front)
        for x: CGFloat in [-0.25,0.25] {
            shopPane(front,x:x,y:0.265,w:0.119,h:0.185,frame:trim,sill:stone,glass:glass)
            shopPane(front,x:x,y:0.61,w:0.137,h:0.192,frame:trim,sill:stone,glass:glass)
            box(front,w:0.136,h:0.009,l:0.012,x:x,y:0.614,z:0.046,material:trim,chamfer:0.002)
        }
        box(front,w:0.214,h:0.329,l:0.034,y:0.067,z:0.008,material:trim,chamfer:0.007)
        box(front,w:0.169,h:0.291,l:0.023,y:0.080,z:0.032,material:blue,chamfer:0.004)
        window(front,x:0,y:0.31,z:0.05,w:0.126,h:0.083,material:glass)
        box(front,w:0.007,h:0.082,l:0.012,y:0.269,z:0.067,material:trim,chamfer:0.001)
        box(front,w:0.117,h:0.103,l:0.009,y:0.116,z:0.048,material:iron,chamfer:0.004)
        box(front,w:0.011,h:0.042,l:0.016,x:0.055,y:0.222,z:0.055,material:gold,chamfer:0.004)
        // Low stone steps meet the road; the porch stops clear of the first-floor windows.
        box(r,w:0.34,h:0.025,l:0.183,y:0,z:0.355,material:stone,chamfer:0.009)
        box(r,w:0.29,h:0.044,l:0.128,y:0.024,z:0.333,material:trim,chamfer:0.006)
        for x: CGFloat in [-0.132,0.132] {
            box(r,w:0.046,h:0.045,l:0.046,x:x,y:0.043,z:0.362,material:trim,chamfer:0.005)
            box(r,w:0.027,h:0.307,l:0.031,x:x,y:0.078,z:0.362,material:trim,chamfer:0.003)
            box(r,w:0.048,h:0.028,l:0.049,x:x,y:0.365,z:0.362,material:trim,chamfer:0.003)
        }
        box(r,w:0.343,h:0.032,l:0.185,y:0.392,z:0.354,material:trim,chamfer:0.005)
        let porchRoof = box(r,w:0.371,h:0.025,l:0.205,y:0.423,z:0.344,material:roof,chamfer:0.005)
        porchRoof.eulerAngles.x = 0.10
        // Shield and six-point service star replace the old floating blue beacon.
        let shield = UIBezierPath(); shield.move(to:CGPoint(x:-0.073,y:0.065)); shield.addLine(to:CGPoint(x:0.073,y:0.065))
        shield.addLine(to:CGPoint(x:0.062,y:-0.023)); shield.addLine(to:CGPoint(x:0,y:-0.078))
        shield.addLine(to:CGPoint(x:-0.062,y:-0.023)); shield.close()
        let crest = SCNShape(path:shield,extrusionDepth:0.012); crest.chamferRadius = 0.003; crest.materials = [gold]
        let crestNode = SCNNode(geometry:crest); crestNode.position = SCNVector3(0,0.623,0.034); front.addChildNode(crestNode)
        let inset = SCNShape(path:shield,extrusionDepth:0.013); inset.materials = [blue]
        let insetNode = SCNNode(geometry:inset); insetNode.scale = SCNVector3(0.82,0.82,1); insetNode.position = SCNVector3(0,0.625,0.044); front.addChildNode(insetNode)
        let star = UIBezierPath()
        for i in 0..<12 {
            let a = CGFloat(i) * .pi/6 + .pi/2, radius: CGFloat = i%2 == 0 ? 0.040 : 0.022
            let p = CGPoint(x:cos(a)*radius,y:sin(a)*radius)
            if i == 0 { star.move(to:p) } else { star.addLine(to:p) }
        }
        star.close()
        let emblem = SCNShape(path:star,extrusionDepth:0.006); emblem.materials = [gold]
        let emblemNode = SCNNode(geometry:emblem); emblemNode.position = SCNVector3(0,0.629,0.057); front.addChildNode(emblemNode)
        // A small attic light fills the closed front gable.
        shopPane(front,x:0,y:0.88,w:0.080,h:0.074,frame:trim,sill:trim,glass:glass)
        for side: Float in [-1,1] {
            let wall = SCNNode(); wall.position.x = side*0.375; wall.eulerAngles.y = side * .pi/2; r.addChildNode(wall)
            for x: CGFloat in [-0.135,0.135] {
                for y: CGFloat in [0.267,0.61] { shopPane(wall,x:x,y:y,w:0.108,h:0.172,frame:trim,sill:stone,glass:glass) }
            }
        }
        let rear = SCNNode(); rear.position.z = -0.29; rear.eulerAngles.y = .pi; r.addChildNode(rear)
        for x: CGFloat in [-0.218,0.218] {
            for y: CGFloat in [0.267,0.61] { shopPane(rear,x:x,y:y,w:0.13,h:0.172,frame:trim,sill:stone,glass:glass) }
        }
        shopPane(rear,x:0,y:0.88,w:0.080,h:0.074,frame:trim,sill:trim,glass:glass)
        // Dark lantern frames keep the warm glow controlled at night.
        for x: CGFloat in [-0.148,0.148] {
            box(front,w:0.058,h:0.072,l:0.039,x:x,y:0.30,z:0.074,material:glass,chamfer:0.005)
            for y: CGFloat in [0.289,0.372] { box(front,w:0.074,h:0.012,l:0.060,x:x,y:y,z:0.072,material:iron,chamfer:0.004) }
            for dx: CGFloat in [-0.024,0.024] { box(front,w:0.005,h:0.072,l:0.009,x:x+dx,y:0.30,z:0.095,material:iron,chamfer:0.001) }
        }
        box(r,w:0.092,h:0.27,l:0.10,x:0.238,y:0.868,z:-0.176,material:stone,chamfer:0.005)
        box(r,w:0.121,h:0.032,l:0.129,x:0.238,y:1.132,z:-0.176,material:trim,chamfer:0.004)
        box(r,w:0.077,h:0.008,l:0.083,x:0.238,y:1.165,z:-0.176,material:iron,chamfer:0.002)
    }

    /// A small town clinic: ivory plaster, blue-green joinery and a sheltered glass entrance.
    private static func buildHospital(_ r: SCNNode, _ f: CGFloat) {
        let plaster = facadeMat(.plaster,0.93,0.90,0.79,f), trim = mat(0.98,0.95,0.85,f)
        let stone = texMat(.stone,0.67,0.68,0.61,f), teal = mat(0.37,0.56,0.54,f)
        let roof = roofMat(0.36,0.48,0.53,f), wood = mat(0.50,0.39,0.28,f)
        let red = mat(0.76,0.28,0.25,f), glass = glassMat()
        let main = SCNNode(); main.position.z = -0.055; r.addChildNode(main)
        box(main,w:0.79,h:0.061,l:0.72,material:stone,chamfer:0.017)
        box(main,w:0.69,h:0.74,l:0.59,y:0.061,material:plaster,chamfer:0.007)
        for y: CGFloat in [0.064,0.409,0.787] {
            box(main,w:0.722,h:0.027,l:0.621,y:y,material:trim,chamfer:0.004)
        }
        for x: CGFloat in [-0.329,0.329] {
            for z: CGFloat in [-0.279,0.279] {
                box(main,w:0.028,h:0.69,l:0.028,x:x,y:0.095,z:z,material:trim,chamfer:0.003)
            }
        }
        roofShell(main,span:0.715,depth:0.62,rise:0.285,y:0.818,wall:plaster,roof:roof)
        func clinicWindow(_ wall: SCNNode, x: CGFloat, y: CGFloat, w: CGFloat = 0.105, h: CGFloat = 0.178) {
            window(wall,x:x,y:y,z:0.013,w:w+0.036,h:h+0.035,material:teal)
            window(wall,x:x,y:y,z:0.030,w:w,h:h,material:glass)
            box(wall,w:0.009,h:h,l:0.010,x:x,y:y-h/2,z:0.047,material:trim,chamfer:0.001)
            box(wall,w:w,h:0.010,l:0.010,x:x,y:y+0.012,z:0.047,material:trim,chamfer:0.001)
            box(wall,w:w+0.064,h:0.022,l:0.059,x:x,y:y-h/2-0.029,z:0.022,material:stone,chamfer:0.004)
        }
        for side in 0..<4 {
            let wall = SCNNode(); wall.eulerAngles.y = Float(side)*Float.pi/2
            wall.position = side%2 == 0 ? SCNVector3(0,0,side == 0 ? 0.295 : -0.295) : SCNVector3(side == 1 ? 0.345 : -0.345,0,0)
            main.addChildNode(wall)
            let xs: [CGFloat] = side%2 == 0 ? [-0.225,0.225] : [-0.16,0.16]
            for x in xs { for y: CGFloat in [0.248,0.621] { clinicWindow(wall,x:x,y:y) } }
            if side == 0 { clinicWindow(wall,x:0,y:0.647,w:0.10,h:0.13) }
        }
        // The pale sign reads clearly against the gable, above the entrance.
        box(main,w:0.195,h:0.168,l:0.028,y:0.849,z:0.319,material:trim,chamfer:0.012)
        box(main,w:0.106,h:0.031,l:0.012,y:0.916,z:0.340,material:red,chamfer:0.003)
        box(main,w:0.031,h:0.106,l:0.012,y:0.878,z:0.340,material:red,chamfer:0.003)
        // A real pair of glazed doors under a low pitched porch.
        box(r,w:0.218,h:0.302,l:0.035,y:0.067,z:0.249,material:teal,chamfer:0.006)
        for x: CGFloat in [-0.049,0.049] {
            box(r,w:0.083,h:0.258,l:0.016,x:x,y:0.082,z:0.273,material:glass,chamfer:0.003)
            box(r,w:0.083,h:0.032,l:0.016,x:x,y:0.083,z:0.285,material:teal,chamfer:0.003)
            box(r,w:0.008,h:0.045,l:0.012,x:x*0.37,y:0.19,z:0.288,material:trim,chamfer:0.002)
        }
        let porch = SCNNode(); porch.position.z = 0.319; r.addChildNode(porch)
        for x: CGFloat in [-0.146,0.146] {
            box(porch,w:0.032,h:0.327,l:0.032,x:x,y:0.061,z:0.066,material:teal,chamfer:0.003)
            box(porch,w:0.054,h:0.049,l:0.054,x:x,y:0.038,z:0.066,material:stone,chamfer:0.005)
        }
        box(porch,w:0.336,h:0.025,l:0.163,y:0.383,material:trim,chamfer:0.004)
        roofShell(porch,span:0.307,depth:0.146,rise:0.081,y:0.409,wall:trim,roof:roof)
        box(r,w:0.36,h:0.027,l:0.20,y:0.003,z:0.378,material:stone,chamfer:0.009)
        box(r,w:0.304,h:0.032,l:0.149,y:0.030,z:0.362,material:trim,chamfer:0.007)
        // A small bench and planted urn soften the entrance without blocking the path.
        for x: CGFloat in [-0.317,-0.217] {
            box(r,w:0.02,h:0.065,l:0.055,x:x,y:0.025,z:0.346,material:teal,chamfer:0.003)
        }
        box(r,w:0.159,h:0.019,l:0.074,x:-0.267,y:0.09,z:0.346,material:wood,chamfer:0.004)
        box(r,w:0.159,h:0.066,l:0.017,x:-0.267,y:0.113,z:0.315,material:wood,chamfer:0.004)
        cylinder(r,r:0.053,h:0.067,x:0.282,y:0.018,z:0.345,material:stone)
        let bush = SCNSphere(radius:0.063); bush.segmentCount = 12; bush.materials = [mat(0.43,0.58,0.37,f)]
        let shrub = SCNNode(geometry:bush); shrub.position = SCNVector3(0.282,0.124,0.345); shrub.scale.y = 0.85; r.addChildNode(shrub)
        box(main,w:0.083,h:0.19,l:0.094,x:-0.215,y:0.943,z:-0.18,material:plaster,chamfer:0.005)
        box(main,w:0.108,h:0.027,l:0.118,x:-0.215,y:1.124,z:-0.18,material:trim,chamfer:0.004)
        box(main,w:0.063,h:0.006,l:0.072,x:-0.215,y:1.151,z:-0.18,material:stone,chamfer:0.002)
    }

    /// A two-cell baroque residence: mansard pavilions, a copper-blue dome and a columned balcony.
    private static func buildChateau(_ r: SCNNode, _ f: CGFloat) {
        let plaster = facadeMat(.plaster,0.91,0.83,0.66,f), trim = mat(0.98,0.94,0.83,f)
        let stone = texMat(.stone,0.70,0.69,0.60,f), roof = roofMat(0.37,0.45,0.54,f)
        let wood = texMat(.planks,0.42,0.32,0.25,f), gold = mat(0.79,0.64,0.32,f)
        let iron = mat(0.35,0.41,0.39,f), green = mat(0.38,0.53,0.34,f)
        let glass = glassMat()
        func framedWindow(_ wall: SCNNode, x: CGFloat, y: CGFloat, w: CGFloat = 0.087, h: CGFloat = 0.153) {
            landmarkArch(wall,x:x,y:y-0.016,z:0.009,w:w+0.040,h:h+0.031,material:trim)
            landmarkArch(wall,x:x,y:y,z:0.022,w:w,h:h,material:glass)
            box(wall,w:0.009,h:h-0.006,l:0.010,x:x,y:y,z:0.035,material:trim,chamfer:0.001)
            box(wall,w:w,h:0.009,l:0.010,x:x,y:y+h*0.43,z:0.035,material:trim,chamfer:0.001)
            box(wall,w:w+0.059,h:0.021,l:0.057,x:x,y:y-0.030,z:0.013,material:stone,chamfer:0.003)
            box(wall,w:0.023,h:0.038,l:0.022,x:x,y:y+h-0.006,z:0.030,material:trim,chamfer:0.003)
        }
        let cx: CGFloat = 0.5
        box(r,w:1.86,h:0.055,l:0.75,x:cx,z:-0.035,material:stone,chamfer:0.022)
        box(r,w:1.59,h:0.60,l:0.45,x:cx,y:0.055,z:-0.045,material:plaster,chamfer:0.007)
        for y: CGFloat in [0.066,0.35,0.645] { box(r,w:1.63,h:0.027,l:0.48,x:cx,y:y,z:-0.045,material:trim,chamfer:0.004) }
        let rangeRoof = SCNNode(); rangeRoof.position = SCNVector3(cx,0,-0.045); r.addChildNode(rangeRoof)
        landmarkRoofTier(rangeRoof,w:1.69,l:0.54,topW:1.43,topL:0.25,h:0.16,y:0.675,material:roof)
        landmarkRoofTier(rangeRoof,w:1.43,l:0.25,topW:1.23,topL:0.035,h:0.085,y:0.835,material:roof)
        // Windows continue around the back, so rotation never exposes a blank facade.
        for face: Float in [-1,1] {
            let wall = SCNNode(); wall.position = SCNVector3(Float(cx),0,-0.045+face*0.225); wall.eulerAngles.y = face > 0 ? 0 : .pi; r.addChildNode(wall)
            for x: CGFloat in [-0.47,-0.29,0.29,0.47] {
                framedWindow(wall,x:x,y:0.15,w:0.086,h:0.143)
                framedWindow(wall,x:x,y:0.43,w:0.086,h:0.146)
            }
        }
        // End pavilions have steep lower roofs and shallow caps, with a dormer in each face.
        for x: CGFloat in [-0.20,1.20] {
            let pavilion = SCNNode(); pavilion.position = SCNVector3(x,0,-0.025); r.addChildNode(pavilion)
            box(pavilion,w:0.367,h:0.73,l:0.57,y:0.055,material:plaster,chamfer:0.006)
            for y: CGFloat in [0.064,0.35,0.765] { box(pavilion,w:0.40,h:0.028,l:0.603,y:y,material:trim,chamfer:0.004) }
            for px: CGFloat in [-0.17,0.17] {
                for pz: CGFloat in [-0.27,0.27] { box(pavilion,w:0.031,h:0.66,l:0.031,x:px,y:0.10,z:pz,material:trim,chamfer:0.003) }
            }
            landmarkRoofTier(pavilion,w:0.44,l:0.64,topW:0.24,topL:0.41,h:0.19,y:0.798,material:roof)
            landmarkRoofTier(pavilion,w:0.24,l:0.41,topW:0.045,topL:0.23,h:0.085,y:0.988,material:roof)
            for side in 0..<4 {
                let wall = SCNNode(); wall.eulerAngles.y = Float(side)*Float.pi/2
                wall.position = side%2 == 0 ? SCNVector3(0,0,side == 0 ? 0.285 : -0.285) : SCNVector3(side == 1 ? 0.1835 : -0.1835,0,0)
                pavilion.addChildNode(wall)
                for y: CGFloat in [0.15,0.46] { framedWindow(wall,x:0,y:y,w:0.098,h:0.183) }
            }
            for face: CGFloat in [-1,1] {
                let dormer = SCNNode(); dormer.position = SCNVector3(0,0,face*0.237); dormer.eulerAngles.y = face > 0 ? 0 : .pi; pavilion.addChildNode(dormer)
                box(dormer,w:0.126,h:0.118,l:0.055,y:0.862,material:trim,chamfer:0.004)
                window(dormer,x:0,y:0.922,z:0.035,w:0.076,h:0.086,material:glass)
                pyramidRoof(dormer,w:0.155,h:0.077,l:0.115,y:0.980,material:roof)
            }
        }
        let centre = SCNNode(); centre.position = SCNVector3(cx,0,0); r.addChildNode(centre)
        box(centre,w:0.43,h:0.87,l:0.585,y:0.055,material:plaster,chamfer:0.006)
        for y: CGFloat in [0.07,0.46,0.887] { box(centre,w:0.47,h:0.035,l:0.623,y:y,material:trim,chamfer:0.004) }
        for x: CGFloat in [-0.194,0.194] {
            for z: CGFloat in [-0.28,0.28] { box(centre,w:0.033,h:0.79,l:0.033,x:x,y:0.103,z:z,material:trim,chamfer:0.003) }
        }
        // The drum conceals the lower hemisphere; a small lantern and finial crown the dome.
        let drum = SCNCylinder(radius:0.215,height:0.075); drum.radialSegmentCount = 16; drum.materials = [trim]
        let drumNode = SCNNode(geometry:drum); drumNode.position.y = 0.941; centre.addChildNode(drumNode)
        let dome = SCNSphere(radius:0.229); dome.segmentCount = 20; dome.materials = [roof]
        let domeNode = SCNNode(geometry:dome); domeNode.position.y = 0.966; domeNode.scale.y = 0.70; centre.addChildNode(domeNode)
        cylinder(centre,r:0.055,h:0.09,y:1.105,material:trim)
        for side in 0..<4 {
            let lantern = SCNNode(); lantern.eulerAngles.y = Float(side)*Float.pi/2; centre.addChildNode(lantern)
            window(lantern,x:0,y:1.151,z:0.053,w:0.03,h:0.049,material:glass)
        }
        let cap = cone(centre,r:0.077,h:0.077,y:1.196,material:roof)
        (cap.geometry as? SCNCone)?.radialSegmentCount = 12
        cylinder(centre,r:0.009,h:0.069,y:1.265,material:gold)
        let ball = SCNSphere(radius:0.017); ball.segmentCount = 10; ball.materials = [gold]
        let ballNode = SCNNode(geometry:ball); ballNode.position.y = 1.332; centre.addChildNode(ballNode)
        let front = SCNNode(); front.position.z = 0.299; centre.addChildNode(front)
        landmarkArch(front,y:0.085,z:0.012,w:0.237,h:0.332,material:stone)
        landmarkArch(front,y:0.089,z:0.027,w:0.184,h:0.293,material:wood)
        box(front,w:0.008,h:0.272,l:0.009,y:0.09,z:0.039,material:gold,chamfer:0.001)
        for x: CGFloat in [-0.035,0.035] { box(front,w:0.009,h:0.034,l:0.013,x:x,y:0.201,z:0.043,material:gold,chamfer:0.002) }
        framedWindow(front,x:0,y:0.556,w:0.141,h:0.236)
        // Four columns hold the balcony; the upper railing leaves the French window visible.
        for x: CGFloat in [-0.168,-0.108,0.108,0.168] {
            cylinder(centre,r:0.020,h:0.325,x:x,y:0.098,z:0.375,material:trim)
            box(centre,w:0.047,h:0.037,l:0.048,x:x,y:0.07,z:0.375,material:stone,chamfer:0.004)
            box(centre,w:0.049,h:0.029,l:0.048,x:x,y:0.413,z:0.375,material:trim,chamfer:0.003)
        }
        box(centre,w:0.413,h:0.036,l:0.163,y:0.443,z:0.35,material:trim,chamfer:0.005)
        for i in -4...4 { box(centre,w:0.012,h:0.087,l:0.012,x:CGFloat(i)*0.043,y:0.479,z:0.417,material:iron,chamfer:0.002) }
        box(centre,w:0.385,h:0.016,l:0.022,y:0.565,z:0.417,material:iron,chamfer:0.003)
        for x: CGFloat in [-0.184,0.184] {
            box(centre,w:0.028,h:0.102,l:0.029,x:x,y:0.476,z:0.414,material:trim,chamfer:0.003)
            box(centre,w:0.016,h:0.016,l:0.135,x:x,y:0.565,z:0.361,material:iron,chamfer:0.002)
        }
        for (w,y,z,l) in [(0.43,0.002,0.413,0.158),(0.37,0.028,0.393,0.135),(0.31,0.054,0.374,0.11)] as [(CGFloat,CGFloat,CGFloat,CGFloat)] {
            box(centre,w:w,h:0.027,l:l,y:y,z:z,material:stone,chamfer:0.006)
        }
        let back = SCNNode(); back.position.z = -0.299; back.eulerAngles.y = .pi; centre.addChildNode(back)
        for y: CGFloat in [0.16,0.55] { framedWindow(back,x:0,y:y,w:0.14,h:0.21) }
        // Two clipped trees and paired chimney stacks make the residence feel cared for.
        for x: CGFloat in [-0.015,1.015] {
            box(r,w:0.111,h:0.073,l:0.11,x:x,y:0.012,z:0.393,material:stone,chamfer:0.012)
            cylinder(r,r:0.011,h:0.105,x:x,y:0.079,z:0.393,material:wood)
            let g = SCNSphere(radius:0.068); g.segmentCount = 12; g.materials = [green]
            let n = SCNNode(geometry:g); n.position = SCNVector3(x,0.197,0.393); n.scale.y = 1.2; r.addChildNode(n)
        }
        for x: CGFloat in [0.15,0.85] {
            box(r,w:0.068,h:0.16,l:0.075,x:x,y:0.79,z:-0.173,material:plaster,chamfer:0.005)
            box(r,w:0.083,h:0.025,l:0.09,x:x,y:0.939,z:-0.173,material:trim,chamfer:0.004)
        }
    }

    /// The town's landmark: a broad civic block with a clock tower rising from the
    /// middle of the front. Many a town-hall tower is the tallest thing in town,
    /// so this one stands close to the cathedral.
    /// A weathered village house: a steep gable, an open porch and a crooked corner turret.
    private static func buildHauntedHouse(_ r: SCNNode, _ f: CGFloat) {
        let boards = facadeMat(.planks,0.49,0.43,0.49,f)
        let trim = mat(0.76,0.70,0.59,f), timber = mat(0.39,0.34,0.31,f)
        let stone = texMat(.stone,0.58,0.58,0.53,f), roof = roofMat(0.31,0.36,0.39,f)
        let shutters = mat(0.41,0.48,0.43,f), metal = mat(0.29,0.32,0.32,f)
        let glass = windowMat()
        box(r,w:0.66,h:0.07,l:0.59,x:-0.045,z:-0.03,material:stone,chamfer:0.012)
        box(r,w:0.60,h:0.68,l:0.51,x:-0.045,y:0.07,z:-0.03,material:boards,chamfer:0.006)
        let house = SCNNode(); house.position = SCNVector3(-0.045,0,-0.03); r.addChildNode(house)
        box(house,w:0.625,h:0.03,l:0.535,y:0.733,material:trim,chamfer:0.005)
        roofShell(house,span:0.60,depth:0.51,rise:0.38,y:0.765,wall:boards,roof:roof)
        for x: CGFloat in [-0.28,0.28] {
            for z: CGFloat in [-0.246,0.246] { box(house,w:0.026,h:0.66,l:0.027,x:x,y:0.075,z:z,material:timber,chamfer:0.003) }
        }
        let front = SCNNode(); front.position.z = 0.226; r.addChildNode(front)
        for x: CGFloat in [-0.195,0.10] {
            shopPane(front,x:x,y:0.572,w:0.102,h:0.193,frame:trim,sill:trim,glass:glass)
            for side: CGFloat in [-1,1] {
                box(front,w:0.027,h:0.205,l:0.016,x:x+side*0.087,y:0.474,z:0.018,material:shutters,chamfer:0.003)
                for y: CGFloat in [0.51,0.55,0.59,0.63] { box(front,w:0.028,h:0.008,l:0.008,x:x+side*0.087,y:y,z:0.03,material:timber,chamfer:0.001) }
            }
        }
        shopPane(front,x:-0.045,y:0.902,w:0.09,h:0.125,frame:trim,sill:trim,glass:glass)
        // The door is offset to keep the porch readable next to the turret.
        box(front,w:0.183,h:0.334,l:0.025,x:-0.08,y:0.07,z:0.007,material:trim,chamfer:0.005)
        box(front,w:0.139,h:0.287,l:0.021,x:-0.08,y:0.083,z:0.028,material:timber,chamfer:0.004)
        window(front,x:-0.08,y:0.316,z:0.042,w:0.085,h:0.057,material:glass)
        box(front,w:0.011,h:0.033,l:0.014,x:-0.035,y:0.218,z:0.045,material:trim,chamfer:0.003)
        shopPane(front,x:-0.27,y:0.27,w:0.074,h:0.106,frame:trim,sill:stone,glass:glass)
        for angle: Float in [-0.30,0.22] {
            let board = box(front,w:0.115,h:0.022,l:0.014,x:-0.27,y:0.251,z:0.062,material:timber,chamfer:0.003)
            board.eulerAngles.z = angle
        }
        box(r,w:0.44,h:0.030,l:0.207,x:-0.068,y:0.031,z:0.333,material:timber,chamfer:0.006)
        box(r,w:0.245,h:0.026,l:0.126,x:-0.08,z:0.391,material:stone,chamfer:0.009)
        for x: CGFloat in [-0.255,0.12] {
            box(r,w:0.029,h:0.329,l:0.034,x:x,y:0.064,z:0.389,material:trim,chamfer:0.004)
            box(r,w:0.047,h:0.036,l:0.046,x:x,y:0.064,z:0.389,material:stone,chamfer:0.004)
        }
        let canopy = box(r,w:0.455,h:0.024,l:0.241,x:-0.068,y:0.410,z:0.333,material:roof,chamfer:0.005)
        canopy.eulerAngles.x = 0.15
        box(r,w:0.46,h:0.025,l:0.028,x:-0.068,y:0.398,z:0.45,material:trim,chamfer:0.003)
        // Faceted turret with a gently leaning spire, kept inside its single tile.
        let tower = SCNNode(); tower.position = SCNVector3(0.255,0,-0.045); r.addChildNode(tower)
        func drum(_ radius: CGFloat, _ height: CGFloat, _ y: CGFloat, _ mat: SCNMaterial) {
            let g = SCNCylinder(radius:radius,height:height); g.radialSegmentCount = 8; g.materials = [mat]
            let n = SCNNode(geometry:g); n.position.y = Float(y+height/2); tower.addChildNode(n)
        }
        drum(0.153,0.075,0,stone); drum(0.133,1.045,0.075,boards)
        drum(0.144,0.032,0.46,trim); drum(0.155,0.043,1.095,trim)
        for side in 0..<4 {
            let wall = SCNNode(); wall.eulerAngles.y = Float(side) * .pi/2; tower.addChildNode(wall)
            let face = SCNNode(); face.position.z = 0.132; wall.addChildNode(face)
            shopPane(face,x:0,y:0.91,w:0.067,h:0.164,frame:trim,sill:trim,glass:glass)
        }
        let spire = SCNNode(); spire.position.y = 1.14; spire.eulerAngles.z = -0.045; tower.addChildNode(spire)
        let cone = SCNCone(topRadius:0,bottomRadius:0.183,height:0.375); cone.radialSegmentCount = 8; cone.materials = [roof]
        let coneNode = SCNNode(geometry:cone); coneNode.position.y = 0.1875; spire.addChildNode(coneNode)
        cylinder(spire,r:0.010,h:0.072,y:0.37,material:metal)
        for side: Float in [-1,1] {
            let wall = SCNNode(); wall.position = SCNVector3(-0.045+side*0.30,0,-0.03); wall.eulerAngles.y = side * .pi/2; r.addChildNode(wall)
            shopPane(wall,x:0.09,y:0.55,w:0.09,h:0.155,frame:trim,sill:stone,glass:glass)
        }
        let rear = SCNNode(); rear.position = SCNVector3(-0.045,0,-0.285); rear.eulerAngles.y = .pi; r.addChildNode(rear)
        shopPane(rear,x:0,y:0.55,w:0.16,h:0.155,frame:trim,sill:stone,glass:glass)
        let chimney = SCNNode(); chimney.position = SCNVector3(-0.225,0.958,-0.165); chimney.eulerAngles.z = 0.10; r.addChildNode(chimney)
        box(chimney,w:0.088,h:0.257,l:0.098,material:stone,chamfer:0.004)
        box(chimney,w:0.116,h:0.030,l:0.124,y:0.25,material:trim,chamfer:0.004)
        let pumpkin = AutumnProps.pumpkin(radius:0.054); pumpkin.position = SCNVector3(-0.27,0.023,0.37); pumpkin.eulerAngles.y = -0.20; r.addChildNode(pumpkin)
        // A small bare tree, restrained to one corner rather than hiding the facade.
        let bark = mat(0.41,0.36,0.29,f)
        let tree = SCNNode(); tree.position = SCNVector3(-0.40,0,-0.05); r.addChildNode(tree)
        AutumnProps.beam(tree,SIMD3(0,0,0),SIMD3(-0.014,0.64,-0.018),radius:0.014,material:bark)
        for (a,b) in [(SIMD3<Float>(0,0.31,0),SIMD3<Float>(-0.052,0.45,0.052)),(SIMD3<Float>(-0.01,0.46,-0.01),SIMD3<Float>(0.040,0.57,-0.12)),(SIMD3<Float>(-0.01,0.54,-0.014),SIMD3<Float>(-0.053,0.63,0.03))] {
            AutumnProps.beam(tree,a,b,radius:0.008,material:bark)
        }
    }

    /// Christmas: gingerbread walls, white icing along the eaves, sweets on the
    /// ridge and candy canes by the door.
    private static func buildGingerbreadHouse(_ r: SCNNode, _ f: CGFloat) {
        let ginger = mat(0.66, 0.40, 0.22, f)
        let roof = mat(0.50, 0.29, 0.16, f)
        let icing = mat(0.98, 0.97, 0.95)
        let glow = mat(1.0, 0.86, 0.48)
        glow.emission.contents = UIColor(red: 1.0, green: 0.78, blue: 0.40, alpha: 1)

        box(r, w: 0.62, h: 0.44, l: 0.52, material: ginger)
        gableRoof(r, ridgeLen: 0.74, span: 0.7, y: 0.44, material: roof)
        // icing: a white band along each eave and the ridge, with drips
        for z in [-0.335, 0.335] as [CGFloat] {
            box(r, w: 0.76, h: 0.035, l: 0.05, y: 0.43, z: z, material: icing, chamfer: 0.015)
        }
        box(r, w: 0.78, h: 0.05, l: 0.07, y: 0.77, material: icing, chamfer: 0.02)
        for x in stride(from: -0.3, through: 0.3, by: 0.15) {
            let drip = SCNSphere(radius: 0.022)
            drip.segmentCount = 8
            drip.materials = [icing]
            let d = SCNNode(geometry: drip)
            d.position = SCNVector3(Float(x), 0.41, 0.34)
            d.scale = SCNVector3(1, 1.4, 1)
            r.addChildNode(d)
        }
        // gumdrops along the ridge
        let sweets = [mat(0.92, 0.28, 0.32), mat(0.36, 0.72, 0.40), mat(0.98, 0.80, 0.26), mat(0.42, 0.56, 0.92)]
        for (i, x) in stride(from: -0.27, through: 0.27, by: 0.135).enumerated() {
            let g = SCNSphere(radius: 0.04)
            g.segmentCount = 10
            g.materials = [sweets[i % sweets.count]]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(Float(x), 0.81, 0)
            n.scale = SCNVector3(1, 0.8, 1)
            r.addChildNode(n)
        }
        // windows with icing frames, warm light inside
        for x in [-0.18, 0.18] as [CGFloat] {
            box(r, w: 0.16, h: 0.18, l: 0.02, x: x, y: 0.15, z: 0.262, material: icing, chamfer: 0.01)
            window(r, x: x, y: 0.24, z: 0.272, w: 0.11, h: 0.13, material: glow)
        }
        box(r, w: 0.17, h: 0.29, l: 0.02, z: 0.262, material: icing, chamfer: 0.01)
        door(r, z: 0.272, w: 0.12, h: 0.24)
        // candy canes either side of the door
        for x in [-0.32, 0.32] as [CGFloat] {
            cylinder(r, r: 0.018, h: 0.3, x: x, z: 0.32, material: icing)
            for y in [0.06, 0.14, 0.22] as [CGFloat] {
                cylinder(r, r: 0.02, h: 0.03, x: x, y: y, z: 0.32, material: sweets[0])
            }
            let hook = SCNTorus(ringRadius: 0.04, pipeRadius: 0.017)
            hook.materials = [sweets[0]]
            let hk = SCNNode(geometry: hook)
            hk.position = SCNVector3(Float(x) + 0.04, 0.3, 0.32)
            hk.eulerAngles.x = .pi / 2
            r.addChildNode(hk)
        }
        box(r, w: 0.08, h: 0.2, l: 0.08, x: -0.18, y: 0.6, z: -0.1, material: ginger)
        box(r, w: 0.1, h: 0.03, l: 0.1, x: -0.18, y: 0.8, z: -0.1, material: icing, chamfer: 0.012)
        smoke(r, x: -0.18, y: 0.86, z: -0.1)
    }

    private static func buildTownhall(_ r: SCNNode, _ f: CGFloat) {
        let body = facadeMat(.plaster, 0.86, 0.80, 0.68, f)
        let trim = mat(0.95, 0.91, 0.81, f)
        let stone = texMat(.stone, 0.64, 0.61, 0.54, f)
        let timber = mat(0.47, 0.37, 0.28, f)
        let roof = roofMat(0.39, 0.56, 0.49, f)
        let glass = glassMat()
        let gold = mat(0.76, 0.62, 0.37, f)
        box(r, w: 0.87, h: 0.07, l: 0.65, z: -0.025, material: stone, chamfer: 0.015)
        box(r, w: 0.83, h: 0.665, l: 0.60, y: 0.07, z: -0.025, material: body, chamfer: 0.006)
        box(r, w: 0.855, h: 0.03, l: 0.624, y: 0.38, z: -0.025, material: trim, chamfer: 0.004)
        box(r, w: 0.87, h: 0.034, l: 0.64, y: 0.726, z: -0.025, material: trim, chamfer: 0.005)
        pyramidRoof(r, w: 0.93, h: 0.25, l: 0.69, y: 0.76, z: -0.025, material: roof)
        for x: CGFloat in [-0.395, 0.395] {
            for z: CGFloat in [-0.31, 0.26] {
                box(r, w: 0.032, h: 0.65, l: 0.032, x: x, y: 0.075, z: z, material: trim, chamfer: 0.003)
            }
        }
        for face: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position.z = face > 0 ? 0.275 : -0.325
            wall.eulerAngles.y = face > 0 ? 0 : .pi
            r.addChildNode(wall)
            let positions: [CGFloat] = face > 0 ? [-0.278, 0.278] : [-0.278, 0, 0.278]
            for x in positions {
                for y: CGFloat in [0.25, 0.555] {
                    shopPane(wall, x: x, y: y, w: 0.106, h: 0.177, frame: trim, sill: trim, glass: glass)
                }
            }
        }
        for side: Float in [-1, 1] {
            let wall = SCNNode()
            wall.position = SCNVector3(side * 0.415, 0, -0.025)
            wall.eulerAngles.y = side * .pi / 2
            r.addChildNode(wall)
            for x: CGFloat in [-0.145, 0.145] {
                for y: CGFloat in [0.25, 0.555] {
                    shopPane(wall, x: x, y: y, w: 0.105, h: 0.177, frame: trim, sill: trim, glass: glass)
                }
            }
        }

        let tower = SCNNode()
        tower.position.z = 0.20
        r.addChildNode(tower)
        box(tower, w: 0.285, h: 1.29, l: 0.28, y: 0.07, material: trim, chamfer: 0.005)
        for x: CGFloat in [-0.131, 0.131] {
            for z: CGFloat in [-0.129, 0.129] {
                box(tower, w: 0.019, h: 1.24, l: 0.019, x: x, y: 0.09, z: z, material: body, chamfer: 0.002)
            }
        }
        box(tower, w: 0.313, h: 0.031, l: 0.31, y: 1.012, material: body, chamfer: 0.004)
        box(tower, w: 0.33, h: 0.041, l: 0.326, y: 1.36, material: stone, chamfer: 0.006)
        box(tower, w: 0.206, h: 0.328, l: 0.026, y: 0.075, z: 0.149, material: timber, chamfer: 0.006)
        box(tower, w: 0.154, h: 0.282, l: 0.021, y: 0.083, z: 0.169, material: doorMat, chamfer: 0.005)
        box(tower, w: 0.011, h: 0.28, l: 0.011, y: 0.084, z: 0.185, material: gold, chamfer: 0.002)
        box(r, w: 0.36, h: 0.035, l: 0.16, z: 0.389, material: stone, chamfer: 0.01)
        box(r, w: 0.30, h: 0.037, l: 0.12, y: 0.035, z: 0.374, material: stone, chamfer: 0.009)
        let front = SCNNode()
        front.position.z = 0.14
        tower.addChildNode(front)
        shopPane(front, x: 0, y: 0.633, w: 0.116, h: 0.213, frame: timber, sill: trim, glass: glass)
        box(tower, w: 0.232, h: 0.03, l: 0.117, y: 0.482, z: 0.18, material: stone, chamfer: 0.005)
        for x: CGFloat in [-0.095, -0.032, 0.032, 0.095] {
            box(tower, w: 0.014, h: 0.084, l: 0.014, x: x, y: 0.512, z: 0.231, material: trim, chamfer: 0.002)
        }
        box(tower, w: 0.233, h: 0.018, l: 0.022, y: 0.59, z: 0.231, material: trim, chamfer: 0.003)
        for side: CGFloat in [-1, 1] {
            box(tower, w: 0.017, h: 0.018, l: 0.09, x: side * 0.103, y: 0.59, z: 0.188, material: trim, chamfer: 0.003)
        }
        // A restrained civic banner below the clock gives the pale tower a focal point.
        box(tower, w: 0.061, h: 0.15, l: 0.012, y: 0.811, z: 0.15, material: mat(0.73, 0.40, 0.33, f), chamfer: 0.004)
        box(tower, w: 0.033, h: 0.035, l: 0.009, y: 0.884, z: 0.161, material: gold, chamfer: 0.003)

        // Local clock plane faces +Z. Rotating the whole group puts hands on every side.
        for i in 0..<4 {
            let angle = Float(i) * .pi / 2
            let clock = SCNNode()
            clock.position = SCNVector3(sin(angle) * 0.149, 1.176, cos(angle) * 0.149)
            clock.eulerAngles.y = angle
            tower.addChildNode(clock)
            for (radius, depth, z, material) in [(CGFloat(0.094), CGFloat(0.018), Float(0), gold), (0.079, 0.01, 0.014, trim)] {
                let cylinder = SCNCylinder(radius: radius, height: depth)
                cylinder.radialSegmentCount = 24
                cylinder.materials = [material]
                let face = SCNNode(geometry: cylinder)
                face.position.z = z
                face.eulerAngles.x = .pi / 2
                clock.addChildNode(face)
            }
            for tick in 0..<4 {
                let a = CGFloat(tick) * .pi / 2
                let mark = box(clock, w: 0.008, h: 0.016, l: 0.006,
                               x: sin(a) * 0.06, y: cos(a) * 0.06 - 0.008, z: 0.023, material: timber, chamfer: 0.001)
                mark.eulerAngles.z = Float(-a)
            }
            for (dx, dy) in [(CGFloat(-0.026), CGFloat(0.027)), (0.033, 0.039)] {
                let hand = SCNBox(width: sqrt(dx * dx + dy * dy), height: 0.008, length: 0.007, chamferRadius: 0.002)
                hand.materials = [timber]
                let n = SCNNode(geometry: hand)
                n.position = SCNVector3(dx / 2, dy / 2, 0.026)
                n.eulerAngles.z = Float(atan2(dy, dx))
                clock.addChildNode(n)
            }
        }
        for x: CGFloat in [-0.122, 0.122] {
            for z: CGFloat in [-0.12, 0.12] {
                box(tower, w: 0.027, h: 0.193, l: 0.027, x: x, y: 1.401, z: z, material: trim, chamfer: 0.003)
            }
        }
        box(tower, w: 0.294, h: 0.025, l: 0.29, y: 1.576, material: trim, chamfer: 0.004)
        pyramidRoof(tower, w: 0.375, h: 0.26, l: 0.37, y: 1.60, material: roof)
        cylinder(tower, r: 0.008, h: 0.119, y: 1.856, material: gold)
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0.106, y: 0))
        path.addLine(to: CGPoint(x: 0.084, y: 0.03))
        path.addLine(to: CGPoint(x: 0.106, y: 0.06))
        path.addLine(to: CGPoint(x: 0, y: 0.06))
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.007)
        shape.materials = [mat(0.77, 0.40, 0.32, f)]
        let flag = SCNNode(geometry: shape)
        flag.position = SCNVector3(0.011, 1.904, 0)
        tower.addChildNode(flag)
    }

    /// A village church with a plaster nave, arched glazing and an open bell chamber.
    private static func buildChurch(_ r: SCNNode, _ f: CGFloat) {
        let plaster = facadeMat(.plaster, 0.91, 0.87, 0.76, f)
        let trim = mat(0.96, 0.92, 0.82, f)
        let stone = texMat(.stone, 0.65, 0.63, 0.55, f)
        let roof = roofMat(0.37, 0.47, 0.56, f)
        let wood = mat(0.43, 0.34, 0.26, f)
        let gold = mat(0.79, 0.65, 0.35, f)
        let glass = glassMat()
        func arch(_ parent: SCNNode, x: CGFloat = 0, y: CGFloat, z: CGFloat,
                  w: CGFloat, h: CGFloat, material: SCNMaterial) {
            let p = UIBezierPath()
            p.move(to: CGPoint(x: -w/2, y: 0)); p.addLine(to: CGPoint(x: w/2, y: 0))
            p.addLine(to: CGPoint(x: w/2, y: h-w/2))
            let radius = w/2, k = radius * 0.55228475
            p.addCurve(to: CGPoint(x: 0, y: h),
                       controlPoint1: CGPoint(x: radius, y: h-radius+k),
                       controlPoint2: CGPoint(x: k, y: h))
            p.addCurve(to: CGPoint(x: -radius, y: h-radius),
                       controlPoint1: CGPoint(x: -k, y: h),
                       controlPoint2: CGPoint(x: -radius, y: h-radius+k))
            p.close(); p.flatness = 0.002
            let geometry = SCNShape(path: p, extrusionDepth: 0.018)
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry); node.position = SCNVector3(x,y,z)
            parent.addChildNode(node)
        }
        func archedWindow(_ wall: SCNNode, x: CGFloat = 0, y: CGFloat, w: CGFloat, h: CGFloat) {
            arch(wall, x: x, y: y-0.021, z: 0.012, w: w+0.048, h: h+0.043, material: trim)
            arch(wall, x: x, y: y, z: 0.029, w: w, h: h, material: glass)
            box(wall, w: 0.011, h: h-0.018, l: 0.012, x: x, y: y, z: 0.044, material: trim, chamfer: 0.002)
            box(wall, w: w, h: 0.011, l: 0.012, x: x, y: y+h*0.43, z: 0.044, material: trim, chamfer: 0.002)
            box(wall, w: w+0.073, h: 0.025, l: 0.065, x: x, y: y-0.038, z: 0.021, material: stone, chamfer: 0.004)
        }
        let nave = SCNNode(); nave.position = SCNVector3(0.12,0,-0.015); r.addChildNode(nave)
        box(nave, w: 0.55, h: 0.065, l: 0.79, material: stone, chamfer: 0.014)
        box(nave, w: 0.50, h: 0.52, l: 0.74, y: 0.065, material: plaster, chamfer: 0.005)
        box(nave, w: 0.532, h: 0.032, l: 0.772, y: 0.565, material: trim, chamfer: 0.004)
        roofShell(nave, span: 0.50, depth: 0.74, rise: 0.32, y: 0.597, wall: plaster, roof: roof)
        for side: Float in [-1,1] {
            let wall = SCNNode(); wall.position.x = side*0.25; wall.eulerAngles.y = side * .pi/2
            nave.addChildNode(wall)
            for x: CGFloat in [-0.235,0,0.235] {
                archedWindow(wall, x: x, y: 0.245, w: 0.087, h: 0.235)
            }
            for x: CGFloat in [-0.355,0.355] {
                box(wall, w: 0.048, h: 0.43, l: 0.054, x: x, y: 0.065, z: 0.016, material: trim, chamfer: 0.005)
                box(wall, w: 0.066, h: 0.045, l: 0.077, x: x, y: 0.065, z: 0.022, material: stone, chamfer: 0.005)
            }
        }
        for face: Float in [-1,1] {
            let wall = SCNNode(); wall.position.z = face*0.37; wall.eulerAngles.y = face > 0 ? 0 : .pi
            nave.addChildNode(wall)
            archedWindow(wall, y: 0.235, w: 0.125, h: 0.25)
            // A small rose in each gable; glazing retains the shared night-light tag.
            for (radius,z,material) in [(CGFloat(0.080),Float(0.012),trim),(0.059,0.028,glass)] {
                let disc = SCNCylinder(radius: radius,height: 0.014); disc.radialSegmentCount = 16; disc.materials = [material]
                let node = SCNNode(geometry:disc); node.position = SCNVector3(0,0.686,z); node.eulerAngles.x = .pi/2
                wall.addChildNode(node)
            }
            for angle: Float in [0,.pi/2] {
                let bar = box(wall,w:0.010,h:0.115,l:0.012,y:0.628,z:0.04,material:trim,chamfer:0.002)
                bar.eulerAngles.z = angle
            }
        }
        let tower = SCNNode(); tower.position = SCNVector3(-0.24,0,0.13); r.addChildNode(tower)
        box(tower,w:0.35,h:0.075,l:0.37,material:stone,chamfer:0.014)
        box(tower,w:0.30,h:0.81,l:0.32,y:0.075,material:plaster,chamfer:0.005)
        for x: CGFloat in [-0.139,0.139] {
            for z: CGFloat in [-0.149,0.149] {
                box(tower,w:0.025,h:0.77,l:0.025,x:x,y:0.08,z:z,material:trim,chamfer:0.003)
            }
        }
        let front = SCNNode(); front.position.z = 0.16; tower.addChildNode(front)
        arch(front,y:0.069,z:0.013,w:0.235,h:0.365,material:stone)
        arch(front,y:0.079,z:0.030,w:0.171,h:0.315,material:wood)
        box(front,w:0.009,h:0.295,l:0.012,y:0.08,z:0.044,material:trim,chamfer:0.002)
        for x: CGFloat in [-0.027,0.027] {
            box(front,w:0.009,h:0.032,l:0.012,x:x,y:0.205,z:0.048,material:gold,chamfer:0.003)
        }
        archedWindow(front,y:0.565,w:0.075,h:0.155)
        for side: Float in [-1,1] {
            let wall = SCNNode(); wall.position.x = side*0.15; wall.eulerAngles.y = side * .pi/2
            tower.addChildNode(wall); archedWindow(wall,y:0.565,w:0.075,h:0.155)
        }
        box(r,w:0.285,h:0.035,l:0.175,x:-0.24,z:0.352,material:stone,chamfer:0.01)
        box(r,w:0.235,h:0.039,l:0.13,x:-0.24,y:0.035,z:0.333,material:stone,chamfer:0.008)
        box(tower,w:0.346,h:0.043,l:0.366,y:0.867,material:stone,chamfer:0.006)
        // Open on all four sides, with a real suspended bell under the spire.
        for x: CGFloat in [-0.127,0.127] {
            for z: CGFloat in [-0.137,0.137] {
                box(tower,w:0.043,h:0.25,l:0.043,x:x,y:0.91,z:z,material:trim,chamfer:0.004)
            }
        }
        box(tower,w:0.31,h:0.027,l:0.31,y:1.113,material:wood,chamfer:0.004)
        cylinder(tower,r:0.011,h:0.08,y:1.046,material:wood)
        let bell = SCNCone(topRadius:0.025,bottomRadius:0.061,height:0.083)
        bell.radialSegmentCount = 12; bell.materials = [gold]
        let bellNode = SCNNode(geometry:bell); bellNode.position.y = 1.027; tower.addChildNode(bellNode)
        cylinder(tower,r:0.066,h:0.013,y:0.977,material:gold)
        let clapper = SCNSphere(radius:0.013); clapper.segmentCount = 8; clapper.materials = [wood]
        let clapperNode = SCNNode(geometry:clapper); clapperNode.position.y = 0.969; tower.addChildNode(clapperNode)
        box(tower,w:0.365,h:0.04,l:0.385,y:1.15,material:trim,chamfer:0.006)
        let spire = SCNCone(topRadius:0,bottomRadius:0.213,height:0.43)
        spire.radialSegmentCount = 8; spire.materials = [roof]
        let spireNode = SCNNode(geometry:spire); spireNode.position.y = 1.405; tower.addChildNode(spireNode)
        cylinder(tower,r:0.020,h:0.025,y:1.612,material:gold)
        box(tower,w:0.015,h:0.13,l:0.015,y:1.631,material:gold,chamfer:0.002)
        box(tower,w:0.084,h:0.014,l:0.015,y:1.710,material:gold,chamfer:0.002)
    }

    // MARK: Landmark masonry and roof details

    /// A shallow opening in the local XY wall plane, with a rounded or pointed crown.
    private static func landmarkArch(_ parent: SCNNode, x: CGFloat = 0, y: CGFloat,
                                     z: CGFloat, w: CGFloat, h: CGFloat,
                                     pointed: Bool = false, material: SCNMaterial) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -w/2, y: 0)); path.addLine(to: CGPoint(x: w/2, y: 0))
        if pointed {
            let shoulder = h * 0.62
            path.addLine(to: CGPoint(x: w/2, y: shoulder))
            for i in 1...8 {
                let t = CGFloat(i)/8, u = 1-t
                path.addLine(to: CGPoint(x: u*u*w/2 + 2*u*t*w*0.46,
                                        y: u*u*shoulder + 2*u*t*h*0.88 + t*t*h))
            }
            for i in 1...8 {
                let t = CGFloat(i)/8, u = 1-t
                path.addLine(to: CGPoint(x: -2*u*t*w*0.46 - t*t*w/2,
                                        y: u*u*h + 2*u*t*h*0.88 + t*t*shoulder))
            }
        } else {
            let radius = w/2, shoulder = h-radius
            path.addLine(to: CGPoint(x: radius, y: shoulder))
            for i in 1...12 {
                let a = CGFloat(i)*CGFloat.pi/12
                path.addLine(to: CGPoint(x: cos(a)*radius, y: shoulder+sin(a)*radius))
            }
        }
        path.close()
        let geometry = SCNShape(path: path, extrusionDepth: 0.012)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.position = SCNVector3(x,y,z)
        parent.addChildNode(node)
    }

    private static func landmarkBeam(_ parent: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>,
                                     width: CGFloat, depth: CGFloat, material: SCNMaterial) {
        let delta = b-a
        let geometry = SCNBox(width: width, height: CGFloat(simd_length(delta)), length: depth, chamferRadius: 0.002)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.simdPosition = (a+b)/2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: simd_normalize(delta))
        parent.addChildNode(node)
    }

    /// Four sloping faces with independent normals: a crisp, closed mansard tier.
    private static func landmarkRoofTier(_ parent: SCNNode, w: CGFloat, l: CGFloat,
                                         topW: CGFloat, topL: CGFloat, h: CGFloat, y: CGFloat,
                                         material: SCNMaterial) {
        let lower = [SIMD3<Float>(Float(-w/2),0,Float(l/2)), SIMD3<Float>(Float(w/2),0,Float(l/2)),
                     SIMD3<Float>(Float(w/2),0,Float(-l/2)), SIMD3<Float>(Float(-w/2),0,Float(-l/2))]
        let upper = [SIMD3<Float>(Float(-topW/2),Float(h),Float(topL/2)), SIMD3<Float>(Float(topW/2),Float(h),Float(topL/2)),
                     SIMD3<Float>(Float(topW/2),Float(h),Float(-topL/2)), SIMD3<Float>(Float(-topW/2),Float(h),Float(-topL/2))]
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        func face(_ points: [SIMD3<Float>]) {
            let normal = simd_normalize(simd_cross(points[1]-points[0], points[2]-points[0]))
            let start = Int32(vertices.count)
            vertices += points.map { SCNVector3($0.x,$0.y,$0.z) }
            normals += Array(repeating: SCNVector3(normal.x,normal.y,normal.z), count: 4)
            indices += [start,start+1,start+2,start,start+2,start+3]
        }
        for i in 0..<4 { let j = (i+1)%4; face([lower[i],lower[j],upper[j],upper[i]]) }
        face([upper[0],upper[1],upper[2],upper[3]])
        face([lower[3],lower[2],lower[1],lower[0]])
        let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals)],
                                  elements: [.init(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.position.y = Float(y); parent.addChildNode(node)
    }

    /// A low, defensive courtyard fortress with open battlements and a timber gatehouse.
    private static func buildFortress(_ r: SCNNode, _ f: CGFloat) {
        let stone = facadeMat(.stone,0.66,0.65,0.57,f), trim = mat(0.79,0.76,0.65,f)
        let base = texMat(.stone,0.54,0.56,0.50,f), dark = mat(0.27,0.31,0.29,f)
        let timber = texMat(.planks,0.44,0.34,0.25,f), iron = mat(0.30,0.34,0.34,f)
        let roof = roofMat(0.40,0.48,0.43,f), banner = mat(0.66,0.36,0.29,f), brass = mat(0.77,0.63,0.35,f)
        let glass = glassMat()
        box(r,w:0.96,h:0.055,l:0.96,material:base,chamfer:0.025)
        box(r,w:0.66,h:0.025,l:0.66,y:0.055,material:mat(0.71,0.68,0.57,f),chamfer:0.007)
        // Separate walls leave a visible courtyard. The gate opening is built around, not painted on.
        for side in 0..<4 {
            let wall = SCNNode(); wall.eulerAngles.y = Float(side)*Float.pi/2; r.addChildNode(wall)
            if side == 0 {
                for x: CGFloat in [-0.235,0.235] {
                    box(wall,w:0.20,h:0.405,l:0.095,x:x,y:0.055,z:0.32,material:stone,chamfer:0.006)
                }
                box(wall,w:0.29,h:0.12,l:0.095,y:0.345,z:0.32,material:stone,chamfer:0.005)
            } else {
                box(wall,w:0.68,h:0.405,l:0.095,y:0.055,z:0.32,material:stone,chamfer:0.006)
                for x: CGFloat in [-0.15,0.15] {
                    box(wall,w:0.027,h:0.115,l:0.010,x:x,y:0.225,z:0.373,material:dark,chamfer:0.003)
                    box(wall,w:0.064,h:0.017,l:0.013,x:x,y:0.280,z:0.377,material:dark,chamfer:0.002)
                }
            }
            box(wall,w:0.66,h:0.03,l:0.14,y:0.447,z:0.30,material:trim,chamfer:0.005)
            for i in -3...3 {
                let x = CGFloat(i)*0.09
                box(wall,w:0.054,h:0.09,l:0.079,x:x,y:0.477,z:0.333,material:stone,chamfer:0.004)
                box(wall,w:0.062,h:0.015,l:0.089,x:x,y:0.556,z:0.333,material:trim,chamfer:0.003)
            }
        }
        for x: CGFloat in [-0.326,0.326] {
            for z: CGFloat in [-0.326,0.326] {
                let tower = SCNNode(); tower.position = SCNVector3(x,0,z); r.addChildNode(tower)
                let h: CGFloat = z > 0 ? 0.66 : 0.77
                func drum(_ radius: CGFloat, _ height: CGFloat, _ bottom: CGFloat, _ material: SCNMaterial) {
                    let g = SCNCylinder(radius:radius,height:height); g.radialSegmentCount = 12; g.materials = [material]
                    let n = SCNNode(geometry:g); n.position.y = Float(bottom+height/2); tower.addChildNode(n)
                }
                drum(0.143,0.10,0.045,base); drum(0.121,h-0.14,0.14,stone)
                drum(0.128,0.025,0.32,trim); drum(0.137,0.043,h-0.02,trim)
                // Recessed dark stone floor inside the crown; individual merlons reveal the opening.
                drum(0.121,0.012,h+0.022,dark)
                for i in 0..<8 {
                    let angle = CGFloat(i)*CGFloat.pi/4
                    let block = box(tower,w:0.065,h:0.083,l:0.043,x:sin(angle)*0.115,y:h+0.024,z:cos(angle)*0.115,material:stone,chamfer:0.004)
                    block.eulerAngles.y = Float(angle)
                    let cap = box(tower,w:0.070,h:0.013,l:0.049,x:sin(angle)*0.115,y:h+0.099,z:cos(angle)*0.115,material:trim,chamfer:0.003)
                    cap.eulerAngles.y = Float(angle)
                }
                for side in 0..<4 {
                    let wall = SCNNode(); wall.eulerAngles.y = Float(side)*Float.pi/2; tower.addChildNode(wall)
                    landmarkArch(wall,y:h-0.25,z:0.118,w:0.045,h:0.135,material:dark)
                    landmarkArch(wall,y:h-0.238,z:0.126,w:0.021,h:0.108,material:glass)
                }
            }
        }
        // Rear barracks give the otherwise open courtyard a warm, inhabited focal point.
        let hall = SCNNode(); hall.position = SCNVector3(0,0,-0.15); r.addChildNode(hall)
        box(hall,w:0.35,h:0.57,l:0.25,y:0.08,material:stone,chamfer:0.007)
        box(hall,w:0.378,h:0.035,l:0.278,y:0.63,material:timber,chamfer:0.004)
        roofShell(hall,span:0.35,depth:0.25,rise:0.23,y:0.665,wall:stone,roof:roof)
        for x: CGFloat in [-0.095,0.095] {
            landmarkArch(hall,x:x,y:0.385,z:0.136,w:0.09,h:0.17,material:trim)
            landmarkArch(hall,x:x,y:0.402,z:0.148,w:0.058,h:0.135,material:glass)
        }
        box(hall,w:0.09,h:0.21,l:0.016,y:0.08,z:0.14,material:timber,chamfer:0.004)
        // Oak double gate and pale voussoirs, with the raised iron grille above.
        landmarkArch(r,y:0.057,z:0.380,w:0.286,h:0.36,material:trim)
        landmarkArch(r,y:0.060,z:0.391,w:0.225,h:0.31,material:dark)
        landmarkArch(r,y:0.067,z:0.403,w:0.193,h:0.277,material:timber)
        for x: CGFloat in [-0.069,-0.034,0,0.034,0.069] {
            box(r,w:0.006,h:0.209,l:0.009,x:x,y:0.068,z:0.414,material:dark,chamfer:0.001)
        }
        for y: CGFloat in [0.13,0.245] { box(r,w:0.187,h:0.019,l:0.012,y:y,z:0.420,material:iron,chamfer:0.002) }
        for x: CGFloat in [-0.070,0,0.070] { box(r,w:0.009,h:0.051,l:0.01,x:x,y:0.317,z:0.405,material:iron,chamfer:0.001) }
        box(r,w:0.235,h:0.034,l:0.124,y:0.006,z:0.43,material:base,chamfer:0.007)
        box(r,w:0.22,h:0.025,l:0.093,y:0.04,z:0.425,material:trim,chamfer:0.005)
        for x: CGFloat in [-0.19,0.19] {
            box(r,w:0.06,h:0.17,l:0.014,x:x,y:0.244,z:0.38,material:banner,chamfer:0.003)
            box(r,w:0.074,h:0.012,l:0.025,x:x,y:0.408,z:0.384,material:brass,chamfer:0.002)
        }
        cylinder(hall,r:0.008,h:0.22,y:0.885,material:brass)
        let flag = UIBezierPath(); flag.move(to:.zero); flag.addLine(to:CGPoint(x:0.15,y:-0.012)); flag.addLine(to:CGPoint(x:0.12,y:-0.045)); flag.addLine(to:CGPoint(x:0.15,y:-0.084)); flag.addLine(to:CGPoint(x:0,y:-0.077)); flag.close()
        let g = SCNShape(path:flag,extrusionDepth:0.006); g.materials = [banner]
        let n = SCNNode(geometry:g); n.position = SCNVector3(0.008,1.087,0); hall.addChildNode(n)
        // Small stacked stores remain below the wall line.
        for (x,z) in [(0.17,0.02),(0.19,0.12)] as [(CGFloat,CGFloat)] {
            box(r,w:0.085,h:0.08,l:0.075,x:x,y:0.08,z:z,material:timber,chamfer:0.004)
            box(r,w:0.092,h:0.012,l:0.08,x:x,y:0.148,z:z,material:trim,chamfer:0.002)
        }
    }

    /// Sandstone Gothic silhouette: twin open belfries, tracery and flying buttresses.
    private static func buildCathedral(_ r: SCNNode, _ f: CGFloat) {
        let stone = facadeMat(.stone,0.83,0.79,0.68,f), trim = mat(0.95,0.90,0.77,f)
        let base = texMat(.stone,0.66,0.65,0.57,f), shadow = mat(0.32,0.37,0.37,f)
        let roof = roofMat(0.34,0.46,0.53,f), gold = mat(0.79,0.65,0.34,f)
        let wood = texMat(.planks,0.43,0.32,0.26,f)
        let glass = glassMat()
        func lancet(_ wall: SCNNode, x: CGFloat = 0, y: CGFloat, z: CGFloat = 0.012,
                    w: CGFloat, h: CGFloat) {
            landmarkArch(wall,x:x,y:y-0.018,z:z,w:w+0.034,h:h+0.036,pointed:true,material:trim)
            landmarkArch(wall,x:x,y:y,z:z+0.013,w:w,h:h,pointed:true,material:glass)
            box(wall,w:0.009,h:h*0.83,l:0.010,x:x,y:y,z:z+0.025,material:trim,chamfer:0.001)
            box(wall,w:w,h:0.01,l:0.010,x:x,y:y+h*0.40,z:z+0.025,material:trim,chamfer:0.001)
            box(wall,w:w+0.05,h:0.019,l:0.043,x:x,y:y-0.035,z:z+0.013,material:base,chamfer:0.003)
        }
        box(r,w:0.91,h:0.052,l:0.90,z:-0.005,material:base,chamfer:0.018)
        let nave = SCNNode(); nave.position.z = -0.063; r.addChildNode(nave)
        box(nave,w:0.49,h:0.94,l:0.70,y:0.052,material:stone,chamfer:0.006)
        box(nave,w:0.528,h:0.035,l:0.723,y:0.959,material:trim,chamfer:0.004)
        roofShell(nave,span:0.49,depth:0.70,rise:0.34,y:0.996,wall:stone,roof:roof)
        // Narrow side aisles, with visible buttresses lifting toward the nave.
        for side: CGFloat in [-1,1] {
            box(nave,w:0.12,h:0.40,l:0.57,x:side*0.291,y:0.055,z:-0.035,material:stone,chamfer:0.005)
            let slope = box(nave,w:0.163,h:0.025,l:0.62,x:side*0.294,y:0.46,z:-0.035,material:roof,chamfer:0.003)
            slope.eulerAngles.z = Float(-side*0.43)
            let wall = SCNNode(); wall.position.x = Float(side*0.245); wall.eulerAngles.y = Float(side)*Float.pi/2; nave.addChildNode(wall)
            for x: CGFloat in [-0.23,-0.03,0.17] { lancet(wall,x:x,y:0.63,w:0.075,h:0.25) }
            for z: CGFloat in [-0.295,-0.09,0.115] {
                box(nave,w:0.065,h:0.55,l:0.068,x:side*0.379,y:0.052,z:z,material:stone,chamfer:0.004)
                box(nave,w:0.09,h:0.054,l:0.09,x:side*0.379,y:0.053,z:z,material:base,chamfer:0.004)
                landmarkBeam(nave,from:SIMD3(Float(side*0.26),0.83,Float(z)),to:SIMD3(Float(side*0.379),0.58,Float(z)),width:0.041,depth:0.055,material:trim)
                pyramidRoof(nave,w:0.079,h:0.11,l:0.079,x:side*0.379,y:0.60,z:z,material:trim)
            }
        }
        let rear = SCNNode(); rear.position.z = -0.35; rear.eulerAngles.y = .pi; nave.addChildNode(rear)
        lancet(rear,y:0.48,w:0.135,h:0.36)
        // A projecting central entrance gives the steps a clear destination.
        box(r,w:0.335,h:0.89,l:0.128,y:0.052,z:0.318,material:stone,chamfer:0.006)
        box(r,w:0.363,h:0.029,l:0.15,y:0.91,z:0.318,material:trim,chamfer:0.004)
        let pediment = SCNNode(); pediment.position.z = 0.318; r.addChildNode(pediment)
        roofShell(pediment,span:0.334,depth:0.125,rise:0.16,y:0.939,wall:stone,roof:roof)
        landmarkArch(r,y:0.06,z:0.390,w:0.298,h:0.493,pointed:true,material:trim)
        landmarkArch(r,y:0.067,z:0.404,w:0.251,h:0.436,pointed:true,material:base)
        landmarkArch(r,y:0.076,z:0.418,w:0.211,h:0.388,pointed:true,material:wood)
        for x: CGFloat in [-0.071,-0.035,0,0.035,0.071] {
            box(r,w:0.005,h:0.265,l:0.009,x:x,y:0.081,z:0.430,material:shadow,chamfer:0.001)
        }
        for y: CGFloat in [0.153,0.30] { box(r,w:0.19,h:0.012,l:0.012,y:y,z:0.435,material:gold,chamfer:0.002) }
        box(r,w:0.30,h:0.025,l:0.136,y:0.002,z:0.419,material:base,chamfer:0.008)
        box(r,w:0.263,h:0.027,l:0.101,y:0.027,z:0.415,material:trim,chamfer:0.005)
        box(r,w:0.226,h:0.024,l:0.075,y:0.054,z:0.409,material:trim,chamfer:0.004)
        // Stained rose: colored radial panes, a pale rim and eight stone spokes.
        func disc(_ radius: CGFloat, _ z: CGFloat, _ material: SCNMaterial) {
            let g = SCNCylinder(radius:radius,height:0.013); g.radialSegmentCount = 32; g.materials = [material]
            let n = SCNNode(geometry:g); n.position = SCNVector3(0,0.729,z); n.eulerAngles.x = .pi/2; r.addChildNode(n)
        }
        disc(0.133,0.393,base); disc(0.116,0.405,trim); disc(0.100,0.416,shadow)
        let colors: [(CGFloat,CGFloat,CGFloat)] = [(0.49,0.69,0.75),(0.81,0.65,0.39),(0.63,0.57,0.70)]
        for i in 0..<8 {
            let c = colors[i%3], pane = mat(c.0,c.1,c.2)
            pane.name = BuildingNightLighting.windowMaterialName
            let path = UIBezierPath(); path.move(to:.zero)
            for j in 0...4 {
                let angle = (CGFloat(i)+CGFloat(j)/4)*CGFloat.pi/4
                path.addLine(to:CGPoint(x:cos(angle)*0.095,y:sin(angle)*0.095))
            }
            path.close()
            let g = SCNShape(path:path,extrusionDepth:0.008); g.materials = [pane]
            let n = SCNNode(geometry:g); n.position = SCNVector3(0,0.729,0.427); r.addChildNode(n)
            let a = Float(i)*Float.pi/4
            landmarkBeam(r,from:SIMD3(0,0.729,0.439),to:SIMD3(cos(a)*0.099,0.729+sin(a)*0.099,0.439),width:0.009,depth:0.01,material:trim)
        }
        disc(0.024,0.446,trim); disc(0.014,0.455,glass)
        for x: CGFloat in [-0.299,0.299] {
            let tower = SCNNode(); tower.position = SCNVector3(x,0,0.275); r.addChildNode(tower)
            box(tower,w:0.258,h:0.082,l:0.273,y:0.045,material:base,chamfer:0.009)
            box(tower,w:0.222,h:1.18,l:0.23,y:0.105,material:stone,chamfer:0.005)
            for px: CGFloat in [-0.099,0.099] {
                for pz: CGFloat in [-0.103,0.103] { box(tower,w:0.023,h:1.12,l:0.024,x:px,y:0.13,z:pz,material:trim,chamfer:0.003) }
            }
            for y: CGFloat in [0.54,0.91,1.266] { box(tower,w:0.248,h:0.025,l:0.258,y:y,material:trim,chamfer:0.004) }
            for side in 0..<4 {
                let wall = SCNNode(); wall.eulerAngles.y = Float(side)*Float.pi/2; tower.addChildNode(wall)
                lancet(wall,y:0.984,z:0.123,w:0.066,h:0.20)
                if side == 0 { lancet(wall,y:0.654,z:0.123,w:0.063,h:0.19) }
            }
            // Open belfry: slender corner piers frame a hanging bronze bell.
            for px: CGFloat in [-0.089,0.089] {
                for pz: CGFloat in [-0.094,0.094] { box(tower,w:0.037,h:0.20,l:0.037,x:px,y:1.29,z:pz,material:trim,chamfer:0.003) }
            }
            cylinder(tower,r:0.008,h:0.065,y:1.426,material:wood)
            let bell = SCNCone(topRadius:0.023,bottomRadius:0.049,height:0.068); bell.radialSegmentCount = 10; bell.materials = [gold]
            let bellNode = SCNNode(geometry:bell); bellNode.position.y = 1.397; tower.addChildNode(bellNode)
            cylinder(tower,r:0.053,h:0.012,y:1.361,material:gold)
            box(tower,w:0.263,h:0.036,l:0.273,y:1.48,material:trim,chamfer:0.004)
            let spire = SCNCone(topRadius:0,bottomRadius:0.165,height:0.405); spire.radialSegmentCount = 8; spire.materials = [roof]
            let node = SCNNode(geometry:spire); node.position.y = 1.7185; tower.addChildNode(node)
            cylinder(tower,r:0.014,h:0.02,y:1.913,material:gold)
            box(tower,w:0.010,h:0.092,l:0.01,y:1.93,material:gold,chamfer:0.001)
            box(tower,w:0.059,h:0.010,l:0.01,y:1.982,material:gold,chamfer:0.001)
        }
        // A smaller ridge lantern breaks up the long roof without competing with the twin towers.
        box(nave,w:0.11,h:0.14,l:0.13,y:1.24,z:-0.10,material:trim,chamfer:0.004)
        pyramidRoof(nave,w:0.18,h:0.27,l:0.20,y:1.38,z:-0.10,material:roof)
        cylinder(nave,r:0.008,h:0.06,y:1.641,z:-0.10,material:gold)
    }

    /// A compact hill-town castle: dressed stone, a tall keep, copper-blue roofs and a real gate surround.
    private static func buildCastle(_ r: SCNNode, _ f: CGFloat) {
        let stone = facadeMat(.stone,0.70,0.68,0.60,f), trim = mat(0.84,0.80,0.69,f)
        let base = texMat(.stone,0.59,0.59,0.53,f), shadow = mat(0.34,0.36,0.34,f)
        let roof = roofMat(0.34,0.44,0.52,f), wood = texMat(.planks,0.43,0.33,0.25,f)
        let iron = mat(0.30,0.34,0.35,f), red = mat(0.63,0.32,0.29,f), gold = mat(0.80,0.65,0.35,f)
        let glass = glassMat()
        box(r,w:0.96,h:0.06,l:0.94,material:base,chamfer:0.025)
        box(r,w:0.69,h:0.025,l:0.68,y:0.059,material:mat(0.65,0.63,0.54,f),chamfer:0.01)
        func arch(_ parent: SCNNode, x: CGFloat = 0, y: CGFloat, z: CGFloat, w: CGFloat, h: CGFloat, material: SCNMaterial) {
            let radius = w/2, shoulder = h-radius
            let path = UIBezierPath(); path.move(to:CGPoint(x:-radius,y:0)); path.addLine(to:CGPoint(x:radius,y:0))
            path.addLine(to:CGPoint(x:radius,y:shoulder))
            for i in 1...12 {
                let angle = CGFloat(i) * .pi/12
                path.addLine(to:CGPoint(x:cos(angle)*radius,y:shoulder+sin(angle)*radius))
            }
            path.close()
            let g = SCNShape(path:path,extrusionDepth:0.012); g.chamferRadius = 0.002; g.materials = [material]
            let n = SCNNode(geometry:g); n.position = SCNVector3(x,y,z); parent.addChildNode(n)
        }
        func slit(_ parent: SCNNode, x: CGFloat = 0, y: CGFloat, z: CGFloat, w: CGFloat = 0.059, h: CGFloat = 0.148) {
            arch(parent,x:x,y:y-0.017,z:z,w:w+0.036,h:h+0.033,material:trim)
            arch(parent,x:x,y:y,z:z+0.012,w:w,h:h,material:glass)
            box(parent,w:w+0.058,h:0.018,l:0.044,x:x,y:y-0.028,z:z+0.004,material:trim,chamfer:0.003)
        }
        let keep = SCNNode(); keep.position.z = -0.052; r.addChildNode(keep)
        box(keep,w:0.48,h:1.30,l:0.438,y:0.065,material:stone,chamfer:0.008)
        for x: CGFloat in [-0.224,0.224] {
            for z: CGFloat in [-0.204,0.204] {
                box(keep,w:0.041,h:1.26,l:0.041,x:x,y:0.09,z:z,material:trim,chamfer:0.004)
            }
        }
        for y: CGFloat in [0.70,1.035,1.335] { box(keep,w:0.513,h:0.036,l:0.47,y:y,material:trim,chamfer:0.006) }
        box(keep,w:0.547,h:0.045,l:0.505,y:1.375,material:base,chamfer:0.006)
        pyramidRoof(keep,w:0.595,h:0.385,l:0.556,y:1.42,material:roof)
        for side in 0..<4 {
            let wall = SCNNode(); wall.eulerAngles.y = Float(side) * .pi/2; keep.addChildNode(wall)
            let z: CGFloat = side%2 == 0 ? 0.225 : 0.246
            for x: CGFloat in [-0.112,0.112] { slit(wall,x:x,y:1.112,z:z,w:0.058,h:0.169) }
            slit(wall,y:0.802,z:z,w:0.064,h:0.15)
        }
        // Continuous curtain walls, with thicker copings and crenels on each side.
        for side in 0..<4 {
            let wall = SCNNode(); wall.eulerAngles.y = Float(side) * .pi/2; r.addChildNode(wall)
            box(wall,w:0.67,h:0.445,l:0.079,y:0.06,z:0.34,material:stone,chamfer:0.005)
            box(wall,w:0.68,h:0.032,l:0.098,y:0.485,z:0.34,material:trim,chamfer:0.004)
            for i in -3...3 {
                box(wall,w:0.063,h:0.083,l:0.094,x:CGFloat(i)*0.092,y:0.517,z:0.34,material:stone,chamfer:0.006)
                box(wall,w:0.071,h:0.014,l:0.102,x:CGFloat(i)*0.092,y:0.595,z:0.34,material:trim,chamfer:0.003)
            }
        }
        for x: CGFloat in [-0.33,0.33] {
            for z: CGFloat in [-0.33,0.33] {
                let tower = SCNNode(); tower.position = SCNVector3(x,0,z); r.addChildNode(tower)
                let h: CGFloat = z > 0 ? 0.855 : 1.005
                func drum(_ radius: CGFloat, _ height: CGFloat, _ bottom: CGFloat, _ material: SCNMaterial) {
                    let g = SCNCylinder(radius:radius,height:height); g.radialSegmentCount = 12; g.materials = [material]
                    let n = SCNNode(geometry:g); n.position.y = Float(bottom+height/2); tower.addChildNode(n)
                }
                drum(0.137,0.105,0.058,base); drum(0.119,h-0.12,0.13,stone)
                drum(0.126,0.028,0.40,trim); drum(0.137,0.039,h-0.03,trim)
                drum(0.145,0.027,h+0.011,base)
                for side in 0..<4 {
                    let wall = SCNNode(); wall.eulerAngles.y = Float(side) * .pi/2; tower.addChildNode(wall)
                    slit(wall,y:h-0.238,z:0.12,w:0.038,h:0.123)
                }
                let g = SCNCone(topRadius:0,bottomRadius:0.155,height:0.32); g.radialSegmentCount = 12; g.materials = [roof]
                let n = SCNNode(geometry:g); n.position.y = Float(h+0.198); tower.addChildNode(n)
                cylinder(tower,r:0.009,h:0.044,y:h+0.35,material:gold)
            }
        }
        // A framed arched oak gate with iron straps and a portcullis raised above it.
        box(r,w:0.284,h:0.577,l:0.122,y:0.062,z:0.357,material:stone,chamfer:0.007)
        box(r,w:0.320,h:0.027,l:0.149,y:0.626,z:0.36,material:trim,chamfer:0.005)
        for x: CGFloat in [-0.12,0,0.12] { box(r,w:0.072,h:0.076,l:0.133,x:x,y:0.653,z:0.36,material:stone,chamfer:0.005) }
        arch(r,y:0.063,z:0.426,w:0.252,h:0.425,material:trim)
        arch(r,y:0.069,z:0.436,w:0.204,h:0.380,material:shadow)
        arch(r,y:0.072,z:0.446,w:0.177,h:0.338,material:wood)
        for x: CGFloat in [-0.059,-0.029,0,0.029,0.059] { box(r,w:0.005,h:0.251,l:0.006,x:x,y:0.08,z:0.458,material:shadow,chamfer:0.001) }
        for y: CGFloat in [0.133,0.259] { box(r,w:0.173,h:0.014,l:0.012,y:y,z:0.463,material:iron,chamfer:0.002) }
        for x: CGFloat in [-0.064,0,0.064] { box(r,w:0.008,h:0.074,l:0.013,x:x,y:0.35,z:0.458,material:iron,chamfer:0.001) }
        box(r,w:0.173,h:0.011,l:0.014,y:0.378,z:0.457,material:iron,chamfer:0.001)
        box(r,w:0.27,h:0.032,l:0.101,y:0.007,z:0.442,material:base,chamfer:0.008)
        box(r,w:0.23,h:0.025,l:0.068,y:0.039,z:0.427,material:trim,chamfer:0.005)
        // The keep's pennant and small wall banners share the same subdued red.
        cylinder(keep,r:0.009,h:0.232,y:1.793,material:gold)
        let flagPath = UIBezierPath(); flagPath.move(to:.zero); flagPath.addLine(to:CGPoint(x:0.19,y:-0.018)); flagPath.addLine(to:CGPoint(x:0.154,y:-0.066)); flagPath.addLine(to:CGPoint(x:0.19,y:-0.106)); flagPath.addLine(to:CGPoint(x:0,y:-0.088)); flagPath.close()
        let flagG = SCNShape(path:flagPath,extrusionDepth:0.006); flagG.materials = [red]
        let flag = SCNNode(geometry:flagG); flag.position = SCNVector3(0.011,2.006,0); keep.addChildNode(flag)
        for x: CGFloat in [-0.172,0.172] {
            box(keep,w:0.071,h:0.176,l:0.011,x:x,y:0.785,z:0.227,material:red,chamfer:0.003)
            box(keep,w:0.086,h:0.011,l:0.018,x:x,y:0.957,z:0.230,material:gold,chamfer:0.002)
            box(keep,w:0.009,h:0.059,l:0.008,x:x,y:0.864,z:0.237,material:trim,chamfer:0.001)
            box(keep,w:0.032,h:0.009,l:0.008,x:x,y:0.887,z:0.237,material:trim,chamfer:0.001)
        }
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
        case .poplar:    TownDecorationModels.buildPoplar(into: root, variant: variant)
        case .fruitTree: buildFruitTree(root, variant)
        case .bush:      buildBush(root, variant)
        case .road:      buildRoad(root, n: false, e: false, s: false, w: false)
        case .bench:     buildBench(root)
        case .streetLamp: TownDecorationModels.buildStreetLamp(into: root)
        case .fountain:  buildFountain(root)
        case .pond:      buildPond(root)
        case .doghouse:   buildDoghouse(root)
        case .birdFeeder: buildBirdFeeder(root)
        case .firePit:    buildFirePit(root)
        case .pumpkins:      buildPumpkins(root)
        case .scarecrow:     buildScarecrow(root)
        case .christmasTree: buildChristmasTree(root)
        case .snowman:       buildSnowman(root)
        }
    }

    /// Hollow timber kennel. +Z is the open doorway; the dog rests at local Z = 0.18.
    private static func buildDoghouse(_ r: SCNNode) {
        let cedar = m(0.73,0.55,0.36), lighter = m(0.78,0.61,0.41), endGrain = m(0.59,0.44,0.29)
        let cream = m(0.94,0.87,0.70), roof = m(0.43,0.53,0.48), ridge = m(0.35,0.44,0.41)
        let inside = m(0.49,0.39,0.28), blue = m(0.39,0.54,0.61)
        func slab(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                  _ material: SCNMaterial, chamfer: CGFloat = 0.004) {
            let g = SCNBox(width:w,height:h,length:l,chamferRadius:min(chamfer,min(w,h,l)/2)); g.materials = [material]
            let n = SCNNode(geometry:g); n.position = SCNVector3(x,y+h/2,z); r.addChildNode(n)
        }
        // A thin floor, never a solid interior block: the rig needs this cavity to lie down.
        slab(0.70,0.020,0.65,0,0,-0.015,endGrain,chamfer:0.008)
        for i in 0..<7 {
            slab(0.084,0.003,0.596,-0.258+CGFloat(i)*0.086,0.020,-0.018,i%2 == 0 ? cedar : lighter,chamfer:0.001)
        }
        // Individual horizontal boards on the two side walls and the back.
        for i in 0..<7 {
            let y = 0.024+CGFloat(i)*0.066
            for x: CGFloat in [-0.322,0.322] { slab(0.044,0.064,0.62,x,y,-0.03,i%3 == 0 ? lighter : cedar) }
            slab(0.618,0.064,0.038,0,y,-0.321,i%2 == 0 ? cedar : endGrain)
        }
        // Interior rear face only; the middle and entire doorway remain empty.
        slab(0.595,0.453,0.006,0,0.025,-0.298,inside,chamfer:0.001)
        for x: CGFloat in [-0.321,0.321] {
            for z: CGFloat in [-0.314,0.286] { slab(0.057,0.475,0.048,x,0.020,z,cream) }
            slab(0.058,0.030,0.65,x,0.025,-0.015,endGrain)
        }
        let eave: CGFloat = 0.494, rise: CGFloat = 0.213, half: CGFloat = 0.351
        for z: CGFloat in [-0.329,0.289] {
            let path = UIBezierPath(); path.move(to:CGPoint(x:-half,y:0)); path.addLine(to:CGPoint(x:half,y:0)); path.addLine(to:CGPoint(x:0,y:rise)); path.close()
            let g = SCNShape(path:path,extrusionDepth:0.025); g.materials = [cedar]
            let n = SCNNode(geometry:g); n.position = SCNVector3(0,eave,z); r.addChildNode(n)
        }
        // Ridge runs front-to-back (Z), aligned with both triangular gables.
        let reach: CGFloat = 0.391, pitch = rise/half
        for side: CGFloat in [-1,1] {
            let g = SCNBox(width:reach*sqrt(1+pitch*pitch),height:0.029,length:0.73,chamferRadius:0.004)
            g.materials = [roof]
            let n = SCNNode(geometry:g); n.position = SCNVector3(side*reach/2,eave+rise-reach*pitch/2+0.014,-0.020)
            n.eulerAngles.z = Float(-side*atan(pitch)); r.addChildNode(n)
            for z: CGFloat in [-0.385,0.345] {
                let fascia = SCNBox(width:reach*sqrt(1+pitch*pitch),height:0.031,length:0.025,chamferRadius:0.003)
                fascia.materials = [cream]
                let edge = SCNNode(geometry:fascia); edge.position = SCNVector3(side*reach/2,eave+rise-reach*pitch/2+0.005,z)
                edge.eulerAngles.z = n.eulerAngles.z; r.addChildNode(edge)
            }
            // Two quiet seams break up the roof without noisy tile geometry.
            for z: CGFloat in [-0.14,0.10] {
                let seam = SCNBox(width:reach*sqrt(1+pitch*pitch),height:0.006,length:0.007,chamferRadius:0.001)
                seam.materials = [ridge]
                let edge = SCNNode(geometry:seam); edge.position = SCNVector3(side*reach/2,eave+rise-reach*pitch/2+0.031,z)
                edge.eulerAngles.z = n.eulerAngles.z; r.addChildNode(edge)
            }
        }
        slab(0.041,0.025,0.766,0,0.708,-0.020,ridge,chamfer:0.008)
        // Small carved paw on the gable; a custom nameplate can cover it.
        for (x,y,rad) in [(0.0,0.553,0.017),(-0.026,0.581,0.009),(-0.009,0.594,0.009),(0.011,0.594,0.009),(0.029,0.581,0.009)] as [(CGFloat,CGFloat,CGFloat)] {
            let g = SCNCylinder(radius:rad,height:0.006); g.radialSegmentCount = 12; g.materials = [cream]
            let n = SCNNode(geometry:g); n.position = SCNVector3(x,y,0.308); n.eulerAngles.x = .pi/2; r.addChildNode(n)
        }
        // Low front deck supports the front paws when the dog rests in the doorway.
        slab(0.50,0.020,0.16,0,0,0.38,endGrain,chamfer:0.006)
        slab(0.43,0.008,0.64,0,0.023,0.12,m(0.70,0.72,0.53),chamfer:0.004)
        // Preserve the bowl anchor used by the pet's feeding behaviour.
        let bowl = SCNNode(); bowl.name = "bowl"; bowl.position = SCNVector3(0.36,0.018,0.42); r.addChildNode(bowl)
        let bottom = SCNCylinder(radius:0.068,height:0.013); bottom.radialSegmentCount = 20; bottom.materials = [blue]
        let base = SCNNode(geometry:bottom); base.position.y = -0.006; bowl.addChildNode(base)
        let rim = SCNTorus(ringRadius:0.063,pipeRadius:0.010); rim.ringSegmentCount = 24; rim.pipeSegmentCount = 8; rim.materials = [blue]
        let rimNode = SCNNode(geometry:rim); rimNode.position.y = 0.009; bowl.addChildNode(rimNode)
        let hollow = SCNCylinder(radius:0.053,height:0.006); hollow.radialSegmentCount = 20; hollow.materials = [m(0.27,0.39,0.44)]
        let dish = SCNNode(geometry:hollow); dish.position.y = 0.001; bowl.addChildNode(dish)
        let food = SCNNode(); food.name = "bowlFood"; food.position = SCNVector3(0.36,0.035,0.42); food.isHidden = true; r.addChildNode(food)
        let kibble = m(0.48,0.33,0.21)
        for i in 0..<9 {
            let a = Float(i)*2.4, radius: Float = i == 0 ? 0 : 0.031
            let g = SCNSphere(radius:0.013); g.segmentCount = 6; g.materials = [kibble]
            let n = SCNNode(geometry:g); n.position = SCNVector3(cos(a)*radius,Float(i%3)*0.003,sin(a)*radius); n.scale.y = 0.6; food.addChildNode(n)
        }
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

    /// A little harvest group: two carved lanterns and a smaller uncut pumpkin.
    private static func buildPumpkins(_ r: SCNNode) {
        for (x,z,radius,variant,yaw) in [(-0.055,0.07,0.128,0,-0.16),(-0.174,-0.12,0.088,2,-0.5),(0.167,-0.037,0.092,1,0.38)] as [(Float,Float,Float,Int,Float)] {
            let pumpkin = AutumnProps.pumpkin(radius:radius,variant:variant,carved:variant != 2)
            pumpkin.position = SCNVector3(x,0.004,z); pumpkin.eulerAngles.y = yaw; r.addChildNode(pumpkin)
        }
        let leaves = [m(0.67,0.45,0.25),m(0.61,0.53,0.30),m(0.55,0.59,0.34)]
        for (i,p) in [SCNVector3(-0.25,0.007,0.035),SCNVector3(0.12,0.007,0.155),SCNVector3(0.04,0.007,-0.17)].enumerated() {
            let path = UIBezierPath(); path.move(to:CGPoint(x:-0.036,y:0)); path.addLine(to:CGPoint(x:-0.009,y:0.018)); path.addLine(to:CGPoint(x:0.041,y:0)); path.addLine(to:CGPoint(x:-0.009,y:-0.019)); path.close()
            let g = SCNShape(path:path,extrusionDepth:0.003); g.materials = [leaves[i]]
            let node = SCNNode(geometry:g); node.position = p; node.eulerAngles = SCNVector3(-Float.pi/2,Float(i)*1.7,0); r.addChildNode(node)
        }
    }

    /// A patched harvest coat, stuffed cuffs, sackcloth face and a crow on the crossbar.
    private static func buildScarecrow(_ r: SCNNode) {
        let wood = m(0.48,0.38,0.27), straw = m(0.78,0.64,0.37), lightStraw = m(0.90,0.77,0.48)
        let coat = m(0.62,0.43,0.29), seams = m(0.43,0.33,0.26), trousers = m(0.35,0.46,0.44)
        let patch = m(0.74,0.60,0.39), sack = m(0.83,0.75,0.59), hat = m(0.35,0.32,0.38), scarf = m(0.72,0.39,0.25)
        func slab(_ w: CGFloat,_ h: CGFloat,_ l: CGFloat,_ x: CGFloat,_ y: CGFloat,_ z: CGFloat,_ mat: SCNMaterial) {
            let g = SCNBox(width:w,height:h,length:l,chamferRadius:min(0.01,min(w,h,l)/3)); g.materials = [mat]
            let n = SCNNode(geometry:g); n.position = SCNVector3(x,y+h/2,z); r.addChildNode(n)
        }
        AutumnProps.beam(r,SIMD3(0,0,0),SIMD3(-0.011,0.72,0),radius:0.021,material:wood)
        AutumnProps.beam(r,SIMD3(-0.29,0.51,-0.014),SIMD3(0.29,0.55,-0.014),radius:0.019,material:wood)
        // The coat flares at the hem; it is shaped cloth rather than a block torso.
        let cloth = UIBezierPath(); cloth.move(to:CGPoint(x:-0.093,y:0.29)); cloth.addLine(to:CGPoint(x:-0.115,y:0.335)); cloth.addLine(to:CGPoint(x:-0.075,y:0.565)); cloth.addLine(to:CGPoint(x:0.063,y:0.574)); cloth.addLine(to:CGPoint(x:0.103,y:0.317)); cloth.addLine(to:CGPoint(x:0.063,y:0.283)); cloth.addLine(to:CGPoint(x:0,y:0.304)); cloth.close()
        let body = SCNShape(path:cloth,extrusionDepth:0.107); body.chamferRadius = 0.010; body.materials = [coat]; r.addChildNode(SCNNode(geometry:body))
        for side: Float in [-1,1] {
            AutumnProps.beam(r,SIMD3(side*0.06,0.527,0),SIMD3(side*0.237,0.53+side*0.017,0),radius:0.044,material:coat)
            AutumnProps.beam(r,SIMD3(side*0.235,0.53+side*0.017,0),SIMD3(side*0.25,0.53+side*0.017,0),radius:0.046,material:patch)
            AutumnProps.beam(r,SIMD3(side*0.046,0.34,0),SIMD3(side*0.07,0.201,0.016),radius:0.035,material:trousers)
            for i in -2...2 {
                let d = Float(i)*0.009
                AutumnProps.beam(r,SIMD3(side*0.242,0.53+side*0.017+d,0),SIMD3(side*(0.30+Float(i%2)*0.008),0.53+side*0.017+d*2,Float(i)*0.006),radius:0.004,material:i%2 == 0 ? lightStraw : straw)
                AutumnProps.beam(r,SIMD3(side*0.07+d,0.215,0.014),SIMD3(side*0.074+d*1.35,0.162,0.022),radius:0.004,material:straw)
            }
        }
        slab(0.009,0.23,0.010,0,0.318,0.06,seams)
        slab(0.048,0.054,0.012,-0.06,0.346,0.056,trousers)
        slab(0.037,0.029,0.012,0.045,0.452,0.055,patch)
        for x: CGFloat in [-0.078,-0.045] { slab(0.004,0.065,0.003,x,0.34,0.064,lightStraw) }
        for y: CGFloat in [0.35,0.371,0.392] { slab(0.054,0.004,0.003,-0.06,y,0.065,lightStraw) }
        for y: CGFloat in [0.397,0.468,0.521] {
            let g = SCNSphere(radius:0.009); g.segmentCount = 8; g.materials = [seams]
            let node = SCNNode(geometry:g); node.position = SCNVector3(0,y,0.069); node.scale.z = 0.5; r.addChildNode(node)
        }
        let head = SCNNode(); head.position = SCNVector3(-0.01,0.655,0); head.eulerAngles.z = -0.10; r.addChildNode(head)
        let ball = SCNSphere(radius:0.076); ball.segmentCount = 12; ball.materials = [sack]
        let face = SCNNode(geometry:ball); face.scale = SCNVector3(0.94,1.05,0.88); head.addChildNode(face)
        for x: Float in [-0.025,0.025] {
            let button = SCNCylinder(radius:0.010,height:0.004); button.radialSegmentCount = 8; button.materials = [seams]
            let n = SCNNode(geometry:button); n.position = SCNVector3(x,0.013,0.062); n.eulerAngles.x = .pi/2; head.addChildNode(n)
        }
        for i in -2...2 {
            let x = Float(i)*0.012
            AutumnProps.beam(head,SIMD3(x-0.006,-0.023+abs(x)*0.22,0.065),SIMD3(x+0.006,-0.024+abs(x)*0.22,0.065),radius:0.0018,material:seams)
            AutumnProps.beam(head,SIMD3(x,-0.027+abs(x)*0.22,0.066),SIMD3(x,-0.017+abs(x)*0.22,0.066),radius:0.0015,material:seams)
        }
        let brim = SCNCylinder(radius:0.118,height:0.014); brim.radialSegmentCount = 12; brim.materials = [hat]
        let brimNode = SCNNode(geometry:brim); brimNode.position.y = 0.059; brimNode.eulerAngles.z = -0.10; head.addChildNode(brimNode)
        let crown = SCNCone(topRadius:0.042,bottomRadius:0.069,height:0.108); crown.radialSegmentCount = 10; crown.materials = [hat]
        let crownNode = SCNNode(geometry:crown); crownNode.position = SCNVector3(0.005,0.116,0); crownNode.eulerAngles.z = -0.10; head.addChildNode(crownNode)
        let band = SCNCylinder(radius:0.068,height:0.022); band.radialSegmentCount = 10; band.materials = [scarf]
        let bandNode = SCNNode(geometry:band); bandNode.position.y = 0.081; head.addChildNode(bandNode)
        slab(0.115,0.029,0.115,-0.005,0.566,0,scarf)
        let tail = UIBezierPath(); tail.move(to:CGPoint(x:-0.015,y:0.586)); tail.addLine(to:CGPoint(x:0.036,y:0.584)); tail.addLine(to:CGPoint(x:0.081,y:0.451)); tail.addLine(to:CGPoint(x:0.043,y:0.467)); tail.addLine(to:CGPoint(x:0.016,y:0.448)); tail.close()
        let tailG = SCNShape(path:tail,extrusionDepth:0.009); tailG.materials = [scarf]
        let tailNode = SCNNode(geometry:tailG); tailNode.position.z = 0.073; r.addChildNode(tailNode)
        let crow = AutumnProps.crow(); crow.position = SCNVector3(0.247,0.588,-0.010); crow.eulerAngles.y = -0.48; r.addChildNode(crow)
        let pumpkin = AutumnProps.pumpkin(radius:0.057,variant:2,carved:false); pumpkin.position = SCNVector3(-0.113,0.004,0.055); r.addChildNode(pumpkin)
        for i in 0..<7 {
            let a = Float(i)*2.4
            AutumnProps.beam(r,SIMD3(0.084,0.004,0.01),SIMD3(0.084+cos(a)*0.04,0.045+Float(i%3)*0.011,0.01+sin(a)*0.04),radius:0.003,material:straw)
        }
    }

    /// A proper spruce with glowing baubles, a star and a couple of presents.
    private static func buildChristmasTree(_ r: SCNNode) {
        let trunk = SCNCylinder(radius: 0.04, height: 0.12)
        trunk.materials = [m(0.42, 0.30, 0.20)]
        let t = SCNNode(geometry: trunk)
        t.position = SCNVector3(0, 0.06, 0)
        r.addChildNode(t)

        let greens = [m(0.18, 0.44, 0.26), m(0.22, 0.50, 0.30)]
        let tiers: [(r: CGFloat, h: CGFloat, y: Float)] = [(0.30, 0.30, 0.10), (0.24, 0.27, 0.27), (0.18, 0.24, 0.42), (0.11, 0.2, 0.56)]
        for (i, tier) in tiers.enumerated() {
            let g = SCNCone(topRadius: 0, bottomRadius: tier.r, height: tier.h)
            g.radialSegmentCount = 12
            g.materials = [greens[i % 2]]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(0, tier.y + Float(tier.h) / 2, 0)
            r.addChildNode(n)
        }

        // baubles, lit like fairy lights
        let colors: [UIColor] = [UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1),
                                 UIColor(red: 1.0, green: 0.82, blue: 0.30, alpha: 1),
                                 UIColor(red: 0.40, green: 0.62, blue: 1.0, alpha: 1)]
        var k = 0
        for tier in tiers.dropLast() {
            let count = Int(tier.r * 26)
            for j in 0..<count {
                let a = Float(j) / Float(count) * 2 * .pi + Float(k) * 0.5
                let ball = SCNSphere(radius: 0.022)
                ball.segmentCount = 8
                let mat = SCNMaterial()
                mat.diffuse.contents = colors[(j + k) % colors.count]
                mat.emission.contents = colors[(j + k) % colors.count].withAlphaComponent(0.7)
                mat.lightingModel = .constant
                ball.materials = [mat]
                let n = SCNNode(geometry: ball)
                let rr = Float(tier.r) * 0.82
                n.position = SCNVector3(cos(a) * rr, tier.y + 0.04, sin(a) * rr)
                r.addChildNode(n)
            }
            k += 1
        }

        // five-pointed star on top
        let star = UIBezierPath()
        for i in 0..<10 {
            let a = CGFloat(i) * .pi / 5 - .pi / 2
            let rad: CGFloat = i % 2 == 0 ? 0.075 : 0.032
            let pt = CGPoint(x: cos(a) * rad, y: -sin(a) * rad)
            if i == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
        }
        star.close()
        let starShape = SCNShape(path: star, extrusionDepth: 0.025)
        let gold = SCNMaterial()
        gold.diffuse.contents = UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1)
        gold.emission.contents = UIColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1)
        gold.lightingModel = .constant
        starShape.materials = [gold]
        let sn = SCNNode(geometry: starShape)
        sn.position = SCNVector3(0, 0.81, 0)
        sn.eulerAngles.y = .pi / 4                 // face the camera
        r.addChildNode(sn)

        // presents
        for (x, z, w, c) in [(0.2, 0.18, 0.12, (0.85, 0.25, 0.28)), (-0.16, 0.22, 0.1, (0.30, 0.55, 0.85))]
            as [(Float, Float, CGFloat, (CGFloat, CGFloat, CGFloat))] {
            let g = SCNBox(width: w, height: w * 0.8, length: w, chamferRadius: 0.008)
            g.materials = [m(c.0, c.1, c.2)]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(x, Float(w) * 0.4, z)
            n.eulerAngles.y = x
            r.addChildNode(n)
            let ribbon = SCNBox(width: w + 0.004, height: w * 0.8 + 0.004, length: 0.02, chamferRadius: 0)
            ribbon.materials = [m(1.0, 0.86, 0.40)]
            let rb = SCNNode(geometry: ribbon)
            rb.position = n.position
            rb.eulerAngles.y = x
            r.addChildNode(rb)
        }
    }

    /// Three snowballs, coal buttons, a carrot nose, a red scarf and a hat.
    private static func buildSnowman(_ r: SCNNode) {
        let snow = m(0.97, 0.98, 1.0), coal = m(0.14, 0.13, 0.14)
        let scarf = m(0.85, 0.25, 0.26), stick = m(0.42, 0.30, 0.20)

        var y: Float = 0
        for (i, rad) in [0.14, 0.105, 0.075].enumerated() {
            let g = SCNSphere(radius: CGFloat(rad))
            g.segmentCount = 16
            g.materials = [snow]
            let n = SCNNode(geometry: g)
            y += Float(rad) * (i == 0 ? 0.9 : 1.75)
            n.position = SCNVector3(0, y, 0)
            r.addChildNode(n)
            if i == 1 {
                for by in [-0.03, 0.03] as [Float] {
                    let b = SCNSphere(radius: 0.013)
                    b.segmentCount = 6
                    b.materials = [coal]
                    let bn = SCNNode(geometry: b)
                    bn.position = SCNVector3(0, y + by, Float(rad) * 0.98)
                    r.addChildNode(bn)
                }
                // stick arms
                for side in [-1.0, 1.0] as [Float] {
                    let g = SCNCylinder(radius: 0.008, height: 0.2)
                    g.materials = [stick]
                    let a = SCNNode(geometry: g)
                    a.position = SCNVector3(side * 0.17, y + 0.04, 0)
                    a.eulerAngles.z = side * -1.05
                    r.addChildNode(a)
                }
            }
        }
        let headY = y
        for ex in [-0.025, 0.025] as [Float] {
            let e = SCNSphere(radius: 0.011)
            e.segmentCount = 6
            e.materials = [coal]
            let en = SCNNode(geometry: e)
            en.position = SCNVector3(ex, headY + 0.02, 0.068)
            r.addChildNode(en)
        }
        let nose = SCNCone(topRadius: 0, bottomRadius: 0.014, height: 0.07)
        nose.materials = [m(0.95, 0.52, 0.18)]
        let ns = SCNNode(geometry: nose)
        ns.position = SCNVector3(0, headY, 0.1)
        ns.eulerAngles.x = .pi / 2
        r.addChildNode(ns)
        let wrap = SCNTorus(ringRadius: 0.078, pipeRadius: 0.022)
        wrap.materials = [scarf]
        let w = SCNNode(geometry: wrap)
        w.position = SCNVector3(0, headY - 0.065, 0)
        r.addChildNode(w)
        let tail = SCNBox(width: 0.04, height: 0.1, length: 0.02, chamferRadius: 0.008)
        tail.materials = [scarf]
        let tl = SCNNode(geometry: tail)
        tl.position = SCNVector3(0.05, headY - 0.11, 0.07)
        tl.eulerAngles.z = 0.2
        r.addChildNode(tl)
        let brim = SCNCylinder(radius: 0.085, height: 0.012)
        brim.materials = [coal]
        let bn = SCNNode(geometry: brim)
        bn.position = SCNVector3(0, headY + 0.065, 0)
        r.addChildNode(bn)
        let crown = SCNCylinder(radius: 0.055, height: 0.09)
        crown.materials = [coal]
        let cn = SCNNode(geometry: crown)
        cn.position = SCNVector3(0, headY + 0.115, 0)
        r.addChildNode(cn)
        let band = SCNCylinder(radius: 0.057, height: 0.018)
        band.materials = [scarf]
        let bd = SCNNode(geometry: band)
        bd.position = SCNVector3(0, headY + 0.08, 0)
        r.addChildNode(bd)
    }

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

        TownDecorationModels.addSwimmingDuck(to: r)
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
    static func buildRoad(_ r: SCNNode, n: Bool, e: Bool, s: Bool, w: Bool,
                          entrances: [RoadEntranceConnection] = []) {
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
            for connection in entrances { p.append(connection.outline(extraWidth: Float(inset * 2))) }
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

    /// A closed, softly faceted crown. Uneven rings avoid both perfect balls and noisy leaf meshes.
    private static func foliage(_ root: SCNNode, at p: SCNVector3, size: SCNVector3,
                                material: SCNMaterial, seed: Int) {
        let sides = 10
        let rings: [(Float, Float)] = [(-0.92, 0.22), (-0.60, 0.78), (-0.10, 1), (0.48, 0.85), (0.88, 0.42)]
        var points = [SCNVector3(0, -1, 0)]
        for ring in rings {
            for i in 0..<sides {
                let a = Float(i) * 2 * .pi / Float(sides) + Float(seed) * 0.31
                let variation = 1 + 0.07 * sin(Float(i * 3 + seed * 7))
                points.append(SCNVector3(cos(a) * ring.1 * variation,
                                        ring.0 + 0.035 * sin(Float(i * 2 + seed)),
                                        sin(a) * ring.1 * variation))
            }
        }
        points.append(SCNVector3(0.06, 1, -0.03))
        var indices: [Int32] = []
        for i in 0..<sides {
            let next = (i + 1) % sides
            indices += [0, Int32(1 + i), Int32(1 + next)]
            for j in 0..<(rings.count - 1) {
                let a = Int32(1 + j * sides + i), b = Int32(1 + j * sides + next)
                let c = a + Int32(sides), d = b + Int32(sides)
                indices += [a, c, b, b, c, d]
            }
            indices += [Int32(points.count - 1), Int32(1 + (rings.count - 1) * sides + next), Int32(1 + (rings.count - 1) * sides + i)]
        }
        // Blend broad facets with radial normals for soft foliage in the village palette.
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = points[Int(indices[t])], b = points[Int(indices[t + 1])], c = points[Int(indices[t + 2])]
            let u = SIMD3<Float>(b.x-a.x, b.y-a.y, b.z-a.z)
            let v = SIMD3<Float>(c.x-a.x, c.y-a.y, c.z-a.z)
            let n = simd_normalize(simd_cross(u, v))
            vertices += [a, b, c]
            for point in [a, b, c] {
                let radial = simd_normalize(SIMD3<Float>(point.x,point.y,point.z))
                let soft = simd_normalize(n * 0.35 + radial * 0.65)
                normals.append(SCNVector3(soft.x,soft.y,soft.z))
            }
        }
        let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals)],
                                   elements: [.init(indices: (0..<vertices.count).map(Int32.init), primitiveType: .triangles)])
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = p; node.scale = size
        root.addChildNode(node)
    }

    private static func twig(_ root: SCNNode, from a: SCNVector3, to b: SCNVector3,
                             radius: CGFloat, material: SCNMaterial, taper: CGFloat = 0.55) {
        let delta = SIMD3<Float>(b.x-a.x, b.y-a.y, b.z-a.z)
        let geometry = SCNCone(topRadius: radius * taper, bottomRadius: radius, height: CGFloat(simd_length(delta)))
        geometry.radialSegmentCount = 7; geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
        root.addChildNode(node)
    }

    private static func smallFruit(_ root: SCNNode, at p: SCNVector3, radius: CGFloat,
                                   material: SCNMaterial, plum: Bool = false) {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 8; geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = p; node.scale.y = plum ? 1.3 : 0.9
        root.addChildNode(node)
    }

    private static func buildFruitTree(_ r: SCNNode, _ variant: Int) {
        let v = ((variant % 3) + 3) % 3
        let bark = m(0.43, 0.32, 0.23)
        let green = v == 2 ? m(0.34, 0.51, 0.30) : m(0.43, 0.59, 0.34)
        let light = v == 2 ? m(0.40, 0.57, 0.32) : m(0.49, 0.64, 0.38)
        let shade = m(0.36, 0.51, 0.30)
        let fruitMat = v == 1 ? m(0.40, 0.29, 0.49) : v == 2 ? m(0.94, 0.57, 0.20) : m(0.79, 0.28, 0.23)
        let fork = SCNVector3(-0.015, 0.24, 0)
        twig(r, from: SCNVector3(0.025, 0.015, 0), to: fork, radius: 0.041, material: bark)
        for i in 0..<3 {
            let a = Float(i) * 2.1 + 0.4
            twig(r, from: SCNVector3(cos(a)*0.072, 0.008, sin(a)*0.072),
                 to: SCNVector3(0.02, 0.07, 0), radius: 0.016, material: bark)
        }
        // Three joined boughs: broad apple, upright plum, compact citrus.
        let crowns: [(SCNVector3, SCNVector3)]
        if v == 1 {
            crowns = [(SCNVector3(-0.065,0.46,0.015), SCNVector3(0.15,0.20,0.155)),
                      (SCNVector3(0.07,0.53,-0.035), SCNVector3(0.14,0.225,0.145)),
                      (SCNVector3(0.045,0.40,0.095), SCNVector3(0.13,0.145,0.13))]
        } else if v == 2 {
            crowns = [(SCNVector3(-0.10,0.37,0.005), SCNVector3(0.16,0.155,0.17)),
                      (SCNVector3(0.08,0.45,-0.025), SCNVector3(0.175,0.175,0.17)),
                      (SCNVector3(0.07,0.345,0.09), SCNVector3(0.145,0.13,0.145))]
        } else {
            crowns = [(SCNVector3(-0.12,0.405,0), SCNVector3(0.175,0.155,0.185)),
                      (SCNVector3(0.04,0.51,-0.04), SCNVector3(0.19,0.165,0.18)),
                      (SCNVector3(0.14,0.39,0.07), SCNVector3(0.16,0.14,0.16))]
        }
        for (i, crown) in crowns.enumerated() {
            twig(r, from: fork, to: crown.0, radius: 0.023, material: bark)
            foliage(r, at: crown.0, size: crown.1, material: [green,light,shade][i], seed: i + v * 3)
            // Fruit follows the outer boughs at staggered heights, readable from the map camera.
            for j in 0..<3 {
                let a = Float(j) * 2.1 + Float(i) * 0.9 + 0.4
                let pitch: Float = j == 1 ? 0.38 : j == 2 ? -0.48 : -0.06
                let p = SCNVector3(crown.0.x + cos(a)*cos(pitch)*crown.1.x*1.01,
                                   crown.0.y + sin(pitch)*crown.1.y,
                                   crown.0.z + sin(a)*cos(pitch)*crown.1.z*1.01)
                twig(r, from: p, to: SCNVector3(p.x,p.y+0.034,p.z), radius: 0.003, material: bark)
                smallFruit(r, at: p, radius: v == 1 ? 0.019 : 0.025, material: fruitMat, plum: v == 1)
            }
        }
        smallFruit(r, at: SCNVector3(0.14,0.018,0.10), radius: 0.019, material: fruitMat, plum: v == 1)
    }

    /// Berry shrub, flowering shrub and a fan of curved grass blades.
    private static func buildBush(_ r: SCNNode, _ variant: Int = 0) {
        let v = ((variant % 3) + 3) % 3
        let green = m(0.42,0.58,0.34), light = m(0.50,0.64,0.39), dark = m(0.35,0.50,0.31)
        if v == 2 {
            let grass = [green, light, m(0.59,0.67,0.42)]
            for i in 0..<17 {
                let a = Float(i) * 2.4
                let height = Float(0.17) + Float(i % 4)*0.027
                let spread = Float(0.09) + Float(i % 3)*0.027
                var vertices: [SCNVector3] = []
                for j in 0...4 {
                    let t = Float(j)/4
                    let width = Float(0.026) * (1-t) + 0.001
                    let x = cos(a)*spread*t*t, z = sin(a)*spread*t*t
                    vertices += [SCNVector3(x-sin(a)*width, height*t, z+cos(a)*width),
                                 SCNVector3(x+sin(a)*width, height*t, z-cos(a)*width)]
                }
                var indices: [Int32] = []
                for j in 0..<4 { let k = Int32(j*2); indices += [k,k+1,k+2,k+1,k+3,k+2] }
                let geo = SCNGeometry(sources: [.init(vertices: vertices)], elements: [.init(indices: indices, primitiveType: .triangles)])
                let mat = grass[i % grass.count]; mat.isDoubleSided = true
                geo.materials = [mat]; r.addChildNode(SCNNode(geometry: geo))
            }
            return
        }
        let crowns: [(SCNVector3,SCNVector3)] = [
            (SCNVector3(-0.065,0.105,0.015),SCNVector3(0.135,0.10,0.12)),
            (SCNVector3(0.075,0.09,0.03),SCNVector3(0.12,0.08,0.105)),
            (SCNVector3(0.025,0.135,-0.05),SCNVector3(0.105,0.11,0.11))]
        for (i,c) in crowns.enumerated() { foliage(r, at: c.0, size: c.1, material: [green,dark,light][i], seed: i+4) }
        let accents: [SCNVector3] = [SCNVector3(-0.095,0.19,0.055),SCNVector3(0.10,0.15,0.07),
                                   SCNVector3(0.025,0.24,-0.035),SCNVector3(-0.035,0.18,-0.09)]
        let berry = m(0.67,0.29,0.30), petal = m(0.91,0.75,0.67), centre = m(0.85,0.64,0.31)
        for p in accents {
            if v == 0 {
                for dx: Float in [-0.01,0.01] {
                    smallFruit(r, at: SCNVector3(p.x+dx,p.y,p.z), radius: 0.011, material: berry)
                }
            } else {
                for i in 0..<5 {
                    let a = Float(i)*2 * .pi/5
                    smallFruit(r, at: SCNVector3(p.x+cos(a)*0.014,p.y,p.z+sin(a)*0.014), radius: 0.012, material: petal)
                }
                smallFruit(r, at: SCNVector3(p.x,p.y+0.006,p.z), radius: 0.007, material: centre)
            }
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
        let stone = m(0.69,0.66,0.57), edge = m(0.85,0.81,0.70), shadow = m(0.58,0.58,0.51)
        let water = m(0.34,0.65,0.67), stream = m(0.65,0.84,0.81), foam = m(0.84,0.92,0.85)
        func add(_ geometry: SCNGeometry, _ y: CGFloat, _ material: SCNMaterial) {
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry); node.position.y = Float(y)
            r.addChildNode(node)
        }
        func disk(_ radius: CGFloat, _ height: CGFloat, _ y: CGFloat, _ material: SCNMaterial, sides: Int = 8) {
            let geo = SCNCylinder(radius: radius, height: height); geo.radialSegmentCount = sides
            add(geo,y,material)
        }
        func rim(_ inner: CGFloat, _ outer: CGFloat, _ height: CGFloat, _ y: CGFloat, _ material: SCNMaterial) {
            let geo = SCNTube(innerRadius: inner, outerRadius: outer, height: height)
            geo.radialSegmentCount = 8; add(geo,y,material)
        }
        // The water lies inside an open basin; layered coping gives the small silhouette weight.
        disk(0.385,0.035,0.018,shadow)
        disk(0.36,0.035,0.049,edge)
        disk(0.325,0.065,0.085,stone)
        rim(0.278,0.333,0.095,0.13,stone)
        rim(0.271,0.347,0.032,0.188,edge)
        disk(0.278,0.012,0.159,water,sides:48)
        disk(0.09,0.035,0.18,shadow)
        disk(0.071,0.035,0.213,edge)
        let shaft = SCNCone(topRadius:0.045,bottomRadius:0.057,height:0.17)
        shaft.radialSegmentCount = 8; add(shaft,0.308,stone)
        disk(0.066,0.022,0.395,edge)
        let bowl = SCNCone(topRadius:0.141,bottomRadius:0.058,height:0.069)
        bowl.radialSegmentCount = 8; add(bowl,0.436,stone)
        rim(0.112,0.152,0.028,0.481,edge)
        disk(0.114,0.009,0.482,water,sides:32)
        disk(0.024,0.065,0.52,stone)
        let finial = SCNSphere(radius:0.034); finial.segmentCount = 8; add(finial,0.561,edge)

        // Four continuous, restrained ribbons, with no screen-filling particle spray.
        let streams = SCNNode()
        for i in 0..<4 {
            let a = Float(i)*(.pi/2) + .pi/8
            var previous = SCNVector3(cos(a)*0.125,0.48,sin(a)*0.125)
            for j in 1...14 {
                let t = Float(j)/14
                let radius = 0.125 + 0.116*t
                let point = SCNVector3(cos(a)*radius,0.48 + 0.048*t - 0.36*t*t,sin(a)*radius)
                twig(streams, from: previous, to: point, radius: 0.008, material: stream, taper: 1)
                previous = point
            }
            let splash = SCNTorus(ringRadius:0.023,pipeRadius:0.003)
            splash.ringSegmentCount = 20; splash.pipeSegmentCount = 5; splash.materials = [foam]
            let node = SCNNode(geometry:splash)
            node.position = SCNVector3(cos(a)*0.241,0.168,sin(a)*0.241)
            node.name = "fountainRipple"
            r.addChildNode(node)
            if !UIAccessibility.isReduceMotionEnabled {
                let swell = SCNAction.group([.scale(to:1.65,duration:1.6),.fadeOpacity(to:0.12,duration:1.6)])
                swell.timingMode = .easeOut
                node.runAction(.repeatForever(.sequence([.wait(duration:Double(i)*0.15),swell,
                                                        .scale(to:0.7,duration:0),.fadeOpacity(to:0.8,duration:0)])))
            }
        }
        r.addChildNode(streams.flattenedClone())
        // Fine radial joints make the coping read as cut stone at closer zoom.
        let joint = m(0.67,0.65,0.56)
        for i in 0..<8 {
            let a = Float(i)*(.pi/4)
            let geo = SCNBox(width:0.058,height:0.0015,length:0.003,chamferRadius:0)
            geo.materials = [joint]
            let node = SCNNode(geometry:geo)
            node.position = SCNVector3(cos(a)*0.307,0.205,sin(a)*0.307)
            node.eulerAngles.y = -a
            r.addChildNode(node)
        }
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
        view.isPlaying = scene.renderingActive
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
            if r.state == .ended || r.state == .cancelled { scene.refreshLocalBuildingLights() }
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
        case .cottage, .house, .barn, .well, .farm, .stables,
             .tent, .homestead:                                        (0.78, 0.49, 0.34)
        case .tavern, .blacksmith, .market, .shop, .flowerShop, .cafe, .post: (0.36, 0.48, 0.60)
        case .townhall, .school, .church, .fortress, .tower,
             .fireStation, .policeStation, .hospital:                  (0.37, 0.62, 0.52)
        case .cathedral, .castle, .chateau:                            (0.49, 0.42, 0.62)
        case .hauntedHouse:                                            (0.42, 0.34, 0.50)
        case .gingerbreadHouse:                                        (0.66, 0.42, 0.24)
        }
    }
}
