import Foundation
import SwiftData
import SwiftUI

@MainActor
final class EntryStore: ObservableObject {
    private let engine = RecurrenceEngine.shared

    /// Bumped on every mutation. Views that cache derived results (occurrence
    /// expansions, counts) observe this to know when to recompute — comparing the
    /// `[Entry]` array itself is not enough, since toggling a completion mutates a
    /// relationship without changing array identity.
    @Published private(set) var dataVersion = 0

    private func markChanged() {
        dataVersion &+= 1
    }

    func occurrences(for entries: [Entry], in interval: DateInterval, calendar: Calendar = .current) -> [CalendarEntryOccurrence] {
        engine.expandEntries(entries, in: interval, calendar: calendar)
    }

    func occurrenceCount(for entries: [Entry], in interval: DateInterval, calendar: Calendar = .current) -> Int {
        engine.countOccurrences(entries, in: interval, calendar: calendar)
    }

    func toggleCompletion(for entry: Entry, on date: Date, modelContext: ModelContext, calendar: Calendar = .current) {
        let normalized = engine.normalizeOccurrenceStart(date, for: entry, calendar: calendar)
        if let existing = entry.completion(for: date, calendar: calendar) {
            modelContext.delete(existing)
        } else {
            let completion = EntryCompletion(occurrenceStart: normalized)
            completion.entry = entry
            entry.completions.append(completion)
            modelContext.insert(completion)
        }

        markChanged()

        let entryID = entry.id
        let completed = entry.isCompleted(on: date, calendar: calendar)
        Task {
            if completed {
                await NotificationPlanner.shared.cancel(entryID: entryID, on: date, calendar: calendar)
            } else {
                let entries = fetchAllEntries(modelContext: modelContext)
                await NotificationPlanner.refreshPendingNotifications(entries: entries, force: true)
            }

            // Keep the Dynamic Island snapshot in sync with completion changes.
            await LiveActivityManager.syncActiveActivity(modelContext: modelContext)
        }
    }

    func delete(entry: Entry, modelContext: ModelContext) {
        let entryID = entry.id
        Task { await NotificationPlanner.shared.cancelAll(entryID: entryID) }
        modelContext.delete(entry)
        try? modelContext.save()
        markChanged()
    }

    func deleteAll(modelContext: ModelContext) {
        let entries = fetchAllEntries(modelContext: modelContext)
        for entry in entries {
            let entryID = entry.id
            Task { await NotificationPlanner.shared.cancelAll(entryID: entryID) }
            modelContext.delete(entry)
        }
        try? modelContext.save()
        markChanged()
    }

    func save(entry: Entry, modelContext: ModelContext, allEntries: [Entry]) {
        if entry.modelContext == nil {
            modelContext.insert(entry)
        }
        let entries = allEntries.contains(where: { $0.id == entry.id }) ? allEntries : allEntries + [entry]
        markChanged()
        Task {
            await NotificationPlanner.refreshPendingNotifications(entries: entries, force: true)
        }
    }

    func incrementProgress(for entry: Entry, modelContext: ModelContext) {
        guard entry.supportsProgress else { return }
        if entry.progress == nil {
            let label = entry.entertainmentSubCategory?.defaultUnitLabel ?? "episode"
            entry.progress = EntryProgress(currentUnit: 1, unitLabel: label)
            entry.progress?.entry = entry
        } else {
            entry.progress?.currentUnit += 1
        }
        try? modelContext.save()
        markChanged()
    }

    func duplicate(entry: Entry, modelContext: ModelContext) -> Entry {
        let copy = Entry(
            title: entry.title + " Copy",
            category: entry.category,
            subCategory: entry.subCategory,
            startDate: entry.startDate,
            isAllDay: entry.isAllDay,
            duration: entry.duration,
            notes: entry.notes,
            isCompletable: entry.isCompletable,
            colorOverrideHex: entry.colorOverrideHex,
            trackExpense: false,
            eventTypeRaw: entry.eventTypeRaw,
            plannedActivity: entry.plannedActivity,
            playedWithRaw: entry.playedWithRaw
        )
        // Expense ledger intentionally cleared — each hangout's spend is one-off.

        modelContext.insert(copy)

        for place in entry.locations {
            let location = LocationEntry(
                name: place.name,
                latitude: place.latitude,
                longitude: place.longitude
            )
            location.entry = copy
            copy.locations.append(location)
            modelContext.insert(location)
        }

        if let recurrence = entry.recurrence, !copy.hasExpense {
            let rule = RecurrenceRule(
                frequency: recurrence.frequency,
                interval: recurrence.interval,
                daysOfWeek: recurrence.daysOfWeek,
                endDate: recurrence.endDate,
                occurrenceCount: recurrence.occurrenceCount
            )
            rule.entry = copy
            copy.recurrence = rule
            modelContext.insert(rule)
        }

        for rule in entry.notificationRules {
            let note = NotificationRule(
                triggerKind: rule.triggerKind,
                triggerDate: rule.triggerDate,
                triggerInterval: rule.triggerInterval,
                messageTemplate: rule.messageTemplate,
                isActive: rule.isActive
            )
            note.entry = copy
            copy.notificationRules.append(note)
            modelContext.insert(note)
        }

        if let progress = entry.progress {
            let p = EntryProgress(
                currentUnit: progress.currentUnit,
                totalUnits: progress.totalUnits,
                unitLabel: progress.unitLabel,
                targetUnitsPerSession: progress.targetUnitsPerSession
            )
            p.entry = copy
            copy.progress = p
            modelContext.insert(p)
        }

        try? modelContext.save()
        return copy
    }

    private func fetchAllEntries(modelContext: ModelContext) -> [Entry] {
        let descriptor = FetchDescriptor<Entry>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
