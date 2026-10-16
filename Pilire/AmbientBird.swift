import SceneKit
import simd
import UIKit

/// Small faceted songbirds, with the same muted materials as the town.
/// +Z is the beak; each wing rotates at its shoulder, with quiet glides between flaps.
final class AmbientBirdNode: SCNNode {
    enum Kind { case swallow, sparrow }
    private let leftWing = SCNNode()
    private let rightWing = SCNNode()
    private let head = SCNNode()

    init(kind: Kind = .swallow, flying: Bool = true) {
        super.init()
        let back = material(kind == .swallow
            ? UIColor(red: 0.32, green: 0.43, blue: 0.49, alpha: 1)
            : UIColor(red: 0.53, green: 0.43, blue: 0.33, alpha: 1))
        let feather = material(kind == .swallow
            ? UIColor(red: 0.40, green: 0.52, blue: 0.57, alpha: 1)
            : UIColor(red: 0.63, green: 0.52, blue: 0.39, alpha: 1))
        let tip = material(UIColor(red: 0.27, green: 0.35, blue: 0.38, alpha: 1))
        let breast = material(UIColor(red: 0.91, green: 0.86, blue: 0.73, alpha: 1))
        let beak = material(UIColor(red: 0.64, green: 0.46, blue: 0.28, alpha: 1))
        let eye = material(UIColor(red: 0.14, green: 0.19, blue: 0.20, alpha: 1))
        addChildNode(ellipsoid(radius: 0.065, scale: SCNVector3(0.80,0.85,1.65), material: back))
        let belly = ellipsoid(radius: 0.055, scale: SCNVector3(0.78,0.63,1.50), material: breast)
        belly.position = SCNVector3(0,-0.023,0.017)
        addChildNode(belly)
        head.position = SCNVector3(0,0.036,0.088)
        head.addChildNode(ellipsoid(radius: 0.043, scale: SCNVector3(0.92,0.92,1.04), material: back))
        let cheek = ellipsoid(radius: 0.029, scale: SCNVector3(1,0.67,0.90), material: breast)
        cheek.position = SCNVector3(0,-0.014,0.020);head.addChildNode(cheek)
        let bill = SCNCone(topRadius: 0, bottomRadius: 0.014, height: 0.043)
        bill.radialSegmentCount = 4;bill.materials = [beak]
        let billNode = SCNNode(geometry: bill)
        billNode.position = SCNVector3(0,0,0.056);billNode.eulerAngles.x = .pi/2
        head.addChildNode(billNode)
        for side: Float in [-1,1] {
            let dot = ellipsoid(radius: 0.007, scale: SCNVector3(0.65,1,1), material: eye)
            dot.position = SCNVector3(side*0.036,0.009,0.019);head.addChildNode(dot)
        }
        addChildNode(head)
        for (wing,side): (SCNNode,Float) in [(leftWing,-1),(rightWing,1)] {
            wing.name = side < 0 ? "leftWing" : "rightWing"
            wing.position = SCNVector3(side*0.034,0.013,0.018)
            let outline: [SIMD3<Float>] = [
                [0,0,0.035], [side*0.11,0.013,0.026], [side*0.23,0.003,-0.045],
                [side*0.32,-0.008,-0.15], [side*0.17,-0.002,-0.115],
                [side*0.07,0,-0.095], [0,0,-0.055],
            ]
            wing.addChildNode(SCNNode(geometry: Self.featherMesh(outline, thickness: 0.008,
                                                               materials: [feather,tip])))
            addChildNode(wing)
        }
        // Two tapered tail feathers give the flying silhouette its fork.
        for side: Float in [-1,1] {
            let outline: [SIMD3<Float>] = [[side*0.006,0,-0.073], [side*0.047,0.006,-0.23],
                                         [side*0.009,0,-0.175], [0,0,-0.115]]
            addChildNode(SCNNode(geometry: Self.featherMesh(outline, thickness: 0.006,
                                                         materials: [back,tip])))
        }
        enumerateHierarchy { node,_ in
            node.castsShadow = false
            node.categoryBitMask = TownScene.decorCategory
        }
        if flying { startFlying() } else { foldWings() }
    }

    required init?(coder: NSCoder) { nil }

    private func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial();material.lightingModel = .lambert
        material.diffuse.contents = color;material.roughness.contents = 1
        return material
    }

    private func ellipsoid(radius: CGFloat, scale: SCNVector3, material: SCNMaterial) -> SCNNode {
        let geometry = SCNSphere(radius: radius);geometry.segmentCount = 8
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry);node.scale = scale
        return node
    }

    /// Closed faceted feathers: separate triangle normals retain the low-poly shading.
    private static func featherMesh(_ outline: [SIMD3<Float>], thickness: Float,
                                    materials: [SCNMaterial]) -> SCNGeometry {
        let winding = outline.indices.reduce(Float(0)) { sum,i in
            let a = outline[i], b = outline[(i+1)%outline.count]
            return sum + a.z*b.x-a.x*b.z
        }
        let outline = winding >= 0 ? outline : Array(outline.reversed())
        let center = outline.reduce(SIMD3<Float>.zero,+)/Float(outline.count) + SIMD3(0,thickness,0)
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [[Int32]] = [[],[]]
        func triangle(_ a: SIMD3<Float>,_ b: SIMD3<Float>,_ c: SIMD3<Float>, tip: Bool = false) {
            let normal = simd_normalize(simd_cross(b-a,c-a))
            let first = Int32(vertices.count)
            vertices += [SCNVector3(a),SCNVector3(b),SCNVector3(c)]
            normals += Array(repeating: SCNVector3(normal), count: 3)
            indices[tip ? 1 : 0] += [first,first+1,first+2]
        }
        let down = SIMD3<Float>(0,-thickness,0)
        for i in outline.indices {
            let a = outline[i], b = outline[(i+1)%outline.count]
            triangle(center,a,b,tip: i == 2 || i == 3)
            triangle(center+down,b+down,a+down)
            triangle(a,b,b+down);triangle(a,b+down,a+down)
        }
        let elements = indices.map { SCNGeometryElement(indices:$0,primitiveType:.triangles) }
        let geometry = SCNGeometry(sources:[.init(vertices:vertices),.init(normals:normals)],elements:elements)
        geometry.materials = materials.map { material in
            let copy = material.copy() as! SCNMaterial;copy.isDoubleSided = true;return copy
        }
        return geometry
    }

    func startFlying() {
        for (wing,side): (SCNNode,CGFloat) in [(leftWing,-1),(rightWing,1)] {
            wing.removeAllActions()
            let down = SCNAction.rotateTo(x:0,y:0,z:side * -0.48,duration:0.18)
            let up = SCNAction.rotateTo(x:0,y:0,z:side * 0.62,duration:0.29)
            let glide = SCNAction.rotateTo(x:0,y:0,z:side * 0.08,duration:0.32)
            down.timingMode = .easeInEaseOut;up.timingMode = .easeInEaseOut;glide.timingMode = .easeOut
            wing.runAction(.repeatForever(.sequence([up,down,up,down,glide,.wait(duration:1.65)])),forKey:"wingbeat")
        }
    }

    func foldWings() {
        for (wing,side): (SCNNode,CGFloat) in [(leftWing,-1),(rightWing,1)] {
            wing.removeAllActions()
            wing.runAction(.group([.scale(to:0.44,duration:0.25),
                                   .rotateTo(x:0,y:side*0.30,z:side * -1.05,duration:0.25)]))
        }
    }

    private func peck() -> SCNAction {
        .sequence([.rotateTo(x:0.42,y:0,z:0,duration:0.18),
                   .wait(duration:0.16),.rotateTo(x:0,y:0,z:0,duration:0.25)])
    }

    func startPecking() {
        head.runAction(.repeatForever(.sequence([.wait(duration:1.1),peck(),.wait(duration:1.8)])))
    }
}
