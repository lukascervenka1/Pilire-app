// Standalone simulator harness. Links the Debug app module with @testable import;
// its own bundle and in-memory database never open the player's stored town.
import SwiftUI
import SwiftData
import SceneKit
@testable import Pilire

@MainActor @Observable
final class FeedingCheck {
    let scene = TownScene()
    let container: ModelContainer
    let house: DecorationNode
    let decoration: PlacedDecoration
    let other: PlacedDecoration
    let dog: AnimalNode
    var timer: Timer?
    var started: Date?
    var eatingSince: Date?
    var sleepingSince: Date?
    var filled = false
    var interrupted = false
    var ended = false
    var consumed = 0
    var rejected = 0
    var maxEating = 0
    var counts = Set<Int>()
    let testCase: String
    let rotation: Int

    init() {
        let args = ProcessInfo.processInfo.arguments
        testCase = args.first(where: { $0.hasPrefix("--case=") }).map { String($0.dropFirst(7)) } ?? "complete"
        rotation = args.first(where: { $0.hasPrefix("--rotation=") }).flatMap { Int($0.dropFirst(11)) } ?? 0
        let kind: AnimalKind = args.contains("--husky") ? .husky : .dog
        container = try! ModelContainer(for: Schema(PilireSchemaV1.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.autosaveEnabled = false
        decoration = PlacedDecoration(type: .doghouse, gridX: 5, gridY: 5)
        decoration.rotation = rotation
        other = PlacedDecoration(type: .doghouse, gridX: 8, gridY: 8)
        other.hasFood = testCase != "two-dogs" && testCase != "sleeping"
        context.insert(decoration)
        context.insert(other)
        house = scene.addDecoration(type: .doghouse, gridX: 5, gridY: 5, rotation: rotation)
        house.associatedDecoration = decoration
        if testCase != "two-dogs" {
            let second = scene.addDecoration(type: .doghouse, gridX: 8, gridY: 8)
            second.associatedDecoration = other
            second.setBowlFilled(other.hasFood)
        }
        dog = scene.addAnimal(kind: kind)
        let dx = Int(sin(Float(rotation) * .pi / 2).rounded())
        let dz = Int(cos(Float(rotation) * .pi / 2).rounded())
        dog.place(col: 5 + dx, row: 5 + dz)
        if testCase == "two-dogs" {
            let secondDog = scene.addAnimal(kind: .husky)
            secondDog.place(col: 5 + dx * 2, row: 5 + dz * 2)
        }
        try! context.save()
        scene.onBowlEmptied = { [weak self] target in
            guard let self else { return false }
            if self.testCase == "save-failure" { self.rejected += 1; return false }
            precondition(target === self.decoration, "Dog consumed another bowl")
            precondition(target.hasFood, "Repeated consumption")
            target.hasFood = false
            try! context.save()
            self.consumed += 1
            return true
        }
        scene.scnScene.rootNode.enumerateHierarchy { node, _ in
            if node.camera != nil {
                node.camera?.orthographicScale = 2.1
                node.parent?.position = SCNVector3(-0.5 + Float(dx) * 0.40, 0.18, -0.5 + Float(dz) * 0.40)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard !ended else { return }
        if started == nil {
            guard dog.childNode(withName: "Head", recursively: true) != nil else { return }
            dog.stopLiving()
            started = .now
            if testCase == "sleeping" { dog.sendToKennel() }
        }
        if !filled {
            if testCase == "sleeping" {
                guard dog.isSleeping else { return }
                if sleepingSince == nil { sleepingSince = .now }
                guard Date().timeIntervalSince(sleepingSince!) > 3.6 else { return }
            }
            decoration.hasFood = true
            if testCase == "sleeping" {
                other.hasFood = true
                scene.decorationNodes.first { $0.associatedDecoration === other }?.setBowlFilled(true)
            }
            try! container.mainContext.save()
            house.setBowlFilled(true)
            filled = true
            scene.notifyBowlFilled()
        }
        let food = house.childNode(withName: "bowlFood", recursively: true)!
        let visible = food.childNodes.filter { !$0.isHidden }.count
        counts.insert(visible)
        maxEating = max(maxEating, scene.animalNodes.filter(\.isEating).count)
        if dog.isEating && eatingSince == nil { eatingSince = .now }
        if let eatingSince, Date().timeIntervalSince(eatingSince) > 1.7, !interrupted {
            if testCase == "carry" { dog.beginCarry(); interrupted = true }
            if testCase == "remove" { scene.removeDecoration(house); interrupted = true }
        }
        if testCase == "carry", interrupted {
            let restored = food.childNodes.filter { !$0.isHidden }.count
            finish(pass: consumed == 0 && decoration.hasFood && restored == 9 && !dog.isEating)
        } else if testCase == "remove", interrupted, !dog.isEating {
            finish(pass: consumed == 0 && decoration.hasFood && dog.claimedBowlID == nil)
        } else if testCase == "save-failure", rejected > 0, !dog.isEating {
            finish(pass: consumed == 0 && decoration.hasFood && visible == 9)
        } else if let happy = scene.animalNodes.first(where: {
            $0.childNode(withName: "affection", recursively: false) != nil
        }) {
            let correctOther = testCase == "two-dogs" || other.hasFood
            finish(pass: consumed == 1 && !decoration.hasFood && !house.bowlHasFood &&
                   !happy.isSleeping && !happy.isEating && correctOther && maxEating == 1 && counts.count >= 4)
        } else if Date().timeIntervalSince(started!) > 32 {
            finish(pass: false)
        }
    }

    private func finish(pass: Bool) {
        ended = true
        let ground = scene.scnScene.rootNode.childNode(withName: "groundDetail", recursively: false)!.boundingBox
        let groundIsSpreadOut = ground.max.x - ground.min.x > Float(scene.cols) / 2
        let result: [String: Any] = ["pass": pass && groundIsSpreadOut, "case": testCase, "rotation": rotation,
            "consumed": consumed, "rejected": rejected, "remainingFood": decoration.hasFood,
            "otherBowlStillFull": other.hasFood, "maxSimultaneousEating": maxEating,
            "granuleCounts": counts.sorted(), "elapsed": Date().timeIntervalSince(started!),
            "groundDetailsSpreadOut": groundIsSpreadOut]
        let url = URL.documentsDirectory.appending(path: "feeding-result.json")
        try! JSONSerialization.data(withJSONObject: result, options: .prettyPrinted).write(to: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let png = self?.scene.scnView?.snapshot().pngData() else { return }
            try? png.write(to: URL.documentsDirectory.appending(path: "feeding-finish.png"))
        }
        if testCase != "complete" && testCase != "sleeping" { scene.animalNodes.forEach { $0.stopLiving() } }
        else {
            // Let the visible thank-you animation finish before stopping the next trip.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) { [weak self] in
                self?.scene.animalNodes.forEach { $0.stopLiving() }
            }
        }
    }
}

@main
struct DogFeedingPreview: App {
    @State private var check = FeedingCheck()
    var body: some Scene {
        WindowGroup {
            TownSceneView(scene: check.scene)
                .ignoresSafeArea()
                .background(Theme.creamGradient)
                .preferredColorScheme(.light)
        }
    }
}
