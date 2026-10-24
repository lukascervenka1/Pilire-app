import SceneKit
import UIKit
import simd

/// Shared local coordinates keep the tray, feet, bill and individual seeds aligned.
/// The feeder still fits its original small, single-tile garden footprint.
enum BirdFeederModel {
    nonisolated static let trayTop: Float = 0.448
    nonisolated static let perch = SIMD3<Float>(-0.065, trayTop, 0.126)
    nonisolated static let perchYaw: Float = atan2(0.065, -0.086)
    nonisolated static let seeds: [SIMD3<Float>] = [
        [0, 0.454, 0.040], [-0.008, 0.454, 0.045], [0.009, 0.454, 0.038],
        [-0.004, 0.454, 0.032], [0.006, 0.454, 0.050]
    ]

    static func build(into root: SCNNode) {
        let wood = FeederGeometry.material(0.62, 0.46, 0.30)
        let board = FeederGeometry.material(0.74, 0.59, 0.39)
        let endGrain = FeederGeometry.material(0.48, 0.37, 0.26)
        let edge = FeederGeometry.material(0.82, 0.71, 0.49)
        let green = FeederGeometry.material(0.43, 0.54, 0.40)
        let seam = FeederGeometry.material(0.35, 0.45, 0.34)
        let seed = FeederGeometry.material(0.84, 0.71, 0.40)
        let darkSeed = FeederGeometry.material(0.44, 0.36, 0.24)
        func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ p: SIMD3<Float>, _ m: SCNMaterial, bevel: CGFloat = 0.003) -> SCNNode {
            FeederGeometry.box(root, w, h, d, at: p, material: m, bevel: bevel)
        }
        let post = SCNCylinder(radius: 0.024, height: 0.419)
        post.radialSegmentCount = 8; post.materials = [wood]
        let support = SCNNode(geometry: post); support.position.y = 0.2095; root.addChildNode(support)
        _ = box(0.058, 0.028, 0.058, [0, 0.020, 0], endGrain)
        // Two small braces and a framed plank tray, with a low, open front lip.
        for side: Float in [-1, 1] {
            FeederGeometry.beam(root, [0, 0.346, 0], [side * 0.105, 0.417, 0], radius: 0.010, material: wood)
        }
        let tray = box(0.286, 0.023, 0.267, [0, 0.4325, 0], endGrain, bevel: 0.006)
        tray.name = "perch"
        for i in 0..<5 {
            _ = box(0.051, 0.004, 0.241, [-0.104 + Float(i)*0.052, 0.446, 0], i % 2 == 0 ? board : wood, bevel: 0.001)
        }
        for side: Float in [-1, 1] {
            _ = box(0.013, 0.021, 0.266, [side*0.137, 0.451, 0], edge)
        }
        _ = box(0.264, 0.021, 0.013, [0, 0.451, -0.127], edge)
        // Broad landing edge: both toes lie on its top at exactly trayTop.
        _ = box(0.266, 0.009, 0.045, [0, trayTop - 0.0045, 0.127], board)
        for (i, position) in seeds.enumerated() {
            let grain = FeederGeometry.ellipsoid(root, 0.006, at: position,
                scale: [0.75, 0.65, 1.08], material: seed, segments: 6)
            grain.eulerAngles.y = Float(i)*1.9; grain.name = "feederSeed\(i)"
        }
        for (i, p) in [SIMD3<Float>(-0.050, 0.451, -0.019), [0.034, 0.451, -0.040],
                       [0.068, 0.451, 0.012], [-0.025, 0.451, 0.001], [0.051, 0.451, 0.061],
                       [-0.065, 0.451, 0.040], [0.016, 0.451, -0.012]].enumerated() {
            let grain = FeederGeometry.ellipsoid(root, 0.0045, at: p,
                scale: [0.7, 0.55, 1.15], material: i % 3 == 0 ? darkSeed : seed, segments: 6)
            grain.eulerAngles.y = Float(i)*2.1
        }
        for side: Float in [-1, 1] {
            _ = box(0.018, 0.204, 0.018, [side*0.116, 0.550, -0.070], wood)
            _ = box(0.024, 0.012, 0.024, [side*0.116, 0.459, -0.070], edge)
        }
        // Two thin pitched planes replace the old diagonally rotated block.
        // The ridge runs along Z; the open front keeps the feeding bird visible.
        let reach: Float = 0.173, rise: Float = 0.100, eave: Float = 0.615
        let pitch = rise/reach
        for side: Float in [-1, 1] {
            let p = SIMD3<Float>(side*reach/2, eave+rise/2, -0.009)
            let roof = box(CGFloat(hypot(reach, rise)), 0.015, 0.315, p, green)
            roof.eulerAngles.z = -side*atan(pitch); roof.name = "feederRoof"
            for z: Float in [-0.170, 0.152] {
                let fascia = box(CGFloat(hypot(reach, rise)), 0.014, 0.011, [p.x,p.y-0.004,z], edge, bevel: 0.002)
                fascia.eulerAngles.z = roof.eulerAngles.z
            }
            for z: Float in [-0.065, 0.044] {
                let joint = box(CGFloat(hypot(reach, rise)), 0.0025, 0.003, [p.x,p.y+0.008,z], seam, bevel: 0.0005)
                joint.eulerAngles.z = roof.eulerAngles.z
            }
        }
        _ = box(0.023, 0.014, 0.333, [0, eave+rise+0.003, -0.009], seam)
    }
}

/// Small shared primitives for the feeder and its visitor; all materials are matte.
enum FeederGeometry {
    static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let material = SCNMaterial(); material.lightingModel = .lambert
        material.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
        material.roughness.contents = 1; return material
    }
    @discardableResult static func box(_ root: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                                       at p: SIMD3<Float>, material: SCNMaterial, bevel: CGFloat = 0.003) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: d, chamferRadius: min(bevel, min(w,h,d)/2))
        g.materials = [material]
        let node = SCNNode(geometry: g); node.simdPosition = p; root.addChildNode(node); return node
    }
    @discardableResult static func ellipsoid(_ root: SCNNode, _ radius: CGFloat, at p: SIMD3<Float>,
        scale: SIMD3<Float>, material: SCNMaterial, segments: Int = 10) -> SCNNode {
        let g = SCNSphere(radius: radius); g.segmentCount = segments; g.materials = [material]
        let node = SCNNode(geometry: g); node.simdPosition = p; node.simdScale = scale
        root.addChildNode(node); return node
    }
    static func beam(_ root: SCNNode, _ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) {
        let delta = b-a
        let g = SCNCylinder(radius: radius, height: CGFloat(simd_length(delta)))
        g.radialSegmentCount = 6; g.materials = [material]
        let node = SCNNode(geometry: g); node.simdPosition = (a+b)/2
        node.simdOrientation = simd_quatf(from: [0,1,0], to: simd_normalize(delta)); root.addChildNode(node)
    }
}
