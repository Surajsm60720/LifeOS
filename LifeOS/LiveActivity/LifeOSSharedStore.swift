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

    @MainActor
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
