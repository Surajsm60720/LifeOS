import Foundation
import SwiftData

enum LifeOSSharedStore {
    static let schema = Schema([
        Entry.self,
        LocationEntry.self,
        ExpenseLine.self,
        ExpenseBalance.self,
        RecurrenceRule.self,
        NotificationRule.self,
        EntryProgress.self,
        EntryCompletion.self,
    ])

    @MainActor
    private static var _container: ModelContainer?

    /// One shared container for the app + Live Activity intents.
    /// Creating a second container on the same store was breaking scope updates.
    @MainActor
    static var container: ModelContainer {
        if let _container {
            return _container
        }
        let created = makeContainer()
        _container = created
        return created
    }

    /// True when the on-disk store could not be opened and we fell back to a
    /// temporary in-memory store. The UI surfaces this so the user can restore
    /// from a backup instead of facing a launch crash loop.
    @MainActor
    private(set) static var isUsingRecoveryStore = false

    /// Why the on-disk store failed to open, for display in the recovery banner.
    @MainActor
    private(set) static var storeFailureReason: String?

    @MainActor
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A corrupted store or a failed schema migration must not brick the app —
            // that would strand the user with no way to reach Backup & Restore and
            // export their data. Fall back to an in-memory store so LifeOS still
            // launches in a degraded but usable state.
            isUsingRecoveryStore = true
            storeFailureReason = error.localizedDescription

            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let recovery = try? ModelContainer(for: schema, configurations: [fallback]) {
                return recovery
            }

            // An in-memory container failing means the schema itself is invalid,
            // which is a programmer error no user action can recover from.
            fatalError("Could not create in-memory recovery ModelContainer: \(error)")
        }
    }
}
