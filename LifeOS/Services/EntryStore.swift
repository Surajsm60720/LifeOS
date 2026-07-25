import Foundation
import SwiftData
import SwiftUI

@MainActor
final class EntryStore: ObservableObject {
    private let engine = RecurrenceEngine.shared

    func occurrences(for entries: [Entry], in interval: DateInterval, calendar: Calendar = .current) -> [CalendarEntryOccurrence] {
        engine.expandEntries(entries, in: interval, calendar: calendar)
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

        let entryID = entry.id
        let completed = entry.isCompleted(on: date, calendar: calendar)
        Task {
            if completed {
                await NotificationPlanner.shared.cancel(entryID: entryID, on: date, calendar: calendar)
            } else {
                let entries = fetchAllEntries(modelContext: modelContext)
                await NotificationPlanner.refreshPendingNotifications(entries: entries, force: true)
            }
        }
    }

    func delete(entry: Entry, modelContext: ModelContext) {
        let entryID = entry.id
        Task { await NotificationPlanner.shared.cancelAll(entryID: entryID) }
        modelContext.delete(entry)
        try? modelContext.save()
        objectWillChange.send()
    }

    func deleteAll(modelContext: ModelContext) {
        let entries = fetchAllEntries(modelContext: modelContext)
        for entry in entries {
            let entryID = entry.id
            Task { await NotificationPlanner.shared.cancelAll(entryID: entryID) }
            modelContext.delete(entry)
        }
        try? modelContext.save()
        objectWillChange.send()
    }

    func save(entry: Entry, modelContext: ModelContext, allEntries: [Entry]) {
        if entry.modelContext == nil {
            modelContext.insert(entry)
        }
        let entries = allEntries.contains(where: { $0.id == entry.id }) ? allEntries : allEntries + [entry]
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
        objectWillChange.send()
    }

    func duplicate(entry: Entry, modelContext: ModelContext) -> Entry {
        let copy = Entry(
            title: entry.title + " Copy",
            category: entry.category,
            subCategory: entry.subCategory,
            startDate: entry.startDate,
            duration: entry.duration,
            location: entry.location,
            notes: entry.notes,
            isCompletable: entry.isCompletable,
            colorOverrideHex: entry.colorOverrideHex
        )

        if let recurrence = entry.recurrence {
            let rule = RecurrenceRule(
                frequency: recurrence.frequency,
                interval: recurrence.interval,
                daysOfWeek: recurrence.daysOfWeek,
                endDate: recurrence.endDate,
                occurrenceCount: recurrence.occurrenceCount
            )
            rule.entry = copy
            copy.recurrence = rule
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
        }

        if let progress = entry.progress {
            let p = EntryProgress(
                currentUnit: progress.currentUnit,
                totalUnits: progress.totalUnits,
                unitLabel: progress.unitLabel
            )
            p.entry = copy
            copy.progress = p
        }

        modelContext.insert(copy)
        try? modelContext.save()
        return copy
    }

    private func fetchAllEntries(modelContext: ModelContext) -> [Entry] {
        let descriptor = FetchDescriptor<Entry>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
