import Foundation
import SwiftData

enum LifeOSDataMigration {
    private static let sampleWipeKey = "lifeos.didWipeSampleData.v1"
    private static let locationMigrateKey = "lifeos.didMigrateLegacyLocation.v1"
    private static let expenseMigrateKey = "lifeos.didMigrateLegacyExpense.v1"

    /// Runs one-time store migrations at app launch. Call from a thin view/app hook.
    @MainActor
    static func runLaunchMigrations(modelContext: ModelContext, entryStore: EntryStore) {
        wipeSampleDataIfNeeded(modelContext: modelContext, entryStore: entryStore)
        migrateLegacyLocationsIfNeeded(modelContext: modelContext)
        migrateLegacyExpenseIfNeeded(modelContext: modelContext)
    }

    @MainActor
    private static func wipeSampleDataIfNeeded(modelContext: ModelContext, entryStore: EntryStore) {
        guard !UserDefaults.standard.bool(forKey: sampleWipeKey) else { return }
        entryStore.deleteAll(modelContext: modelContext)
        UserDefaults.standard.set(true, forKey: sampleWipeKey)
        UserDefaults.standard.set(true, forKey: "lifeos.hasSeededSampleData")
        Task {
            await NotificationPlanner.refreshPendingNotifications(entries: [], force: true)
        }
    }

    @MainActor
    private static func migrateLegacyLocationsIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: locationMigrateKey) else { return }

        let descriptor = FetchDescriptor<Entry>()
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        for entry in entries {
            guard let legacy = entry.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !legacy.isEmpty else {
                continue
            }
            if entry.locations.isEmpty {
                let place = LocationEntry(name: legacy)
                place.entry = entry
                entry.locations.append(place)
                modelContext.insert(place)
            }
            entry.location = nil
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: locationMigrateKey)
    }

    @MainActor
    private static func migrateLegacyExpenseIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: expenseMigrateKey) else { return }

        let descriptor = FetchDescriptor<Entry>()
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        for entry in entries {
            if let amount = entry.expenseAmount {
                if entry.expenseLines.isEmpty {
                    let title = entry.expenseCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let line = ExpenseLine(
                        title: (title?.isEmpty == false) ? title! : "Expense",
                        amount: amount
                    )
                    line.entry = entry
                    entry.expenseLines.append(line)
                    modelContext.insert(line)
                }
                entry.trackExpense = true
                entry.expenseAmount = nil
                entry.expenseCategory = nil
            } else if !entry.expenseLines.isEmpty {
                entry.trackExpense = true
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: expenseMigrateKey)
    }
}
