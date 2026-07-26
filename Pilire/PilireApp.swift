import SwiftUI
import SwiftData

@main
struct PilireApp: App {
    /// Schema versioning, migrations and safe recovery all live in Persistence.swift.
    var sharedModelContainer: ModelContainer = PilireStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
