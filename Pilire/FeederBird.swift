import SceneKit
import UIKit
import simd

/// A compact sparrow built for close-up feeding. Origin is between the planted
/// feet, +Z points through the bill. Flight and feeding share one continuous pose.
final class FeederBirdNode: SCNNode {
    override init() {
        super.init()
        name = "feederBird"
        let back = FeederGeometry.material(0.51, 0.40, 0.29)
        let cap = FeederGeometry.material(0.41, 0.31, 0.23)
        let wing = FeederGeometry.material(0.39, 0.36, 0.30)
        let feather = FeederGeometry.material(0.64, 0.53, 0.38)
        let breast = FeederGeometry.material(0.83, 0.77, 0.61)
        let cream = FeederGeometry.material(0.94, 0.87, 0.69)
        let dark = FeederGeometry.material(0.17, 0.19, 0.16)
        let bill = FeederGeometry.material(0.64, 0.49, 0.30)
        let feet = FeederGeometry.material(0.48, 0.36, 0.26)
        let body = SCNNode(); body.name = "feederBody"; body.position.y = 0.050; addChildNode(body)
        FeederGeometry.ellipsoid(body, 0.044, at: [0,0,-0.013], scale: [0.88,0.98,1.27], material: back)
        FeederGeometry.ellipsoid(body, 0.034, at: [0,-0.001,0.014], scale: [0.94,1.04,0.98], material: breast)
        let tail = SCNNode(); tail.name = "feederTail"; tail.position = SCNVector3(0,0.051,-0.054); addChildNode(tail)
        for side: Float in [-1,1] {
            FeederGeometry.ellipsoid(tail, 0.031, at: [side*0.009,0,-0.035], scale: [0.39,0.14,1.45], material: wing)
            let folded = SCNNode(); folded.name = "feederFolded\(Int(side))"; body.addChildNode(folded)
            let cover = FeederGeometry.ellipsoid(folded, 0.035, at: [side*0.031,0.009,-0.018],
                                                 scale: [0.31,0.75,1.43], material: wing)
            cover.eulerAngles.y = -side*0.18
            for z: Float in [-0.012, -0.030] {
                let bar = FeederGeometry.ellipsoid(folded, 0.017, at: [side*0.041,0.015,z],
                    scale: [0.18,0.72,0.20], material: feather)
                bar.eulerAngles.x = -0.42
            }
            let flying = SCNNode(); flying.name = "feederFlying\(Int(side))"
            flying.position = SCNVector3(side*0.028,0.064,0); addChildNode(flying)
            let outline: [CGPoint] = [CGPoint(x:0,y:0.030),CGPoint(x:CGFloat(side)*0.064,y:0.029),
                CGPoint(x:CGFloat(side)*0.163,y:-0.043),CGPoint(x:CGFloat(side)*0.113,y:-0.087),CGPoint(x:0,y:-0.049)]
            let path = UIBezierPath(); path.move(to:outline[0]); outline.dropFirst().forEach { path.addLine(to:$0) }; path.close()
            let g = SCNShape(path:path,extrusionDepth:0.004); g.chamferRadius = 0.001; g.materials = [wing]
            let spread = SCNNode(geometry:g); spread.eulerAngles.x = .pi/2; flying.addChildNode(spread)
            for i in 0..<3 {
                let plumage = FeederGeometry.ellipsoid(flying, 0.021, at: [side*(0.067+Float(i)*0.025),0.002,-0.029-Float(i)*0.010],
                    scale: [0.31,0.13,1.40], material: feather, segments: 8)
                plumage.eulerAngles.y = -side*0.55
            }
            let leg = SCNNode(); leg.name = "feederFoot\(Int(side))"; addChildNode(leg)
            FeederGeometry.beam(leg, [side*0.020,0.034,-0.004], [side*0.021,0.004,0.006], radius:0.0026, material:feet)
            for toe: Float in [-1,0,1] {
                FeederGeometry.beam(leg, [side*0.021,0.002,0.006],
                    [side*0.021+toe*0.009,0.002,0.026-abs(toe)*0.004], radius:0.0018, material:feet)
            }
            FeederGeometry.beam(leg, [side*0.021,0.002,0.006], [side*0.023,0.002,-0.012], radius:0.0017, material:feet)
        }
        let head = SCNNode(); head.name = "feederHead"; addChildNode(head)
        FeederGeometry.ellipsoid(head, 0.032, at: [0,0,0], scale: [0.96,0.95,1.02], material: back)
        FeederGeometry.ellipsoid(head, 0.029, at: [0,0.010,-0.002], scale: [1.03,0.69,1.04], material: cap)
        FeederGeometry.ellipsoid(head, 0.018, at: [0,-0.019,0.018], scale: [0.74,0.65,0.82], material: dark)
        for side: Float in [-1,1] {
            FeederGeometry.ellipsoid(head, 0.017, at: [side*0.025,-0.006,0.010], scale: [0.42,0.76,1.12], material:cream)
            let eye = SCNNode(); eye.name = "feederEye\(Int(side))"
            eye.position = SCNVector3(side*0.028,0.008,0.017); head.addChildNode(eye)
            FeederGeometry.ellipsoid(eye, 0.0048, at: .zero, scale: [0.58,1,1], material:dark)
            FeederGeometry.ellipsoid(eye, 0.0014, at: [side*0.0027,0.0015,0.001], scale: [0.5,1,1], material:cream)
        }
        let upper = SCNCone(topRadius:0,bottomRadius:0.010,height:0.028)
        upper.radialSegmentCount = 4; upper.materials = [bill]
        let upperNode = SCNNode(geometry:upper); upperNode.position = SCNVector3(0,-0.004,0.047)
        upperNode.eulerAngles.x = .pi/2; head.addChildNode(upperNode)
        let tip = SCNNode(); tip.name = "feederBillTip"; tip.simdPosition = Self.billTip; head.addChildNode(tip)
        let jaw = SCNNode(); jaw.name = "feederJaw"; jaw.position = SCNVector3(0,-0.009,0.033); head.addChildNode(jaw)
        let lower = SCNCone(topRadius:0,bottomRadius:0.006,height:0.024)
        lower.radialSegmentCount = 4; lower.materials = [bill]
        let lowerNode = SCNNode(geometry:lower); lowerNode.position.z = 0.012; lowerNode.eulerAngles.x = .pi/2
        jaw.addChildNode(lowerNode)
        let grain = FeederGeometry.ellipsoid(head, 0.0052, at: Self.billTip + [0,-0.002,0.001],
            scale: [0.7,0.65,1.05], material:FeederGeometry.material(0.87,0.73,0.43), segments:6)
        grain.name = "feederHeldSeed"
        enumerateHierarchy { node, _ in node.castsShadow = false; node.categoryBitMask = TownScene.decorCategory }
        Self.apply(at: 0, to: self)
    }
    required init?(coder: NSCoder) { nil }
    nonisolated static let billTip = SIMD3<Float>(0,-0.004,0.061)

    func startVisits() {
        guard action(forKey:"feederVisit") == nil else { return }
        let visit = SCNAction.customAction(duration:Double(FeederVisit.duration)) { node, elapsed in
            Self.apply(at:Float(elapsed), to:node)
        }
        runAction(.sequence([.wait(duration:6,withRange:8), .repeatForever(.sequence([
            visit, .run { Self.apply(at:0,to:$0) }, .wait(duration:26,withRange:16)
        ]))]), forKey:"feederVisit")
    }

    /// Render-thread work touches only SceneKit nodes; no SwiftData or UI state.
    nonisolated static func apply(at time: Float, to bird: SCNNode) {
        let pose = FeederVisit.pose(at:time)
        bird.simdPosition = pose.position; bird.eulerAngles = SCNVector3(pose.pitch,pose.yaw,pose.bank)
        bird.opacity = CGFloat(pose.opacity)
        guard let head = bird.childNode(withName:"feederHead",recursively:false),
              let body = bird.childNode(withName:"feederBody",recursively:false) else { return }
        let grain = BirdFeederModel.seeds[pose.bite]
        // Solve the fully dipped head position from the actual bill-tip offset.
        // Both feet stay planted while the neck reaches the chosen grain.
        let angle: Float = 0.92
        let rotatedTip = SIMD3<Float>(0, Self.billTip.y*cos(angle)-Self.billTip.z*sin(angle),
                                       Self.billTip.y*sin(angle)+Self.billTip.z*cos(angle))
        let delta = grain-BirdFeederModel.perch, yaw = BirdFeederModel.perchYaw
        let localGrain = SIMD3<Float>(cos(yaw)*delta.x-sin(yaw)*delta.z, delta.y,
                                     sin(yaw)*delta.x+cos(yaw)*delta.z)
        let contactHead = localGrain-rotatedTip
        head.simdPosition = SIMD3(0,0.098,0.028)*(1-pose.peck) + contactHead*pose.peck
        head.eulerAngles = SCNVector3(angle*pose.peck,pose.look*(1-pose.peck),0)
        body.position.y = 0.050 - pose.peck*0.006 + sin(time*3)*0.0008*(1-pose.peck)
        body.eulerAngles.x = 0.13*pose.peck
        bird.childNode(withName:"feederTail",recursively:false)?.eulerAngles.x = -0.10 + 0.19*pose.peck + 0.025*sin(time*4)
        head.childNode(withName:"feederHeldSeed",recursively:false)?.isHidden = !pose.holdingSeed
        head.childNode(withName:"feederJaw",recursively:false)?.eulerAngles.x = pose.chew
        for side in [-1,1] {
            body.childNode(withName:"feederFolded\(side)",recursively:false)?.opacity = CGFloat(1-pose.spread)
            if let flying = bird.childNode(withName:"feederFlying\(side)",recursively:false) {
                flying.opacity = CGFloat(pose.spread)
                flying.eulerAngles.z = Float(side)*(0.15+0.85*sin(time*24))*pose.spread
            }
            bird.childNode(withName:"feederFoot\(side)",recursively:false)?.eulerAngles.x = -0.5*pose.spread
            head.childNode(withName:"feederEye\(side)",recursively:false)?.scale.y = pose.blink
        }
        for i in BirdFeederModel.seeds.indices {
            bird.parent?.childNode(withName:"feederSeed\(i)",recursively:false)?.isHidden = i < pose.eaten
        }
    }
}

/// Deterministic choreography makes contact and takeoff inspectable at any frame.
enum FeederVisit {
    nonisolated static let duration: Float = 12.4
    nonisolated static let bites: [Float] = [3.1, 4.25, 5.9, 7.05, 8.5]
    nonisolated struct Pose {
        var position = BirdFeederModel.perch
        var yaw: Float = BirdFeederModel.perchYaw, pitch: Float = 0, bank: Float = 0
        var opacity: Float = 1, spread: Float = 0, peck: Float = 0
        var look: Float = 0, chew: Float = 0, blink: Float = 1
        var bite = 0, eaten = 0
        var holdingSeed = false
    }
    nonisolated static func smooth(_ value: Float) -> Float {
        let t = min(1,max(0,value)); return t*t*(3-2*t)
    }
    nonisolated static func curve(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let u = 1-t; return u*u*u*a + 3*u*u*t*b + 3*u*t*t*c + t*t*t*d
    }
    nonisolated static func pose(at time: Float) -> Pose {
        let t = max(0,min(duration,time))
        var p = Pose()
        let forward = SIMD3<Float>(sin(BirdFeederModel.perchYaw),0,cos(BirdFeederModel.perchYaw))
        let approach = BirdFeederModel.perch-forward*0.31
        p.look = 0.22*sin(t*2.0)
        if t < 2.4 {
            let progress = t/2.4
            p.position = curve([-0.80,1.28,1.30], [-0.50,0.88,0.85], approach, BirdFeederModel.perch, progress)
            let next = curve([-0.80,1.28,1.30], [-0.50,0.88,0.85], approach, BirdFeederModel.perch, min(1,progress+0.001))
            let delta = next-p.position
            p.yaw = atan2(delta.x,delta.z)
            p.pitch = 0.12*sin(progress * .pi); p.bank = -0.10*sin(progress * .pi)
            p.spread = 1-smooth((progress-0.64)/0.27)
            p.opacity = smooth(t/0.30); p.look = 0
        } else if t >= 10.1 {
            let progress = (t-10.1)/(duration-10.1)
            let exit = approach+SIMD3<Float>(0,0.012,0)
            p.position = curve(BirdFeederModel.perch, exit, [-0.68,0.97,0.93], [-1.25,1.40,1.22], progress)
            let next = curve(BirdFeederModel.perch, exit, [-0.68,0.97,0.93], [-1.25,1.40,1.22], min(1,progress+0.001))
            let delta = next-p.position
            p.yaw = atan2(delta.x,delta.z); p.pitch = -0.16*sin(progress * .pi)
            p.bank = 0.12*sin(progress * .pi); p.spread = smooth(progress/0.25)
            p.opacity = 1-smooth((progress-0.83)/0.17); p.look = 0
        } else if t >= 9.55 {
            let turn = (t-9.55)/0.55
            p.yaw = BirdFeederModel.perchYaw - .pi*smooth(turn); p.look = 0
            p.position.y += 0.012*sin(turn * .pi)
        }
        for (i, start) in bites.enumerated() where t >= start {
            let local = t-start; p.bite = i
            if local >= 0.28 { p.eaten = i+1 }
            guard local < 0.95 else { continue }
            p.peck = local < 0.24 ? smooth(local/0.24) : (local < 0.33 ? 1 : 1-smooth((local-0.33)/0.28))
            p.holdingSeed = local >= 0.28 && local < 0.78
            if local >= 0.61 && local < 0.86 { p.chew = 0.15*abs(sin((local-0.61)/0.25 * .pi*2)) }
            p.look = 0
        }
        for start: Float in [2.8, 6.95, 9.45] where t >= start && t < start+0.14 {
            p.blink = 1-0.92*sin((t-start)/0.14 * .pi)
        }
        return p
    }
}
