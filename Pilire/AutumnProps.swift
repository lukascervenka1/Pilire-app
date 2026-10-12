import SceneKit
import UIKit
import simd

/// Shared small autumn models, used by both the seasonal house and map decorations.
enum AutumnProps {
    static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let m = SCNMaterial(); m.diffuse.contents = UIColor(red:r,green:g,blue:b,alpha:1); m.lightingModel = .lambert; return m
    }

    @discardableResult static func beam(_ root: SCNNode, _ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let v = b-a
        let shape = SCNCylinder(radius:radius,height:CGFloat(simd_length(v))); shape.radialSegmentCount = 6; shape.materials = [material]
        let node = SCNNode(geometry:shape); node.simdPosition = (a+b)/2
        node.simdOrientation = simd_quatf(from:SIMD3(0,1,0),to:simd_normalize(v)); root.addChildNode(node); return node
    }

    static func pumpkin(radius r: Float, variant: Int = 0, carved: Bool = true) -> SCNNode {
        let root = SCNNode()
        let skin = [material(0.79,0.37,0.14),material(0.88,0.48,0.20),material(0.67,0.45,0.26)][variant%3]
        let stem = material(0.36,0.40,0.24)
        // A single continuous, eight-lobed body: grooves follow the shape, not overlaid spheres.
        let slices = 48, rings = 16
        func point(_ phi: Float, _ theta: Float) -> SCNVector3 {
            let radial = r * pow(max(0,sin(phi)),0.78) * (1+0.075*cos(theta*8))
            return SCNVector3(sin(theta)*radial, r*0.77*(1-cos(phi)), cos(theta)*radial)
        }
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        for j in 0...rings {
            let p = Float(j)/Float(rings) * .pi
            for i in 0...slices {
                let t = Float(i)/Float(slices) * 2 * .pi
                let v = point(p,t); vertices.append(v)
                let left = SIMD3<Float>(point(p,t-0.001)), right = SIMD3<Float>(point(p,t+0.001))
                let down = SIMD3<Float>(point(max(0.001,p-0.001),t)), up = SIMD3<Float>(point(min(.pi-0.001,p+0.001),t))
                let n = j == 0 ? SIMD3<Float>(0,-1,0) : (j == rings ? SIMD3<Float>(0,1,0) : simd_normalize(simd_cross(right-left,up-down)))
                normals.append(SCNVector3(n))
                if j < rings && i < slices {
                    let a = Int32(j*(slices+1)+i), b = a+Int32(slices+1)
                    indices += [a,a+1,b,a+1,b+1,b]
                }
            }
        }
        let geometry = SCNGeometry(sources:[.init(vertices:vertices),.init(normals:normals)],elements:[.init(indices:indices,primitiveType:.triangles)])
        skin.isDoubleSided = true; geometry.materials = [skin]; root.addChildNode(SCNNode(geometry:geometry))
        beam(root,SIMD3(0,r*1.47,0),SIMD3(r*0.10,r*1.91,-r*0.06),radius:CGFloat(r*0.11),material:stem)
        // Carved shapes follow the curved skin, avoiding floating flat faces.
        if carved {
            let cavity = material(0.26,0.17,0.11)
            let candle = material(1,0.74,0.30)
            candle.emission.contents = UIColor(red:0.28,green:0.12,blue:0.025,alpha:1)
            candle.lightingModel = .constant
            func facePoint(_ p: SIMD2<Float>, depth: Float) -> SCNVector3 {
                let y = p.y*r, x = p.x*r
                let phi = acos(max(-0.999,min(0.999,1-y/(r*0.77))))
                let radius = r*pow(sin(phi),0.78)
                var z = sqrt(max(0.001*r*r,radius*radius-x*x))
                for _ in 0..<4 {
                    let actual = radius*(1+0.075*cos(atan2(x,z)*8))
                    z = sqrt(max(0.001*r*r,actual*actual-x*x))
                }
                return SCNVector3(x,y,z+depth)
            }
            func face(_ outline: [SIMD2<Float>], material: SCNMaterial, inset: Float) {
                let center = outline.reduce(SIMD2<Float>.zero,+)/Float(outline.count)
                let points = outline.map { center+($0-center)*inset }
                var faceVertices: [SCNVector3] = []
                // Subdivide each triangle so even the wide smile stays against the curved pumpkin.
                func triangle(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, level: Int) {
                    if level == 0 {
                        faceVertices += [facePoint(a,depth:r*(inset == 1 ? 0.045 : 0.095)),facePoint(b,depth:r*(inset == 1 ? 0.045 : 0.095)),facePoint(c,depth:r*(inset == 1 ? 0.045 : 0.095))]
                    } else {
                        let ab = (a+b)/2, bc = (b+c)/2, ca = (c+a)/2
                        triangle(a,ab,ca,level:level-1); triangle(ab,b,bc,level:level-1)
                        triangle(ca,bc,c,level:level-1); triangle(ab,bc,ca,level:level-1)
                    }
                }
                for i in points.indices { triangle(center,points[i],points[(i+1)%points.count],level:2) }
                let g = SCNGeometry(sources:[.init(vertices:faceVertices)],elements:[.init(indices:(0..<faceVertices.count).map(Int32.init),primitiveType:.triangles)])
                material.isDoubleSided = true; g.materials = [material]; root.addChildNode(SCNNode(geometry:g))
            }
            let outlines: [[SIMD2<Float>]] = [
                [SIMD2(-0.54,0.90),SIMD2(-0.19,0.86),SIMD2(-0.35,1.16)],
                [SIMD2(0.19,0.86),SIMD2(0.54,0.90),SIMD2(0.35,1.16)],
                [SIMD2(-0.54,0.66),SIMD2(-0.30,0.61),SIMD2(0,0.59),SIMD2(0.30,0.61),SIMD2(0.54,0.66),SIMD2(0.32,0.39),SIMD2(0,0.34),SIMD2(-0.32,0.39)]
            ]
            for polygon in outlines { face(polygon,material:cavity,inset:1); face(polygon,material:candle,inset:0.77) }
        }
        let leafPath = UIBezierPath(); leafPath.move(to:.zero)
        leafPath.addLine(to:CGPoint(x:0.45,y:0.23)); leafPath.addLine(to:CGPoint(x:0.85,y:0.03))
        leafPath.addLine(to:CGPoint(x:0.40,y:-0.16)); leafPath.close()
        let leaf = SCNShape(path:leafPath,extrusionDepth:0.015); leaf.materials = [stem]
        let leafNode = SCNNode(geometry:leaf); leafNode.scale = SCNVector3(r,r,r); leafNode.eulerAngles.x = -.pi/2
        leafNode.position = SCNVector3(0,r*1.48,0); root.addChildNode(leafNode)
        return root
    }

    static func crow() -> SCNNode {
        let root = SCNNode(), dark = material(0.20,0.23,0.27), wing = material(0.27,0.30,0.33), beak = material(0.42,0.40,0.30)
        func oval(_ radius: CGFloat, _ position: SCNVector3, _ scale: SCNVector3, _ mat: SCNMaterial) {
            let g = SCNSphere(radius:radius); g.segmentCount = 10; g.materials = [mat]
            let n = SCNNode(geometry:g); n.position = position; n.scale = scale; root.addChildNode(n)
        }
        for x: Float in [-0.015,0.015] {
            beam(root,SIMD3(x,0,0),SIMD3(x,0.038,0),radius:0.004,material:beak)
            beam(root,SIMD3(x,0.004,-0.009),SIMD3(x,0.004,0.022),radius:0.004,material:beak)
        }
        oval(0.042,SCNVector3(0,0.064,0),SCNVector3(0.83,1.12,1.28),dark)
        oval(0.027,SCNVector3(0,0.109,0.028),SCNVector3(1,1,1),dark)
        for x: Float in [-0.030,0.030] { oval(0.028,SCNVector3(x,0.06,-0.008),SCNVector3(0.25,1,1.5),wing) }
        beam(root,SIMD3(0,0.05,-0.030),SIMD3(0,0.031,-0.095),radius:0.013,material:dark)
        let bill = SCNCone(topRadius:0,bottomRadius:0.012,height:0.036); bill.radialSegmentCount = 5; bill.materials = [beak]
        let node = SCNNode(geometry:bill); node.position = SCNVector3(0,0.11,0.066); node.eulerAngles.x = .pi/2; root.addChildNode(node)
        for x: Float in [-0.023,0.023] { oval(0.004,SCNVector3(x,0.115,0.039),SCNVector3(1,1,1),material(0.83,0.80,0.64)) }
        return root
    }
}
