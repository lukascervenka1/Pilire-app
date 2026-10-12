import SceneKit
import UIKit

/// Per-building window state and inexpensive pools of warm light on the ground.
/// Materials belong to this model; previews and other buildings retain their daylight colors.
final class BuildingNightLighting {
    static let windowMaterialName = "buildingWindow"
    private struct Pane {
        let material: SCNMaterial
        let diffuse: Any?
        let emission: Any?
        let warmth: CGFloat
    }
    private var panes: [Pane] = []
    private let glow = SCNNode()
    private let porchLight = SCNNode()
    private var phase: DaylightPhase = .day
    private var localLightEnabled = false

    init(model: SCNNode, parent: SCNNode, footprint: (w: Int, l: Int), entrances: [BuildingRoadEntrance]) {
        var seen = Set<ObjectIdentifier>()
        model.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] where material.name == Self.windowMaterialName {
                guard seen.insert(ObjectIdentifier(material)).inserted else { continue }
                self.panes.append(Pane(material: material, diffuse: material.diffuse.contents,
                                       emission: material.emission.contents,
                                       warmth: CGFloat(self.panes.count % 3) * 0.035))
            }
        }
        glow.name = "buildingNightGlow"
        glow.opacity = 0
        parent.addChildNode(glow)
        let centerX = Float(footprint.w - 1) / 2
        // These light pools stay under the building when it moves or turns.
        var positions = entrances.map { SCNVector3($0.point.x, 0.029, $0.point.y + Float($0.outward.y)*0.24) }
        if !panes.isEmpty {
            positions += [SCNVector3(-0.40,0.029,-0.03), SCNVector3(Float(footprint.w)-0.60,0.029,0.02)]
        }
        for position in positions.prefix(4) {
            let plane = SCNPlane(width: 1.18, height: 1.02)
            let material = SCNMaterial()
            material.diffuse.contents = Self.poolTexture
            material.lightingModel = .constant
            material.blendMode = .add
            material.writesToDepthBuffer = false
            plane.materials = [material]
            let pool = SCNNode(geometry: plane)
            pool.eulerAngles.x = -.pi/2
            pool.position = position
            pool.castsShadow = false
            pool.categoryBitMask = TownScene.decorCategory
            glow.addChildNode(pool)
        }
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red:1,green:0.71,blue:0.39,alpha:1)
        light.intensity = 0
        light.attenuationStartDistance = 0.12
        light.attenuationEndDistance = 1.35
        light.attenuationFalloffExponent = 2
        light.castsShadow = false
        porchLight.light = light
        if let entry = entrances.first {
            porchLight.position = SCNVector3(entry.point.x,0.38,entry.point.y + Float(entry.outward.y)*0.20)
        } else {
            porchLight.position = SCNVector3(centerX,0.38,0.48)
        }
        porchLight.isHidden = true
        parent.addChildNode(porchLight)
    }

    func apply(_ phase: DaylightPhase) {
        self.phase = phase
        let strength: CGFloat
        switch phase {
        case .day: strength = 0
        case .dawn: strength = 0.22
        case .dusk: strength = 0.58
        case .night: strength = 1
        }
        for pane in panes {
            if strength == 0 {
                pane.material.diffuse.contents = pane.diffuse
                pane.material.emission.contents = pane.emission
            } else {
                pane.material.diffuse.contents = UIColor(red:1,green:0.80+pane.warmth,blue:0.47+pane.warmth,alpha:1)
                pane.material.emission.contents = UIColor(red:0.95,green:0.61+pane.warmth,blue:0.25+pane.warmth,alpha:1)
            }
            pane.material.emission.intensity = strength == 0 ? 1 : strength * 0.95
        }
        glow.opacity = strength * 0.42
        setLocalLightEnabled(localLightEnabled)
    }

    func setLocalLightEnabled(_ enabled: Bool) {
        // SceneKit must not animate light registration/visibility when a scene is removed.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        localLightEnabled = enabled
        porchLight.isHidden = !enabled || phase == .day
        switch phase {
        case .day: porchLight.light?.intensity = 0
        case .dawn: porchLight.light?.intensity = 25
        case .dusk: porchLight.light?.intensity = 65
        case .night: porchLight.light?.intensity = 125
        }
    }

    private static let poolTexture: UIImage = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width:128,height:128),format:format).image { context in
            let colors = [UIColor(red:1,green:0.63,blue:0.25,alpha:0.72).cgColor,
                          UIColor(red:1,green:0.55,blue:0.18,alpha:0.28).cgColor,
                          UIColor(red:1,green:0.49,blue:0.12,alpha:0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.35,1])!
            context.cgContext.drawRadialGradient(gradient,startCenter:CGPoint(x:64,y:64),startRadius:0,
                                                endCenter:CGPoint(x:64,y:64),endRadius:64,options:[])
        }
    }()
}
