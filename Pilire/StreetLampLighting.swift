import SceneKit
import UIKit

/// Every lamp keeps its lit panes and ground pool; TownScene shares a small
/// budget of actual local lights between street lamps and building entrances.
final class StreetLampLighting {
    static let glassMaterialName = "streetLampGlass"
    static let bulbMaterialName = "streetLampBulb"
    private let panes: [SCNMaterial]
    private let bulbs: [SCNMaterial]
    private let pool = SCNNode()
    private let lightNode = SCNNode()
    private var strength: CGFloat = 0
    private var localLightEnabled = false

    init(parent: SCNNode) {
        var glass: [SCNMaterial] = [], core: [SCNMaterial] = []
        var seen = Set<ObjectIdentifier>()
        parent.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                guard seen.insert(ObjectIdentifier(material)).inserted else { continue }
                if material.name == Self.glassMaterialName { glass.append(material) }
                if material.name == Self.bulbMaterialName { core.append(material) }
            }
        }
        panes = glass; bulbs = core
        let plane = SCNPlane(width: 1.28, height: 1.28)
        let glow = SCNMaterial(); glow.lightingModel = .constant
        glow.diffuse.contents = Self.poolTexture
        glow.blendMode = .add; glow.writesToDepthBuffer = false
        plane.materials = [glow]
        pool.geometry = plane; pool.eulerAngles.x = -.pi / 2
        pool.position.y = 0.034; pool.name = "streetLampPool"
        pool.castsShadow = false; pool.categoryBitMask = TownScene.decorCategory
        parent.addChildNode(pool)

        let light = SCNLight(); light.type = .omni
        light.color = UIColor(red: 1, green: 0.73, blue: 0.43, alpha: 1)
        light.intensity = 0; light.castsShadow = false
        light.attenuationStartDistance = 0.18
        light.attenuationEndDistance = 1.9
        light.attenuationFalloffExponent = 2
        lightNode.light = light; lightNode.position.y = 0.95
        lightNode.name = "streetLampLocalLight"
        parent.addChildNode(lightNode)
        apply(.day)
    }

    func apply(_ phase: DaylightPhase) {
        switch phase {
        case .day: strength = 0
        case .dawn: strength = 0.18
        case .dusk: strength = 0.65
        case .night: strength = 1
        }
        for material in panes {
            material.diffuse.contents = strength == 0
                ? UIColor(red: 0.75, green: 0.82, blue: 0.77, alpha: 1)
                : UIColor(red: 1, green: 0.79, blue: 0.43, alpha: 1)
            material.emission.contents = UIColor(red: 1, green: 0.65, blue: 0.28, alpha: 1)
            material.emission.intensity = strength * 0.80
        }
        for material in bulbs {
            material.emission.contents = UIColor(red: 1, green: 0.83, blue: 0.51, alpha: 1)
            material.emission.intensity = strength
        }
        pool.opacity = strength * 0.62
        pool.isHidden = strength == 0
        setLocalLightEnabled(localLightEnabled)
    }

    func setLocalLightEnabled(_ enabled: Bool) {
        localLightEnabled = enabled
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        lightNode.isHidden = !enabled || strength == 0
        lightNode.light?.intensity = enabled ? strength * 280 : 0
        SCNTransaction.commit()
    }

    private static let poolTexture: UIImage = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { context in
            let colors = [UIColor(red: 1, green: 0.73, blue: 0.39, alpha: 0.73).cgColor,
                          UIColor(red: 1, green: 0.65, blue: 0.30, alpha: 0.29).cgColor,
                          UIColor(red: 1, green: 0.60, blue: 0.26, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.42, 1])!
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }()
}
