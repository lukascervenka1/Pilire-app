import SceneKit
import UIKit

/// Quiet, repeatable meadow dressing. World-based seeds keep existing patches in place on expansion.
enum MeadowGround {
    private struct Random {
        var state: UInt64
        init(_ x: Int, _ z: Int) {
            state = UInt64(bitPattern: Int64(x &* 73856093 ^ z &* 19349663)) &+ 0x9E3779B97F4A7C15
            _ = next()
        }
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
    }

    static func texture(width: CGFloat, cols: Int) -> UIImage {
        let px: CGFloat = 1536, unit = px/width
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size:CGSize(width:px,height:px),format:format).image { context in
            let c = context.cgContext
            c.setFillColor(UIColor(red:0.55,green:0.69,blue:0.43,alpha:1).cgColor)
            c.fill(CGRect(x:0,y:0,width:px,height:px))
            let margin = (width-CGFloat(cols))/2*unit
            for row in 0..<cols {
                for col in 0..<cols {
                    var random = Random(col-cols/2,row-cols/2)
                    let alpha = ((row+col)%2 == 0 ? CGFloat(0.030) : 0) + CGFloat(random.next())*0.008
                    c.setFillColor(UIColor(white:1,alpha:alpha).cgColor)
                    c.fill(CGRect(x:margin+CGFloat(col)*unit,y:margin+CGFloat(row)*unit,width:unit,height:unit))
                }
            }
            // Wide, overlapping changes in grass color, never hard circles or dirt stains.
            for z in -7...7 {
                for x in -7...7 {
                    var random = Random(x*7,z*11)
                    let point = CGPoint(x:px/2+(CGFloat(x)*2.1+CGFloat(random.next()))*unit,
                                        y:px/2+(CGFloat(z)*2.1+CGFloat(random.next()))*unit)
                    let warm = random.next() > 0.55
                    let color = UIColor(red:warm ? 0.76 : 0.35,green:warm ? 0.75 : 0.53,
                                        blue:warm ? 0.46 : 0.35,alpha:0.15).cgColor
                    let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),
                                              colors:[color,color.copy(alpha:0)!] as CFArray,locations:[0,1])!
                    c.saveGState(); c.translateBy(x:point.x,y:point.y)
                    c.scaleBy(x:1,y:0.65+CGFloat(random.next())*0.4)
                    c.drawRadialGradient(gradient,startCenter:.zero,startRadius:0,endCenter:.zero,
                                         endRadius:(0.85+CGFloat(random.next())*0.85)*unit,options:[])
                    c.restoreGState()
                }
            }
            // Small groups of blade marks in world units: no evenly scattered confetti.
            for z in -14...14 {
                for x in -14...14 {
                    var random = Random(x,z)
                    for _ in 0..<5 {
                        let cx = CGFloat(x)+CGFloat(random.next()), cz = CGFloat(z)+CGFloat(random.next())
                        let tint = random.next() > 0.5
                        c.setStrokeColor(UIColor(red:tint ? 0.72 : 0.36,green:tint ? 0.77 : 0.53,
                                               blue:tint ? 0.48 : 0.32,alpha:0.17).cgColor)
                        c.setLineWidth(0.008*unit); c.setLineCap(.round)
                        for _ in 0..<3 {
                            let bx = px/2+(cx+CGFloat(random.next())*0.075)*unit
                            let by = px/2+(cz+CGFloat(random.next())*0.055)*unit
                            c.move(to:CGPoint(x:bx,y:by))
                            c.addLine(to:CGPoint(x:bx+0.012*unit,y:by-(0.02+CGFloat(random.next())*0.025)*unit))
                        }
                        c.strokePath()
                    }
                }
            }
        }
    }

    private static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let m = SCNMaterial(); m.diffuse.contents = UIColor(red:r,green:g,blue:b,alpha:1)
        m.lightingModel = .lambert; return m
    }
    private static let greens = [material(0.40,0.55,0.32),material(0.49,0.62,0.37),material(0.59,0.66,0.41)]
    private static let stones = [material(0.62,0.63,0.56),material(0.72,0.70,0.60)]
    private static let cream = material(0.92,0.88,0.71)
    private static let pollen = material(0.79,0.65,0.33)

    static func details(cols: Int) -> [SCNNode] {
        var details: [SCNNode] = []
        for z in -(cols/2)..<(cols/2) {
            for x in -(cols/2)..<(cols/2) {
                var random = Random(x,z)
                guard random.next() < 0.30 else { continue }
                let root = SCNNode()
                root.position = SCNVector3(Float(x)+0.5+(random.next()-0.5)*0.48,0,
                                           Float(z)+0.5+(random.next()-0.5)*0.48)
                let kind = random.next()
                if kind < 0.48 {
                    // Tapered, bent blades replace upright cone spikes.
                    for i in 0..<6 {
                        let angle = Float(i)*2.4, height = 0.045+random.next()*0.065
                        let reach = 0.035+random.next()*0.05
                        var vertices: [SCNVector3] = []
                        for j in 0...3 {
                            let t = Float(j)/3, width = (1-t)*0.013+0.0008
                            let bx = cos(angle)*reach*t*t, bz = sin(angle)*reach*t*t
                            vertices += [SCNVector3(bx-sin(angle)*width,height*t,bz+cos(angle)*width),
                                         SCNVector3(bx+sin(angle)*width,height*t,bz-cos(angle)*width)]
                        }
                        let indices: [Int32] = [0,1,2,1,3,2,2,3,4,3,5,4,4,5,6,5,7,6]
                        let geometry = SCNGeometry(sources:[.init(vertices:vertices)],elements:[.init(indices:indices,primitiveType:.triangles)])
                        let mat = greens[i%3]; mat.isDoubleSided = true; geometry.materials = [mat]
                        root.addChildNode(SCNNode(geometry:geometry))
                    }
                } else if kind < 0.72 {
                    for i in 0..<3 {
                        let radius = CGFloat(0.024+random.next()*0.023)
                        let rock = SCNSphere(radius:radius); rock.segmentCount = 6; rock.materials = [stones[i%2]]
                        let node = SCNNode(geometry:rock)
                        node.position = SCNVector3(Float(i-1)*0.058,Float(radius)*0.38,(random.next()-0.5)*0.055)
                        node.scale = SCNVector3(1.2,0.58,0.83); node.eulerAngles.y = random.next()*6.28
                        root.addChildNode(node)
                    }
                } else {
                    for i in 0..<3 {
                        let cx = (random.next()-0.5)*0.15, cz = (random.next()-0.5)*0.12
                        for j in 0..<3 {
                            let a = Float(j)*2.094+Float(i)
                            let leaf = SCNSphere(radius:0.023); leaf.segmentCount = 6; leaf.materials = [greens[(i+j)%2]]
                            let node = SCNNode(geometry:leaf)
                            node.position = SCNVector3(cx+cos(a)*0.015,0.014,cz+sin(a)*0.015)
                            node.scale = SCNVector3(1,0.22,0.72); node.eulerAngles.y = -a
                            root.addChildNode(node)
                        }
                        if kind > 0.90 && i < 2 {
                            let stalk = SCNCylinder(radius:0.003,height:0.045); stalk.radialSegmentCount = 5; stalk.materials = [greens[0]]
                            let stem = SCNNode(geometry:stalk); stem.position = SCNVector3(cx,0.025,cz); root.addChildNode(stem)
                            for j in 0..<5 {
                                let a = Float(j)*2 * .pi/5
                                let petal = SCNSphere(radius:0.010); petal.segmentCount = 6; petal.materials = [cream]
                                let node = SCNNode(geometry:petal); node.position = SCNVector3(cx+cos(a)*0.010,0.050,cz+sin(a)*0.010)
                                node.scale.y = 0.35; root.addChildNode(node)
                            }
                            let heart = SCNSphere(radius:0.005); heart.segmentCount = 6; heart.materials = [pollen]
                            let node = SCNNode(geometry:heart); node.position = SCNVector3(cx,0.054,cz); root.addChildNode(node)
                        }
                    }
                }
                root.name = "meadowSample"
                root.enumerateHierarchy { node,_ in node.categoryBitMask = TownScene.decorCategory; node.castsShadow = false }
                details.append(root)
            }
        }
        return details
    }
}
