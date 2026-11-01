import SwiftUI
import SceneKit

extension S.map {
    static let builtOn = T(cs: "Postaveno %@", sk: "Postavené %@", en: "Built %@")
    static let buildCost = T(cs: "Stavba stála", sk: "Stavba stála", en: "It cost")
    static let pillarsDone = T(cs: "%d z %d splněno", sk: "%d z %d splnených", en: "%d of %d done")
}

struct BuildingDetailSheet: View {
    let node: BuildingNode
    let dayRecord: DayRecord?
    var onRotate: (() -> Void)? = nil
    var onStore: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize

    private var builtDate: Date? { dayRecord?.date ?? node.associatedBuilding?.builtDate }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BuildingDiorama(node: node)
                        .frame(height: 280)
                        .background(
                            LinearGradient(colors: [Color(red: 0.80, green: 0.88, blue: 0.92), Theme.creamTop],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cardRadius)
                                .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                        }
                        .accessibilityHidden(true)

                    header
                    actions
                    Text(L(S.map.moveTip))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.creamLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    costPanel
                    if let record = dayRecord, !record.pillars.isEmpty { dayPanel(record) }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Theme.creamGradient)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.creamTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .tint(Theme.creamLabel).accessibilityLabel(L(S.common.close))
                }
            }
        }
        .presentationBackground(Theme.creamTop)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.type.displayName)
                .font(.system(.title, design: .rounded).bold())
                .foregroundStyle(CatalogStyle.ink)
                .accessibilityAddTraits(.isHeader)
            Text("\(node.type.footprint.w) × \(node.type.footprint.l) · \(node.type.category.title)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(MarketStyle.green)
            if let builtDate {
                Label(L(S.map.builtOn, builtDate.formatted(
                        Date.FormatStyle(date: .long).locale(Language.shared.current.locale))),
                      systemImage: "calendar")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.creamLabel)
            }
            if !node.isComplete {
                Label(L(S.map.underConstruction), systemImage: "hammer.fill")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(MarketStyle.accentInk)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.accentTop.opacity(0.18), in: Capsule())
                    .padding(.top, 4)
            }
        }
    }

    private var actions: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if node.canRotate {
                Button { (onRotate ?? node.toggleRotation)() } label: {
                    Label(L(S.map.rotate), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleButtonStyle(kind: .outline))
            }
            // Put away rather than destroyed: it goes to the inventory and can
            // come back any time, so no confirmation is needed.
            if let onStore {
                Button {
                    dismiss()
                    onStore()
                } label: {
                    Label(L(S.town.storeAway), systemImage: "backpack")
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleButtonStyle(kind: .outline))
            }
        }
    }

    private var costPanel: some View {
        let cost = node.type.cost
        let parts = [(Material.wood, cost.wood), (.brick, cost.brick), (.steel, cost.steel)].filter { $0.1 > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L(S.map.buildCost))
            PaperPanel {
                HStack(spacing: 16) {
                    ForEach(parts, id: \.0) { m, n in MarketToken(payment: .material(m, n)) }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dayPanel(_ record: DayRecord) -> some View {
        let pillars = record.pillars.sorted { $0.order < $1.order }
        let done = pillars.filter(\.isCompleted).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(L(S.calendar.dayPillars))
                Spacer(minLength: 8)
                Text(L(S.map.pillarsDone, done, pillars.count))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(MarketStyle.green)
            }
            PaperPanel {
                ForEach(pillars) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: p.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(p.isCompleted ? MarketStyle.green : MarketStyle.edge)
                            .accessibilityHidden(true)
                        Text(p.text)
                            .foregroundStyle(p.isCompleted ? CatalogStyle.ink : Theme.creamLabel)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(p.isCompleted ? L(S.market.settled) : "")
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(.title3, design: .rounded).bold())
            .foregroundStyle(CatalogStyle.ink).accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Diorama

/// The building on its own grass tile, seen from the town's isometric angle
/// and lit by the town's sun. It turns slowly and follows a horizontal drag.
/// The scene is built once, so redraws of the sheet don't restart it.
private struct BuildingDiorama: UIViewRepresentable {
    let node: BuildingNode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        // ProMotion phones get 120 frames; SceneKit defaults to 60, which
        // reads as stutter next to the rest of iOS. Render every frame so the
        // slow turn is evenly paced rather than driven by scene changes.
        view.preferredFramesPerSecond = 120
        view.rendersContinuously = true
        let (scene, turntable) = Self.scene(for: node)
        view.scene = scene
        let coordinator = context.coordinator
        coordinator.turntable = turntable
        coordinator.autoSpin = !reduceMotion
        coordinator.startSpin()
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var turntable: SCNNode?
        var autoSpin = true
        private static let spinKey = "spin"

        func startSpin(after delay: TimeInterval = 0) {
            guard autoSpin, let turntable else { return }
            let spin = SCNAction.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 28))
            turntable.runAction(.sequence([.wait(duration: delay), spin]), forKey: Self.spinKey)
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let turntable else { return }
            switch gesture.state {
            case .began:
                turntable.removeAction(forKey: Self.spinKey)
            case .changed:
                turntable.eulerAngles.y += Float(gesture.translation(in: gesture.view).x) * 0.012
                gesture.setTranslation(.zero, in: gesture.view)
            default:
                startSpin(after: 2.5)
            }
        }

        /// Only horizontal drags turn the model; vertical ones scroll the sheet.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }
    }

    private static let elevation: Float = 0.55   // about 31°, like the town camera
    private static let aspect: Float = 1.2       // narrowest phone card, width / height

    static func scene(for node: BuildingNode) -> (SCNScene, SCNNode) {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let turntable = SCNNode()
        scene.rootNode.addChildNode(turntable)

        // A clone of the very model standing in the town: same variant, same
        // style, same lit windows at night.
        let model = (node.childNodes.first ?? BuildingFactory.node(for: node.type)).clone()
        model.opacity = node.isComplete ? 1 : 0.55
        let (minB, maxB) = model.boundingBox
        model.position = SCNVector3(-(minB.x + maxB.x) / 2, -minB.y, -(minB.z + maxB.z) / 2)
        // In town, buildings rely on a soft contact shadow; here the sun casts
        // a real one onto the tile, plus the same contact shadow underneath.
        model.enumerateHierarchy { child, _ in child.castsShadow = true }
        turntable.addChildNode(model)
        let footprint = node.type.footprint
        turntable.addChildNode(contactShadowNode(radius: 0.42, cellsX: footprint.w, cellsZ: footprint.l))

        // Grass tile with earth sides, a little larger than the building.
        let fp = footprint
        let tileW = max(CGFloat(fp.w) + 0.5, CGFloat(maxB.x - minB.x) + 0.35)
        let tileL = max(CGFloat(fp.l) + 0.5, CGFloat(maxB.z - minB.z) + 0.35)
        let tile = SCNBox(width: tileW, height: 0.24, length: tileL, chamferRadius: 0.05)
        func flat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            m.lightingModel = .lambert
            return m
        }
        let grass = flat(0.60, 0.74, 0.46), earth = flat(0.55, 0.42, 0.29)
        tile.materials = [earth, earth, earth, earth, grass, earth]
        let tileNode = SCNNode(geometry: tile)
        tileNode.position.y = -0.12
        turntable.addChildNode(tileNode)

        // The town's light rig, with the sun now casting real shadows.
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1000
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowColor = UIColor(white: 0, alpha: 0.26)
        sun.shadowMapSize = CGSize(width: 1024, height: 1024)
        sun.shadowSampleCount = 8
        sun.shadowRadius = 3
        // An explicit shadow box around the tile: the automatic projection
        // left the tile outside it and no shadow was drawn.
        sun.automaticallyAdjustsShadowProjection = false
        sun.orthographicScale = Double(max(tileW, tileL)) * 1.3 + Double(maxB.y - minB.y) * 0.5
        sun.zNear = 0.1
        sun.zFar = 40
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.9, -0.6, 0)
        sunNode.simdPosition = -sunNode.simdWorldFront * 15
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 600
        ambient.color = UIColor(red: 0.85, green: 0.90, blue: 0.96, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Fit the camera to every angle the turntable will show, so tall towers
        // and wide farms both fill the card without clipping as they turn.
        // Real vertices rather than the bounding box: a pitched roof leaves
        // the box's upper corners empty, which used to shrink the building.
        let corners = vertices(of: model, in: turntable)
            + [Float(-tileW / 2), Float(tileW / 2)].flatMap { x in
                [Float(-tileL / 2), Float(tileL / 2)].flatMap { z in [SCNVector3(x, 0, z), SCNVector3(x, -0.24, z)] }
            }
        let e = elevation
        var minX = Float.infinity, maxX = -Float.infinity, minY = Float.infinity, maxY = -Float.infinity
        for step in 0..<24 {
            let a = Float(step) / 24 * 2 * .pi
            for c in corners {
                let x = c.x * cos(a) + c.z * sin(a)
                let z = -c.x * sin(a) + c.z * cos(a)
                let screenY = c.y * cos(e) - z * sin(e)
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, screenY); maxY = max(maxY, screenY)
            }
        }
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max((maxY - minY) / 2, (maxX - minX) / 2 / aspect) * 1.04)
        camera.zFar = 200
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.eulerAngles.x = -e
        // Back along the view direction, then shifted so the content is centred.
        let centreY = (minY + maxY) / 2
        let back: Float = 40
        cameraNode.position = SCNVector3((minX + maxX) / 2,
                                         back * sin(e) + centreY * cos(e),
                                         back * cos(e) - centreY * sin(e))
        scene.rootNode.addChildNode(cameraNode)
        return (scene, turntable)
    }

    /// Every vertex of the model, in the turntable's space.
    private static func vertices(of root: SCNNode, in space: SCNNode) -> [SCNVector3] {
        var out: [SCNVector3] = []
        root.enumerateHierarchy { child, _ in
            guard let source = child.geometry?.sources(for: .vertex).first,
                  source.usesFloatComponents, source.bytesPerComponent == 4,
                  source.componentsPerVector >= 3 else { return }
            source.data.withUnsafeBytes { raw in
                for i in 0..<source.vectorCount {
                    let base = i * source.dataStride + source.dataOffset
                    let p = SCNVector3(raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                                       raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                                       raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self))
                    out.append(space.convertPosition(p, from: child))
                }
            }
        }
        return out
    }
}
