import SwiftUI
import SceneKit

enum ChestRevealPhase: Int {
    case closed, stirring, glowing, opened, revealed
}

/// The same matte, softly bevelled geometry and warm daylight used by the town.
@MainActor
enum WeeklyChestModel {
    struct Rig {
        let scene: SCNScene
        let camera: SCNNode
        let chest: SCNNode
        let lid: SCNNode
        let treasureLight: SCNNode
        let treasure: SCNNode
    }

    private static var thumbnail: UIImage?

    static func image() -> UIImage {
        if let thumbnail { return thumbnail }
        let rig = make()
        rig.camera.camera?.orthographicScale = 1.02
        rig.camera.look(at: SCNVector3(0, 0.60, 0))
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = rig.scene
        renderer.pointOfView = rig.camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 640, height: 440),
                                      antialiasingMode: .multisampling4X)
        thumbnail = image
        return image
    }

    static func make() -> Rig {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let wood = material(0.61, 0.42, 0.25)
        let plankColors = [
            material(0.69, 0.49, 0.30), material(0.73, 0.53, 0.33),
            material(0.66, 0.46, 0.28)
        ]
        let brass = material(0.72, 0.59, 0.35)
        let brassEdge = material(0.56, 0.45, 0.27)
        let dark = material(0.26, 0.22, 0.16)
        let chest = SCNNode()
        scene.rootNode.addChildNode(chest)

        let meadow = SCNCylinder(radius: 1.11, height: 0.055)
        meadow.radialSegmentCount = 14
        meadow.materials = [material(0.61, 0.71, 0.47)]
        let meadowNode = SCNNode(geometry: meadow)
        meadowNode.scale.z = 0.77
        meadowNode.position.y = 0.025
        scene.rootNode.addChildNode(meadowNode)
        for (x, z, size) in [(-0.86, 0.44, 0.10), (0.87, -0.37, 0.08)] {
            let stone = SCNSphere(radius: size)
            stone.segmentCount = 6
            stone.materials = [material(0.67, 0.67, 0.57)]
            let n = SCNNode(geometry: stone)
            n.position = SCNVector3(x, 0.07, z)
            n.scale.y = 0.6
            scene.rootNode.addChildNode(n)
        }
        for x: Float in [-0.94, 0.93] {
            for i in 0..<3 {
                let blade = SCNCone(topRadius: 0, bottomRadius: 0.025, height: 0.13)
                blade.radialSegmentCount = 3
                blade.materials = [material(0.40, 0.56, 0.29)]
                let n = SCNNode(geometry: blade)
                n.position = SCNVector3(x + Float(i) * 0.025, 0.10, 0.08 + Float(i) * 0.03)
                n.eulerAngles.z = Float(i - 1) * 0.20
                scene.rootNode.addChildNode(n)
            }
        }

        box(chest, 1.55, 0.12, 1.02, at: (0, 0.16, 0), material: wood)
        for x: CGFloat in [-0.61, 0.61] {
            for z: CGFloat in [-0.36, 0.36] {
                box(chest, 0.18, 0.15, 0.18, at: (x, 0.10, z), material: wood)
            }
        }
        for row in 0..<3 {
            let y = 0.32 + CGFloat(row) * 0.185
            for z: CGFloat in [-0.48, 0.48] {
                box(chest, 1.49, 0.175, 0.10, at: (0, y, z), material: plankColors[row])
            }
            for x: CGFloat in [-0.72, 0.72] {
                box(chest, 0.10, 0.175, 0.90, at: (x, y, 0), material: plankColors[(row + 1) % 3])
            }
        }
        box(chest, 1.33, 0.035, 0.82, at: (0, 0.27, 0), material: dark)
        for x: CGFloat in [-0.46, 0.46] {
            for z: CGFloat in [-0.54, 0.54] {
                box(chest, 0.13, 0.68, 0.035, at: (x, 0.52, z), material: brass)
                for y: CGFloat in [0.25, 0.78] {
                    let rivet = SCNSphere(radius: 0.024)
                    rivet.segmentCount = 6
                    rivet.materials = [brassEdge]
                    let n = SCNNode(geometry: rivet)
                    n.position = SCNVector3(x, y, z + (z > 0 ? 0.023 : -0.023))
                    chest.addChildNode(n)
                }
            }
        }
        for z: CGFloat in [-0.49, 0.49] {
            box(chest, 1.54, 0.055, 0.085, at: (0, 0.85, z), material: wood)
        }
        for x: CGFloat in [-0.735, 0.735] {
            box(chest, 0.085, 0.055, 0.94, at: (x, 0.85, 0), material: wood)
        }

        let lid = SCNNode()
        lid.position = SCNVector3(0, 0.87, -0.54)
        chest.addChildNode(lid)
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: -0.54, y: 0))
        for point in [CGPoint(x: 0.54, y: 0), CGPoint(x: 0.54, y: 0.11),
                      CGPoint(x: 0.39, y: 0.25), CGPoint(x: 0.17, y: 0.31),
                      CGPoint(x: -0.17, y: 0.31), CGPoint(x: -0.39, y: 0.25),
                      CGPoint(x: -0.54, y: 0.11)] {
            profile.addLine(to: point)
        }
        profile.close()
        let lidShape = SCNShape(path: profile, extrusionDepth: 1.60)
        lidShape.chamferRadius = 0.018
        lidShape.materials = [plankColors[1]]
        let arch = SCNNode(geometry: lidShape)
        arch.eulerAngles.y = .pi / 2
        arch.position.z = 0.54
        lid.addChildNode(arch)
        for x: CGFloat in [-0.46, 0.46] {
            // Five quiet facets follow the lid rather than adding glossy ornament.
            for (z, y, length, angle) in [
                (0.075, 0.19, 0.22, -0.75), (0.275, 0.295, 0.23, -0.26),
                (0.54, 0.335, 0.34, 0.0), (0.805, 0.295, 0.23, 0.26),
                (1.005, 0.19, 0.22, 0.75)
            ] {
                let strap = box(lid, 0.13, 0.025, length, at: (x, y, z), material: brass)
                strap.eulerAngles.x = Float(angle)
            }
        }
        for z: CGFloat in [0.25, 0.48, 0.71, 0.94] {
            box(lid, 1.53, 0.012, 0.012, at: (0, z > 0.35 && z < 0.75 ? 0.317 : 0.27, z),
                material: wood, bevel: 0)
        }
        box(lid, 0.23, 0.25, 0.045, at: (0, -0.025, 1.105), material: brass)
        box(lid, 0.035, 0.065, 0.012, at: (0, -0.04, 1.134), material: dark, bevel: 0.01)

        let treasureMaterial = material(1, 0.84, 0.48)
        treasureMaterial.emission.contents = UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1)
        let treasure = box(chest, 1.20, 0.015, 0.72, at: (0, 0.39, 0), material: treasureMaterial)
        treasure.opacity = 0
        for (x, z, y) in [(-0.28, -0.19, 0.43), (0.10, -0.25, 0.43),
                          (0.32, -0.10, 0.43), (-0.09, 0.02, 0.45), (0.19, -0.15, 0.47)] {
            let coin = SCNCylinder(radius: 0.10, height: 0.035)
            coin.radialSegmentCount = 10
            coin.materials = [brass]
            let node = SCNNode(geometry: coin)
            node.position = SCNVector3(x, y, z)
            chest.addChildNode(node)
        }
        let treasureLight = SCNNode()
        treasureLight.light = SCNLight()
        treasureLight.light?.type = .omni
        treasureLight.light?.intensity = 0
        treasureLight.light?.attenuationEndDistance = 3
        treasureLight.position = SCNVector3(0, 0.98, 0.15)
        chest.addChildNode(treasureLight)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 1, green: 0.96, blue: 0.87, alpha: 1)
        ambient.light?.intensity = 460
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 880
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowRadius = 3
        sun.light?.shadowColor = UIColor(red: 0.21, green: 0.18, blue: 0.12, alpha: 0.22)
        sun.eulerAngles = SCNVector3(-0.85, -0.5, 0)
        scene.rootNode.addChildNode(sun)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.35
        camera.position = SCNVector3(3.6, 4.0, 4.8)
        camera.look(at: SCNVector3(0, 0.85, 0))
        scene.rootNode.addChildNode(camera)
        return Rig(scene: scene, camera: camera, chest: chest, lid: lid,
                   treasureLight: treasureLight, treasure: treasure)
    }

    private static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
        material.lightingModel = .lambert
        return material
    }

    @discardableResult
    private static func box(_ parent: SCNNode, _ width: CGFloat, _ height: CGFloat, _ depth: CGFloat,
                            at position: (CGFloat, CGFloat, CGFloat), material: SCNMaterial,
                            bevel: CGFloat = 0.015) -> SCNNode {
        let shape = SCNBox(width: width, height: height, length: depth,
                           chamferRadius: min(bevel, min(width, height, depth) / 2))
        shape.chamferSegmentCount = 1
        shape.materials = [material]
        let node = SCNNode(geometry: shape)
        node.position = SCNVector3(position.0, position.1, position.2)
        parent.addChildNode(node)
        return node
    }
}

struct WeeklyChestArtwork: View {
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .task { image = WeeklyChestModel.image() }
        .accessibilityHidden(true)
    }
}

struct WeeklyChestSceneView: UIViewRepresentable {
    let phase: ChestRevealPhase
    let rarity: ChestReward.Rarity
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let rig = context.coordinator.rig
        view.scene = rig.scene
        view.pointOfView = rig.camera
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.phase != phase else { return }
        coordinator.phase = phase
        let rig = coordinator.rig
        view.isPlaying = [.stirring, .glowing, .opened].contains(phase) && !reduceMotion
        if phase == .stirring && !reduceMotion {
            let left = SCNAction.rotateBy(x: 0, y: 0, z: -0.025, duration: 0.09)
            let right = SCNAction.rotateBy(x: 0, y: 0, z: 0.05, duration: 0.18)
            rig.chest.runAction(.sequence([left, right, left, .wait(duration: 0.12), left, right, left]))
        }
        let color: UIColor
        if phase.rawValue < ChestRevealPhase.opened.rawValue {
            color = UIColor(red: 1, green: 0.88, blue: 0.64, alpha: 1)
        } else {
            switch rarity {
            case .common: color = UIColor(red: 1, green: 0.88, blue: 0.64, alpha: 1)
            case .rare: color = UIColor(red: 0.52, green: 0.77, blue: 1, alpha: 1)
            case .epic: color = UIColor(red: 1, green: 0.77, blue: 0.30, alpha: 1)
            }
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = reduceMotion ? 0 : 0.65
        rig.lid.eulerAngles.x = phase.rawValue >= ChestRevealPhase.opened.rawValue ? -1.85 : 0
        rig.treasure.opacity = phase.rawValue >= ChestRevealPhase.glowing.rawValue ? 1 : 0
        rig.treasure.geometry?.firstMaterial?.emission.contents = color
        rig.treasureLight.light?.color = color
        rig.treasureLight.light?.intensity = phase.rawValue >= ChestRevealPhase.glowing.rawValue ? 190 : 0
        SCNTransaction.commit()
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.scene = nil
    }

    @MainActor
    final class Coordinator {
        let rig = WeeklyChestModel.make()
        var phase: ChestRevealPhase?
    }
}
