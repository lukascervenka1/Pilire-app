import Foundation
import SwiftData

// MARK: - Versioned schema

/// The shape of the store as it ships today. Adding a property with a default
/// value is handled by SwiftData's lightweight migration and needs nothing here.
/// A *destructive* change (renaming, retyping or removing a property) needs a
/// new `PilireSchemaV2` plus a stage in `PilireMigrationPlan`.
enum PilireSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DayRecord.self, Building.self, UserSettings.self,
         PlacedDecoration.self, Habit.self, OwnedAnimal.self]
    }
}

/// Where future migrations get added. Keeping it wired up from the start means
/// a schema change never has to be a scramble.
enum PilireMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PilireSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Container

enum PilireStore {

    /// Opens the store. If it ever fails to open, the existing file is **set
    /// aside, never deleted** — a player's town is months of work and must stay
    /// recoverable, even from a botched migration.
    static func makeContainer() -> ModelContainer {
        let schema = Schema(PilireSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema,
                                      migrationPlan: PilireMigrationPlan.self,
                                      configurations: [config])
        } catch {
            let archived = archiveExistingStore()
            #if DEBUG
            print("⚠️ SwiftData store could not be opened: \(error)")
            print("⚠️ Previous store kept at: \(archived?.path ?? "nothing to archive")")
            #endif

            // Second attempt on a clean file.
            if let container = try? ModelContainer(for: schema,
                                                   migrationPlan: PilireMigrationPlan.self,
                                                   configurations: [config]) {
                return container
            }

            // Last resort: run in memory so the app still opens instead of
            // crashing on launch. Nothing on disk has been destroyed.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("ModelContainer failed even in memory: \(error)")
            }
        }
    }

    /// Timestamped copy of the store files, so nothing is lost and a recovery
    /// path stays open. Returns the folder the files were moved into.
    @discardableResult
    private static func archiveExistingStore() -> URL? {
        let fm = FileManager.default
        let support = URL.applicationSupportDirectory
        let store = support.appending(path: "default.store")
        guard fm.fileExists(atPath: store.path) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let folder = support.appending(path: "RecoveredStores/\(stamp)")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        for suffix in ["", "-shm", "-wal"] {
            let src = support.appending(path: "default.store\(suffix)")
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = folder.appending(path: "default.store\(suffix)")
            try? fm.moveItem(at: src, to: dst)
        }
        return folder
    }
}
