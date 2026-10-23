// Standalone simulator checks and native captures. Links the Debug app module
// in a separate bundle; never opens the player’s saved town. --demo keeps it running.
import SwiftUI
import SceneKit
import AVFoundation
@testable import Pilire

@MainActor @Observable final class StormCheck {
    let town: TownScene
    var results: [String: Any] = [:]
    init() {
        UserDefaults.standard.set("storm", forKey: "screenshotWeather")
        UserDefaults.standard.set("14", forKey: "screenshotHour")
        UserDefaults.standard.set(false, forKey: SoundManager.ambientKey)
        town = TownScene()
        town.setMapSize(12)
        town.addBuilding(type: .cafe, gridX: 4, gridY: 4)
        town.addBuilding(type: .cottage, gridX: 3, gridY: 6)
        town.addBuilding(type: .house, gridX: 6, gridY: 6)
        town.addBuilding(type: .post, gridX: 7, gridY: 4)
        town.addBuilding(type: .church, gridX: 4, gridY: 8)
        town.addBuilding(type: .townhall, gridX: 6, gridY: 8)
        town.addBuilding(type: .flowerShop, gridX: 3, gridY: 3)
        town.addBuilding(type: .farm, gridX: 8, gridY: 7)
        town.addDecoration(type: .pond, gridX: 7, gridY: 2)
        for x in 2...9 { town.addDecoration(type: .road, gridX: x, gridY: 5) }
        for y in 6...9 { town.addDecoration(type: .road, gridX: 5, gridY: y) }
        for x in [3, 5, 7, 9] { town.addDecoration(type: .streetLamp, gridX: x, gridY: 5, isCornerAnchor: true) }
        for x in 3...8 { town.addDecoration(type: .poplar, gridX: x, gridY: 1, variant: x % 3) }
        frame(scale: 11.5)
    }
    func frame(scale: Double) {
        town.scnScene.rootNode.enumerateHierarchy { node, _ in
            if node.camera != nil { node.camera!.orthographicScale = scale; node.parent?.position = SCNVector3(0, 0.7, 0) }
        }
    }
    var root: SCNNode { town.scnScene.rootNode }
    var sun: SCNLight { root.childNodes.compactMap(\.light).first { $0.type == .directional }! }
    func count(_ name: String) -> Int { root.childNodes.filter { $0.name == name }.count }
    func save(_ name: String) {
        let image = town.scnView!.snapshot()
        try! image.pngData()!.write(to: URL.documentsDirectory.appending(path: name + ".png"))
    }
    func weather(_ name: String, hour: Int = 14) {
        UserDefaults.standard.set(name, forKey: "screenshotWeather")
        UserDefaults.standard.set(String(hour), forKey: "screenshotHour")
        town.refreshTimeOfDay()
    }
    func waitForFlash(_ name: String) async {
        root.childNode(withName: "stormWeather", recursively: false)!.action(forKey: "stormCycle")!.speed = 3
        for _ in 0..<150 {
            try? await Task.sleep(for: .milliseconds(100))
            if (root.childNode(withName: "stormLightning", recursively: true)?.light?.intensity ?? 0) > 55 {
                save(name); results[name] = true; return
            }
        }
        preconditionFailure("Scheduled storm never flashed")
    }
    func run() async {
        if ProcessInfo.processInfo.arguments.contains("--demo") { return }
        try? await Task.sleep(for: .seconds(2))
        save("bourka-den")
        await waitForFlash("bourka-blesk")
        try? await Task.sleep(for: .seconds(1.4))
        precondition(root.childNode(withName: "stormLightning", recursively: true)!.light!.intensity < 0.01)
        weather("storm", hour: 22)
        try? await Task.sleep(for: .seconds(1.7))
        save("bourka-noc")
        frame(scale: 6)
        try? await Task.sleep(for: .milliseconds(250))
        save("bourka-detail")
        verify()
        await verifySound()
        try! JSONSerialization.data(withJSONObject: results, options: .prettyPrinted).write(to: URL.documentsDirectory.appending(path: "result.json"))
    }
    func verifySound() async {
        let sound = SoundManager.shared
        func field(_ name: String) -> Any? {
            guard let value = Mirror(reflecting: sound).children.first(where: { $0.label == name })?.value else { return nil }
            return Mirror(reflecting: value).children.first?.value
        }
        UserDefaults.standard.set(true, forKey: SoundManager.ambientKey)
        sound.setAtmosphere(.init(weather: .storm, daylight: .day, fireLit: false))
        sound.setListening(true); sound.playDistantThunder()
        precondition(field("thunderTask") != nil)
        sound.setListening(false)
        precondition(field("thunderTask") == nil)
        try? await Task.sleep(for: .seconds(3))
        precondition(field("thunderPlayer") == nil)
        sound.setListening(true); sound.playDistantThunder()
        try? await Task.sleep(for: .seconds(3))
        precondition((field("thunderPlayer") as? AVAudioPlayer)?.isPlaying == true)
        UserDefaults.standard.set(false, forKey: SoundManager.ambientKey)
        sound.settingsChanged()
        precondition(field("thunderPlayer") == nil)
        UserDefaults.standard.set(true, forKey: SoundManager.ambientKey)
        sound.settingsChanged(); sound.playDistantThunder()
        sound.setAtmosphere(.init(weather: .sunny, daylight: .day, fireLit: false))
        precondition(field("thunderTask") == nil)
        sound.setListening(false)
        results["thunderPlaybackAndCancellation"] = true
    }
    func verify() {
        weather("storm")
        let intensity = sun.intensity
        for _ in 0..<30 { town.refreshTimeOfDay() }
        precondition(sun.intensity == intensity && intensity == 470)
        precondition(count("stormWeather") == 1 && count("rain") == 1 && count("bird") == 0 && count("ambientLife") == 0)
        let storm = root.childNode(withName: "stormWeather", recursively: false)!
        town.setRendering(active: false)
        precondition(storm.action(forKey: "stormCycle") == nil)
        precondition(root.childNode(withName: "stormLightning", recursively: true)!.light!.intensity == 0)
        town.setRendering(active: true)
        precondition(storm.action(forKey: "stormCycle") != nil)
        for mode in ["sunny", "rain", "fog", "storm", "sunny"] {
            weather(mode)
            precondition(count("stormWeather") == (mode == "storm" ? 1 : 0))
            precondition(count("rain") == (["rain", "storm"].contains(mode) ? 1 : 0))
            precondition(sun.castsShadow && sun.shadowRadius == (mode == "storm" ? 12 : 7))
            let lamp = town.decorationNodes.first { $0.type == .streetLamp }!
            precondition(lamp.childNode(withName: "streetLampPool", recursively: true)!.isHidden == (mode != "storm"))
            if mode == "sunny" { precondition(sun.intensity == 1000 && town.scnScene.fogEndDistance == 0 && count("bird") == 2) }
        }
        weather("storm")
        for size in [16, 24, 12] {
            town.setMapSize(size)
            precondition(count("stormWeather") == 1 && count("rain") == 1)
            let emitter = root.childNode(withName: "rain", recursively: false)!.particleSystems!.first!.emitterShape as! SCNBox
            precondition(emitter.width == CGFloat(size + 5))
        }
        let effects = StormWeatherEffects(islandSize: 12)
        effects.setActive(true, allowLightning: false); effects.flash()
        precondition(effects.root.action(forKey: "stormCycle") == nil)
        precondition(effects.root.childNode(withName: "stormLightning", recursively: true)!.light!.intensity == 0)
        for hour in [6, 14, 18, 22] {
            weather("storm", hour: hour)
            precondition(sun.intensity > 140 && sun.intensity <= 470)
            precondition(count("bird") == 0 && count("ambientLife") == 0)
            var localLights = 0
            root.enumerateHierarchy { node, _ in
                if node.light?.type == .omni && !node.isHidden && (node.light?.intensity ?? 0) > 0 { localLights += 1 }
            }
            precondition(localLights <= 5)
            let targets = SoundManager.targets(for: town.atmosphere)
            precondition(targets[.rain] == 1 && targets[.birds] == nil && targets[.crickets] == nil)
        }
        // Crossing midnight refreshes the seeded weather without relaunching.
        UserDefaults.standard.removeObject(forKey: "screenshotWeather")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        var storms = 0, samples = 0
        for day in 0..<365 {
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            let seeded = TownWeather.seeded(at: date)
            precondition(seeded == TownWeather.seeded(at: calendar.date(byAdding: .hour, value: 20, to: date)!))
            if seeded == .storm { storms += 1 }
            if day < 35 { town.refreshTimeOfDay(now: date); precondition(town.weather == seeded); samples += 1 }
        }
        precondition(storms > 0 && storms < 45)
        let sound = Bundle.main.url(forResource: "amb_distant_thunder", withExtension: "m4a")!
        let player = try! AVAudioPlayer(contentsOf: sound)
        precondition(player.duration > 6 && player.duration < 8)
        results["repeatRefreshes"] = 30
        results["weatherTransitions"] = 5
        results["mapSizes"] = [12,16,24]
        results["daylightPhases"] = 4
        results["seededDays"] = 365
        results["stormsIn2026"] = storms
        results["dateChanges"] = samples
        results["accessibilityNoFlash"] = true
        results["pauseResume"] = true
        results["thunderDecodes"] = true
        results["pass"] = true
        weather("storm", hour: 22)
    }
}
@main struct StormPreviewApp: App {
    @State private var check = StormCheck()
    var body: some Scene {
        WindowGroup { TownSceneView(scene: check.town).ignoresSafeArea().task { await check.run() } }
    }
}
