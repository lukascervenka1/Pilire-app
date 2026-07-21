import SwiftUI
import SwiftData

@main
struct PilireApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([DayRecord.self, Building.self, UserSettings.self, PlacedDecoration.self, Habit.self, OwnedAnimal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Dev-phase fallback: incompatible schema → start with a fresh store.
            // TODO: replace with a proper SwiftData MigrationPlan before App Store release.
            let store = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: store)
            try? FileManager.default.removeItem(at: store.appendingPathExtension("shm"))
            try? FileManager.default.removeItem(at: store.appendingPathExtension("wal"))
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("ModelContainer failed: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
