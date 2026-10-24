// Standalone simulator harness using a separate bundle and a temporary town.
// Link to the Debug app module. --demo runs only the close-up animation.
import SwiftUI
import SceneKit
import simd
@testable import Pilire

@MainActor @Observable final class FeederCheck {
    let scene = SCNScene()
    let camera = SCNNode()
    let feeder = DecorationNode(type: .birdFeeder, gridX: 0, gridY: 0)
    let bird = FeederBirdNode()
    var view: SCNView?
    init() {
        UserDefaults.standard.set("sunny", forKey:"screenshotWeather")
        UserDefaults.standard.set("14", forKey:"screenshotHour")
        scene.background.contents = UIColor(red:0.89,green:0.91,blue:0.84,alpha:1)
        let ground = SCNNode(geometry:SCNCylinder(radius:0.52,height:0.018))
        ground.position.y = -0.012; ground.geometry!.firstMaterial!.diffuse.contents = UIColor(red:0.57,green:0.68,blue:0.42,alpha:1)
        scene.rootNode.addChildNode(ground)
        scene.rootNode.addChildNode(feeder); feeder.addChildNode(bird)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional
        sun.light!.intensity = 950; sun.light!.castsShadow = true; sun.light!.shadowRadius = 5
        sun.light!.shadowColor = UIColor(white:0,alpha:0.16); sun.eulerAngles = SCNVector3(-0.9,-0.6,0); scene.rootNode.addChildNode(sun)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient
        ambient.light!.intensity = 650; ambient.light!.color = UIColor(red:0.88,green:0.92,blue:0.96,alpha:1); scene.rootNode.addChildNode(ambient)
        let rig = SCNNode(); rig.position = SCNVector3(0,0.46,0); rig.eulerAngles = SCNVector3(-0.36,0.56,0)
        camera.camera = SCNCamera(); camera.camera!.usesOrthographicProjection = true
        camera.camera!.orthographicScale = 0.78; camera.position.z = 12
        rig.addChildNode(camera); scene.rootNode.addChildNode(rig)
    }
    func save(_ name: String, at time: Float) {
        FeederBirdNode.apply(at:time,to:bird)
        SCNTransaction.flush()
        let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = scene; renderer.pointOfView = camera
        let image = renderer.snapshot(atTime:0,with:CGSize(width:1100,height:1100),antialiasingMode:.multisampling4X)
        try! image.pngData()!.write(to:URL.documentsDirectory.appending(path:name+".png"))
    }
    func verify() {
        var contacts = 0
        for rotation in 0..<4 {
            feeder.eulerAngles.y = Float(rotation) * .pi/2
            for (i, start) in FeederVisit.bites.enumerated() {
                FeederBirdNode.apply(at:start+0.26,to:bird)
                let tip = bird.childNode(withName:"feederBillTip",recursively:true)!
                let position = tip.simdConvertPosition(.zero,to:scene.rootNode)
                let target = feeder.simdConvertPosition(BirdFeederModel.seeds[i],to:scene.rootNode)
                precondition(simd_distance(position,target) < 0.00001, "Bill misses grain")
                precondition(!feeder.childNode(withName:"feederSeed\(i)",recursively:false)!.isHidden)
                FeederBirdNode.apply(at:start+0.29,to:bird)
                precondition(feeder.childNode(withName:"feederSeed\(i)",recursively:false)!.isHidden)
                precondition(!bird.childNode(withName:"feederHeldSeed",recursively:true)!.isHidden)
                FeederBirdNode.apply(at:start+0.81,to:bird)
                precondition(bird.childNode(withName:"feederHeldSeed",recursively:true)!.isHidden)
                contacts += 1
            }
        }
        feeder.eulerAngles.y = 0
        var previous = FeederVisit.pose(at:0)
        for i in 1...1240 {
            let time = Float(i)/100, pose = FeederVisit.pose(at:Float(i)/100)
            precondition(simd_distance(pose.position,previous.position) < 0.025)
            if time >= 2.4 && time < 9.55 {
                precondition(pose.position == BirdFeederModel.perch && pose.spread == 0)
            }
            if time < 2.4 || time > 10.1 { precondition(pose.peck == 0 && !pose.holdingSeed) }
            previous = pose
        }
        var roofHits = 0, minToeHeight: Float = 10
        for i in 0...620 {
            let t = Float(i)/50
            FeederBirdNode.apply(at:t,to:bird)
            bird.enumerateHierarchy { node, _ in
                guard let geometry = node.geometry, node.opacity > 0.01 else { return }
                // Skip invisible flight/fold layers and the seed in the bill.
                if node.isHidden || node.parent?.opacity == 0 || node.parent?.isHidden == true { return }
                let source = geometry.sources(for:.vertex).first!
                let data = source.data
                data.withUnsafeBytes { raw in
                    for index in 0..<source.vectorCount {
                        let base = index*source.dataStride+source.dataOffset
                        guard source.bytesPerComponent == 4 else { continue }
                        let v = SIMD3<Float>(raw.loadUnaligned(fromByteOffset:base,as:Float.self),
                            raw.loadUnaligned(fromByteOffset:base+4,as:Float.self),raw.loadUnaligned(fromByteOffset:base+8,as:Float.self))
                        let point = node.simdConvertPosition(v,to:feeder)
                        if abs(point.x) < 0.175 && point.z > -0.168 && point.z < 0.150 {
                            let roofY = Float(0.715) - abs(point.x)*Float(0.100/0.173)
                            if abs(point.y-roofY) < 0.010 { roofHits += 1 }
                        }
                        if t >= 2.4 && t < 9.55 && node.parent?.name?.hasPrefix("feederFoot") == true {
                            minToeHeight = min(minToeHeight,point.y)
                        }
                    }
                }
            }
        }
        precondition(roofHits == 0, "Bird intersects roof: \(roofHits) vertices")
        precondition(minToeHeight >= BirdFeederModel.trayTop-0.0005 && minToeHeight < BirdFeederModel.trayTop+0.001)
        FeederBirdNode.apply(at:0,to:bird)
        precondition(BirdFeederModel.seeds.indices.allSatisfy { !feeder.childNode(withName:"feederSeed\($0)",recursively:false)!.isHidden })
        let town = TownScene(); town.setMapSize(12)
        let placed = town.addDecoration(type:.birdFeeder,gridX:5,gridY:5)
        placed.startFeederVisits(); placed.startFeederVisits()
        precondition(placed.childNodes.filter { $0.name == "feederBird" }.count == 1)
        UserDefaults.standard.set("storm",forKey:"screenshotWeather"); town.refreshTimeOfDay()
        precondition(placed.childNode(withName:"feederBird",recursively:false) == nil)
        UserDefaults.standard.set("sunny",forKey:"screenshotWeather"); town.refreshTimeOfDay()
        precondition(placed.childNode(withName:"feederBird",recursively:false) != nil)
        UserDefaults.standard.set("22",forKey:"screenshotHour"); town.refreshTimeOfDay()
        precondition(placed.childNode(withName:"feederBird",recursively:false) == nil)
        UserDefaults.standard.set("14",forKey:"screenshotHour"); town.refreshTimeOfDay()
        precondition(placed.childNode(withName:"feederBird",recursively:false) != nil)
        placed.setFeederVisitsEnabled(false)
        precondition(placed.childNode(withName:"feederBird",recursively:false) == nil)
        let result: [String:Any] = ["pass":true,"billContacts":contacts,"pathSamples":1241,
            "roofIntersections":roofHits,"minToeHeight":minToeHeight,"rotations":4,"seedPickupAndSwallow":true,"feetPlanted":true,"singleVisitor":true,"weatherAndNightLifecycle":true]
        try! JSONSerialization.data(withJSONObject:result,options:.prettyPrinted).write(to:URL.documentsDirectory.appending(path:"result.json"))
    }
    func run() {
        if !ProcessInfo.processInfo.arguments.contains("--demo") {
        verify()
        save("krmitko",at:2.65)
        save("zobani",at:3.37)
        save("sousto",at:3.78)
        for (i,t): (Int,Float) in [(0,0.8),(1,1.8),(2,2.25),(3,10.5)] { save("let-\(i)",at:t) }
        camera.camera!.orthographicScale = 0.43
        camera.parent!.position.y = 0.53
        save("ptacek",at:2.65)
        camera.camera!.orthographicScale = 0.78
        camera.parent!.position.y = 0.46
        }
        FeederBirdNode.apply(at:0,to:bird)
        bird.runAction(.repeatForever(.sequence([
            .customAction(duration:Double(FeederVisit.duration)) { node,t in FeederBirdNode.apply(at:Float(t),to:node) },
            .wait(duration:1.6)
        ])))
    }
}
struct NativeFeederView: UIViewRepresentable {
    let check: FeederCheck
    func makeUIView(context:Context) -> SCNView {
        let view = SCNView(); view.scene = check.scene; view.pointOfView = check.camera
        view.isPlaying = true; view.antialiasingMode = .multisampling4X; view.preferredFramesPerSecond = 60
        check.view = view; return view
    }
    func updateUIView(_ view:SCNView,context:Context) {}
}
@main struct FeederPreviewApp: App {
    @State private var check = FeederCheck()
    var body: some Scene { WindowGroup { NativeFeederView(check:check).ignoresSafeArea().task { check.run() } } }
}
