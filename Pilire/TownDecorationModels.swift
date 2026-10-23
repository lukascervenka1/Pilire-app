import SceneKit
import UIKit
import simd

/// Small park pieces use the same muted plaster, iron and foliage palette as
/// the town's buildings. Geometry stays readable from the map camera.
enum TownDecorationModels {
    static func buildPoplar(into root: SCNNode, variant: Int) {
        let look = ((variant % 3) + 3) % 3
        let height: Float = [1, 0.95, 1.07][look]
        let tree = SCNNode(); tree.name = "poplarCrownAndTrunk"
        tree.scale = SCNVector3(1, height, 1); tree.eulerAngles.y = Float(look) * 0.73
        root.addChildNode(tree)
        let bark = material(0.48, 0.44, 0.34), groove = material(0.36, 0.34, 0.27)
        let foliage = [material(0.43, 0.57, 0.30), material(0.48, 0.60, 0.33),
                       material(0.40, 0.54, 0.29), material(0.51, 0.61, 0.35)]
        cone(tree, top: 0.014, bottom: 0.034, height: 0.81, at: (0, 0.43, 0), material: bark)
        cone(tree, top: 0.029, bottom: 0.051, height: 0.075, at: (0, 0.057, 0), material: bark)
        for i in 0..<5 {
            let angle = Float(i) * 2.4
            let tip = SIMD3<Float>(cos(angle) * 0.087, 0.74 + Float(i % 2) * 0.12, sin(angle) * 0.087)
            beam(tree, from: SIMD3(0, 0.34 + Float(i) * 0.045, 0), to: tip, radius: 0.009, material: bark)
            beam(tree, from: SIMD3(cos(angle) * 0.029, 0.08, sin(angle) * 0.029),
                 to: SIMD3(cos(angle) * 0.020, 0.31, sin(angle) * 0.020), radius: 0.0025, material: groove)
        }
        // Overlapping upright leaf masses keep the soft crown language used
        // by the orchard, with a slender column and a rounded tapering tip.
        let crown = SCNNode(); crown.name = "poplarFoliage"; tree.addChildNode(crown)
        ellipsoid(crown, radius: 0.143, at: (0, 0.79, 0),
                  scale: SCNVector3(0.96, 3.45, 0.85), material: foliage[0], segments: 10)
        ellipsoid(crown, radius: 0.064, at: (0.008, 1.238, -0.006),
                  scale: SCNVector3(0.84, 2.02, 0.80), material: foliage[1], segments: 10)
        let clusters: [(CGFloat, CGFloat, CGFloat, CGFloat, Float)] = [
            (-0.061, 0.53, 0.012, 0.079, 2.45), (0.060, 0.71, -0.020, 0.087, 2.65),
            (-0.053, 0.91, -0.023, 0.073, 2.60), (0.037, 1.105, 0.022, 0.058, 2.65),
            (-0.014, 0.74, 0.072, 0.068, 2.7)
        ]
        for (i, c) in clusters.enumerated() {
            ellipsoid(crown, radius: c.3, at: (c.0, c.1, c.2),
                      scale: SCNVector3(0.83, c.4, 0.82), material: foliage[(i + look) % 4], segments: 10)
        }
    }

    static func buildStreetLamp(into root: SCNNode) {
        let iron = material(0.25, 0.32, 0.30), edge = material(0.34, 0.41, 0.37)
        let brass = material(0.66, 0.51, 0.30), stone = material(0.71, 0.68, 0.59)
        box(root, 0.16, 0.040, 0.16, at: (0, 0.020, 0), material: stone, bevel: 0.014)
        box(root, 0.107, 0.028, 0.107, at: (0, 0.052, 0), material: iron, bevel: 0.008)
        cone(root, top: 0.030, bottom: 0.049, height: 0.135, at: (0, 0.127, 0), material: iron)
        cone(root, top: 0.019, bottom: 0.026, height: 0.615, at: (0, 0.493, 0), material: iron)
        for y: CGFloat in [0.185, 0.735, 0.795] {
            cylinder(root, radius: y == 0.185 ? 0.034 : 0.027, height: 0.018, at: (0, y, 0), material: brass)
        }
        for i in 0..<6 {
            let a = Float(i) / 6 * 2 * Float.pi
            beam(root, from: SIMD3(cos(a) * 0.027, 0.22, sin(a) * 0.027),
                 to: SIMD3(cos(a) * 0.021, 0.70, sin(a) * 0.021), radius: 0.0025, material: edge)
        }
        cone(root, top: 0.059, bottom: 0.022, height: 0.055, at: (0, 0.819, 0), material: iron)
        box(root, 0.135, 0.019, 0.135, at: (0, 0.847, 0), material: iron, bevel: 0.005)
        let glass = material(0.75, 0.82, 0.77); glass.name = StreetLampLighting.glassMaterialName
        glass.transparency = 0.48; glass.writesToDepthBuffer = false; glass.isDoubleSided = true
        let panels = frustum(root, bottom: 0.054, top: 0.078, lowY: 0.859, highY: 1.044, material: glass)
        panels.castsShadow = false
        for x: Float in [-1, 1] {
            for z: Float in [-1, 1] {
                beam(root, from: SIMD3(x * 0.056, 0.856, z * 0.056),
                     to: SIMD3(x * 0.080, 1.05, z * 0.080), radius: 0.006, material: iron)
            }
        }
        let bulb = material(0.99, 0.94, 0.75); bulb.name = StreetLampLighting.bulbMaterialName
        cylinder(root, radius: 0.013, height: 0.039, at: (0, 0.877, 0), material: brass)
        ellipsoid(root, radius: 0.030, at: (0, 0.943, 0), scale: SCNVector3(0.72, 1.58, 0.72), material: bulb)
        box(root, 0.18, 0.018, 0.18, at: (0, 1.052, 0), material: brass, bevel: 0.004)
        let roof = SCNPyramid(width: 0.219, height: 0.080, length: 0.219); roof.materials = [iron]
        let hood = SCNNode(geometry: roof); hood.position.y = 1.100; root.addChildNode(hood)
        cylinder(root, radius: 0.014, height: 0.033, at: (0, 1.144, 0), material: brass)
        ellipsoid(root, radius: 0.022, at: (0, 1.174, 0), scale: SCNVector3(0.65, 1.20, 0.65), material: iron)
    }

    /// Duck's local forward direction is −Z, including its bill and paddling feet.
    static func makeDuck() -> SCNNode {
        let duck = SCNNode(); duck.name = "pondDuckModel"
        let feather = material(0.69, 0.66, 0.55), wing = material(0.52, 0.50, 0.43)
        let breast = material(0.42, 0.29, 0.22), tail = material(0.26, 0.30, 0.27)
        let green = material(0.28, 0.43, 0.33), cream = material(0.94, 0.90, 0.75)
        let bill = material(0.84, 0.62, 0.25), blue = material(0.34, 0.43, 0.60)
        let eye = material(0.12, 0.15, 0.13)
        ellipsoid(duck, radius: 0.072, at: (0, 0.047, 0.023), scale: SCNVector3(0.90, 0.67, 1.40), material: feather)
        ellipsoid(duck, radius: 0.052, at: (0, 0.068, -0.055), scale: SCNVector3(1.07, 1.05, 0.94), material: breast)
        let tailNode = ellipsoid(duck, radius: 0.039, at: (0, 0.061, 0.111), scale: SCNVector3(0.70, 0.32, 0.90), material: tail)
        tailNode.eulerAngles.x = -0.25
        for side: CGFloat in [-1, 1] {
            let n = ellipsoid(duck, radius: 0.052, at: (side * 0.046, 0.059, 0.028), scale: SCNVector3(0.37, 0.60, 1.25), material: wing)
            n.eulerAngles.y = Float(side) * -0.16
            let border = ellipsoid(duck, radius: 0.026, at: (side * 0.0668, 0.071, 0.036),
                                   scale: SCNVector3(0.19, 0.46, 1.15), material: cream)
            border.eulerAngles.y = n.eulerAngles.y
            let patch = ellipsoid(duck, radius: 0.022, at: (side * 0.0704, 0.071, 0.036),
                                  scale: SCNVector3(0.16, 0.42, 1.12), material: blue)
            patch.eulerAngles.y = n.eulerAngles.y
            let foot = ellipsoid(duck, radius: 0.020, at: (side * 0.038, 0.003, 0.077),
                                 scale: SCNVector3(0.82, 0.12, 1.14), material: bill)
            foot.eulerAngles.y = Float(side) * 0.25
            if !UIAccessibility.isReduceMotionEnabled {
                let kick = SCNAction.sequence([.rotateBy(x: 0.38, y: 0, z: 0, duration: 0.40),
                                               .rotateBy(x: -0.38, y: 0, z: 0, duration: 0.55)])
                kick.timingMode = .easeInEaseOut
                foot.runAction(.sequence([.wait(duration: side < 0 ? 0 : 0.47), .repeatForever(kick)]))
            }
        }
        let head = SCNNode(); head.name = "pondDuckHead"; head.position = SCNVector3(0, 0.110, -0.084)
        duck.addChildNode(head)
        ellipsoid(head, radius: 0.032, at: (0, -0.010, 0.005), scale: SCNVector3(0.77, 1.15, 0.80), material: green)
        let collar = SCNTorus(ringRadius: 0.026, pipeRadius: 0.004)
        collar.ringSegmentCount = 12; collar.pipeSegmentCount = 5; collar.materials = [cream]
        let ring = SCNNode(geometry: collar); ring.position = SCNVector3(0, -0.012, 0.006); head.addChildNode(ring)
        ellipsoid(head, radius: 0.041, at: (0, 0.027, -0.014), scale: SCNVector3(0.88, 0.94, 1.02), material: green)
        ellipsoid(head, radius: 0.027, at: (0, 0.013, -0.065), scale: SCNVector3(0.87, 0.26, 1.21), material: bill)
        ellipsoid(head, radius: 0.024, at: (0, 0.007, -0.067), scale: SCNVector3(0.89, 0.07, 1.10), material: breast)
        for side: CGFloat in [-1, 1] {
            let eyes = SCNNode(); eyes.position = SCNVector3(side * 0.033, 0.037, -0.033); head.addChildNode(eyes)
            ellipsoid(eyes, radius: 0.0065, at: (0, 0, 0), scale: SCNVector3(0.52, 1, 1), material: eye)
            ellipsoid(eyes, radius: 0.0020, at: (side * 0.003, 0.002, -0.002), scale: SCNVector3(0.55, 1, 1), material: cream)
            ellipsoid(head, radius: 0.0025, at: (side * 0.012, 0.020, -0.065), scale: SCNVector3(1, 0.5, 1), material: breast)
            if !UIAccessibility.isReduceMotionEnabled {
                eyes.runAction(.repeatForever(.sequence([.wait(duration: 4.6),
                    .customAction(duration: 0.16) { node, elapsed in
                        node.scale.y = 1 - 0.88 * sin(Float(elapsed / 0.16) * .pi)
                    }])))
            }
        }
        if !UIAccessibility.isReduceMotionEnabled {
            head.runAction(.repeatForever(.sequence([
                .wait(duration: 3.4), .rotateTo(x: -0.10, y: 0.22, z: 0, duration: 0.8),
                .wait(duration: 1.2), .rotateTo(x: 0, y: -0.13, z: 0, duration: 1.0),
                .wait(duration: 2.2), .rotateTo(x: -0.24, y: 0, z: 0, duration: 0.8),
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.8)
            ])), forKey: "duckLookAround")
        }
        return duck
    }

    /// Elliptical route stays inside the narrow pond. The derivative determines
    /// heading, so the duck always swims bill-first, including around each end.
    nonisolated static func duckPose(at time: Float) -> (position: SIMD3<Float>, yaw: Float) {
        let angle = time / 28 * 2 * Float.pi
        let dx = -0.45 * sin(angle), dz = 0.135 * cos(angle)
        return (SIMD3(0.5 + 0.45 * cos(angle), 0.028, 0.135 * sin(angle)), atan2(-dx, -dz))
    }

    static func addSwimmingDuck(to root: SCNNode) {
        let swimmer = SCNNode(); swimmer.name = "pondDuckSwimmer"; root.addChildNode(swimmer)
        let pose = duckPose(at: 0); swimmer.simdPosition = pose.position; swimmer.eulerAngles.y = pose.yaw
        let duck = makeDuck(); swimmer.addChildNode(duck)
        let ripple = material(0.77, 0.88, 0.83); ripple.transparency = 0.38
        ripple.writesToDepthBuffer = false; ripple.isDoubleSided = true
        for side: CGFloat in [-1, 1] {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: side * 0.057, y: -0.047))
            path.addQuadCurve(to: CGPoint(x: side * 0.104, y: -0.167), controlPoint: CGPoint(x: side * 0.080, y: -0.110))
            path.addLine(to: CGPoint(x: side * 0.109, y: -0.167))
            path.addQuadCurve(to: CGPoint(x: side * 0.062, y: -0.047), controlPoint: CGPoint(x: side * 0.087, y: -0.110))
            path.close(); path.flatness = 0.003
            let geometry = SCNShape(path: path, extrusionDepth: 0.001); geometry.materials = [ripple]
            let wake = SCNNode(geometry: geometry); wake.eulerAngles.x = -.pi / 2
            wake.position.y = 0.001; wake.castsShadow = false; swimmer.addChildNode(wake)
        }
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        swimmer.runAction(.repeatForever(.customAction(duration: 28) { node, elapsed in
            let pose = duckPose(at: Float(elapsed))
            node.simdPosition = pose.position; node.eulerAngles.y = pose.yaw
        }), forKey: "duckSwim")
        let bob = SCNAction.sequence([.moveBy(x: 0, y: 0.003, z: 0, duration: 0.9),
                                     .moveBy(x: 0, y: -0.003, z: 0, duration: 0.9)])
        bob.timingMode = .easeInEaseOut; duck.runAction(.repeatForever(bob), forKey: "duckBob")
    }

    private static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .lambert
        m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1); return m
    }
    @discardableResult private static func box(_ root: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
        at p: (CGFloat, CGFloat, CGFloat), material: SCNMaterial, bevel: CGFloat = 0.003) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: d, chamferRadius: min(bevel, min(w, h, d) / 2))
        g.chamferSegmentCount = 2; g.materials = [material]
        let n = SCNNode(geometry: g); n.position = SCNVector3(p.0, p.1, p.2); root.addChildNode(n); return n
    }
    @discardableResult private static func ellipsoid(_ root: SCNNode, radius: CGFloat,
        at p: (CGFloat, CGFloat, CGFloat), scale: SCNVector3, material: SCNMaterial, segments: Int = 12) -> SCNNode {
        let g = SCNSphere(radius: radius); g.segmentCount = segments; g.materials = [material]
        let n = SCNNode(geometry: g); n.position = SCNVector3(p.0, p.1, p.2); n.scale = scale
        root.addChildNode(n); return n
    }
    private static func cylinder(_ root: SCNNode, radius: CGFloat, height: CGFloat,
        at p: (CGFloat, CGFloat, CGFloat), material: SCNMaterial) {
        let g = SCNCylinder(radius: radius, height: height); g.radialSegmentCount = 12; g.materials = [material]
        let n = SCNNode(geometry: g); n.position = SCNVector3(p.0, p.1, p.2); root.addChildNode(n)
    }
    private static func cone(_ root: SCNNode, top: CGFloat, bottom: CGFloat, height: CGFloat,
        at p: (CGFloat, CGFloat, CGFloat), material: SCNMaterial) {
        let g = SCNCone(topRadius: top, bottomRadius: bottom, height: height)
        g.radialSegmentCount = 10; g.materials = [material]
        let n = SCNNode(geometry: g); n.position = SCNVector3(p.0, p.1, p.2); root.addChildNode(n)
    }
    private static func beam(_ root: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) {
        let g = SCNCylinder(radius: radius, height: CGFloat(simd_length(b - a)))
        g.radialSegmentCount = 6; g.materials = [material]
        let n = SCNNode(geometry: g); n.simdPosition = (a + b) / 2
        n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(b - a)); root.addChildNode(n)
    }
    private static func frustum(_ root: SCNNode, bottom: Float, top: Float, lowY: Float, highY: Float, material: SCNMaterial) -> SCNNode {
        let points: [SIMD2<Float>] = [SIMD2(-1, 1), SIMD2(1, 1), SIMD2(1, -1), SIMD2(-1, -1)]
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [UInt16] = []
        for i in 0..<4 {
            let p = points[i], q = points[(i + 1) % 4]
            let face = [SIMD3(p.x * bottom, lowY, p.y * bottom), SIMD3(q.x * bottom, lowY, q.y * bottom),
                        SIMD3(q.x * top, highY, q.y * top), SIMD3(p.x * top, highY, p.y * top)]
            let normal = simd_normalize(simd_cross(face[1] - face[0], face[2] - face[0])); let b = UInt16(vertices.count)
            vertices += face.map { SCNVector3($0) }; normals += Array(repeating: SCNVector3(normal), count: 4)
            indices += [b, b + 1, b + 2, b, b + 2, b + 3]
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        g.materials = [material]; let n = SCNNode(geometry: g); root.addChildNode(n); return n
    }
}
