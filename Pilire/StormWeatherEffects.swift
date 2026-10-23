import SceneKit
import UIKit
import MediaAccessibility

/// A distant storm at the back of the island. A single broad pulse lights the
/// cloud and town; no screen overlay, rapid flicker or strikes among buildings.
final class StormWeatherEffects {
    let root = SCNNode()
    private let pulse = SCNNode()
    private var clouds: [SCNNode] = []
    private var strikePositions: [SCNVector3] = []
    private var phase: DaylightPhase = .day
    private var active = false
    private var flashesAllowed = false
    var onLightning: (() -> Void)?

    static var allowsLightning: Bool {
        !UIAccessibility.isReduceMotionEnabled && !MADimFlashingLightsEnabled()
    }

    init(islandSize: Int) {
        root.name = "stormWeather"
        let half = Float(islandSize) / 2
        for (i, position) in [SCNVector3(-half * 0.80, 3.0, -half - 2.5),
                              SCNVector3(-half - 2.6, 3.6, -half * 0.75),
                              SCNVector3(-half - 2.4, 4.3, -half - 2.4)].enumerated() {
            let geometry = SCNPlane(width: i == 2 ? 6.8 : 5.4, height: i == 2 ? 2.3 : 1.7)
            let material = SCNMaterial(); material.diffuse.contents = Self.cloudTexture
            material.lightingModel = .constant; material.writesToDepthBuffer = false
            geometry.materials = [material]
            let cloud = SCNNode(geometry: geometry); cloud.position = position
            cloud.constraints = [SCNBillboardConstraint()]; cloud.castsShadow = false
            cloud.opacity = 0.62; cloud.name = "stormCloud"
            root.addChildNode(cloud); clouds.append(cloud)
        }
        strikePositions = clouds.map { SCNVector3($0.position.x, $0.position.y - 0.3, $0.position.z) }
        pulse.name = "stormLightning"
        let light = SCNLight(); light.type = .directional
        light.color = UIColor(red: 0.83, green: 0.90, blue: 1, alpha: 1)
        light.intensity = 0; light.castsShadow = false
        pulse.light = light; pulse.eulerAngles = SCNVector3(-0.7, -0.8, 0)
        root.addChildNode(pulse)

        // Geometry stays in world space; the directional light has its own
        // orientation, while the thin distant fork faces the map camera.
        let fork = SCNNode(); fork.name = "stormFork"
        fork.position = SCNVector3(-half * 0.55, 3.7, -half - 3.1)
        fork.constraints = [SCNBillboardConstraint()]
        root.addChildNode(fork)
        let ice = SCNMaterial(); ice.lightingModel = .constant
        ice.diffuse.contents = UIColor(red: 0.82, green: 0.90, blue: 0.98, alpha: 1)
        ice.writesToDepthBuffer = false; ice.isDoubleSided = true
        for points in [
            [CGPoint(x: 0.14, y: 0.63), CGPoint(x: -0.06, y: 0.30), CGPoint(x: 0.06, y: 0.20), CGPoint(x: -0.13, y: -0.18), CGPoint(x: -0.10, y: -0.46)],
            [CGPoint(x: 0.03, y: 0.20), CGPoint(x: 0.23, y: 0.03), CGPoint(x: 0.28, y: -0.15)]
        ] {
            let path = UIBezierPath()
            // A filled tapered ribbon instead of a chunky zigzag icon.
            for (i, p) in points.enumerated() {
                let width = CGFloat(points.count - i) * 0.0025 + 0.002
                if i == 0 { path.move(to: CGPoint(x: p.x - width, y: p.y)) }
                else { path.addLine(to: CGPoint(x: p.x - width, y: p.y)) }
            }
            for (i, p) in points.enumerated().reversed() {
                let width = CGFloat(points.count - i) * 0.0025 + 0.002
                path.addLine(to: CGPoint(x: p.x + width, y: p.y))
            }
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0.001); shape.materials = [ice]
            fork.addChildNode(SCNNode(geometry: shape))
        }
        let halo = SCNPlane(width: 2.8, height: 1.8)
        let glow = SCNMaterial(); glow.lightingModel = .constant
        glow.diffuse.contents = Self.glowTexture; glow.blendMode = .add; glow.writesToDepthBuffer = false
        halo.materials = [glow]
        let haloNode = SCNNode(geometry: halo); haloNode.position.z = -0.025
        haloNode.opacity = 0.22; fork.addChildNode(haloNode)
        fork.opacity = 0
        root.enumerateHierarchy { node, _ in node.categoryBitMask = TownScene.decorCategory; node.castsShadow = false }
        apply(.day)
    }

    func apply(_ phase: DaylightPhase) {
        self.phase = phase
        for cloud in clouds {
            cloud.geometry?.firstMaterial?.multiply.contents = phase == .night
                ? UIColor(red: 0.31, green: 0.39, blue: 0.45, alpha: 1)
                : UIColor(red: 0.54, green: 0.62, blue: 0.67, alpha: 1)
        }
    }

    /// Called on tab/app changes and when accessibility settings change.
    func setActive(_ enabled: Bool, allowLightning: Bool = StormWeatherEffects.allowsLightning) {
        guard enabled != active || allowLightning != flashesAllowed else { return }
        active = enabled; flashesAllowed = allowLightning
        root.removeAction(forKey: "stormCycle")
        clearFlash()
        guard enabled && allowLightning else { return }
        let firstWait = SCNAction.wait(duration: 11, withRange: 6)
        let cycle = SCNAction.sequence([
            .run { [weak self] _ in
                DispatchQueue.main.async { self?.flash() }
            },
            .wait(duration: 35, withRange: 16)
        ])
        root.runAction(.sequence([firstWait, .repeatForever(cycle)]), forKey: "stormCycle")
    }

    /// Also used by the native preview to inspect the peak and falloff.
    func flash() {
        guard active && flashesAllowed && Self.allowsLightning else { return }
        clearFlash()
        onLightning?()
        let maximum: CGFloat = phase == .night ? 65 : 125
        let fork = root.childNode(withName: "stormFork", recursively: false)!
        fork.position = strikePositions.randomElement()!
        fork.scale.x = Bool.random() ? 1 : -1
        // One smooth pulse, followed by a long dark interval.
        pulse.runAction(.customAction(duration: 1.15) { node, elapsed in
            let level = Self.envelope(at: Float(elapsed))
            node.light?.intensity = maximum * CGFloat(level)
        }, forKey: "stormPulse")
        fork.runAction(.customAction(duration: 1.15) { node, elapsed in
            node.opacity = CGFloat(Self.envelope(at: Float(elapsed))) * 0.72
        }, forKey: "stormPulse")
    }

    func clearFlash() {
        pulse.removeAction(forKey: "stormPulse"); pulse.light?.intensity = 0
        let fork = root.childNode(withName: "stormFork", recursively: false)
        fork?.removeAction(forKey: "stormPulse"); fork?.opacity = 0
    }

    nonisolated static func envelope(at time: Float) -> Float {
        guard time > 0, time < 1.15 else { return 0 }
        let t = time < 0.13 ? time / 0.13 : (1.15 - time) / 1.02
        return t * t * (3 - 2 * t)
    }

    private static let cloudTexture: UIImage = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 384, height: 160), format: format).image { ctx in
            let colors = [UIColor(white: 1, alpha: 0.72).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            for (x, y, w, h) in [(73.0, 93.0, 130.0, 83.0), (145, 72, 165, 110), (231, 91, 175, 105), (300, 99, 130, 72)] {
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: x, y: y); ctx.cgContext.scaleBy(x: w / 2, y: h / 2)
                ctx.cgContext.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                                endCenter: .zero, endRadius: 1, options: [])
                ctx.cgContext.restoreGState()
            }
        }
    }()
    private static let glowTexture: UIImage = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { ctx in
            let colors = [UIColor(red: 0.81, green: 0.89, blue: 1, alpha: 0.70).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 48, y: 48), startRadius: 0,
                endCenter: CGPoint(x: 48, y: 48), endRadius: 48, options: [])
        }
    }()
}
