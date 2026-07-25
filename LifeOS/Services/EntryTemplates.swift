import Foundation
import SwiftData

struct EntryTemplateDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let category: EntryCategory
    let gameSubCategory: GameSubCategory?
    let entertainmentSubCategory: EntertainmentSubCategory?
    let isCompletable: Bool
    let frequency: RecurrenceFrequency?
    let interval: Int
    let addEndOfDayNotification: Bool

    static let builtIn: [EntryTemplateDefinition] = [
        EntryTemplateDefinition(
            id: "dailies",
            title: "Game Dailies",
            detail: "Daily completable with 9 PM check-in",
            category: .game,
            gameSubCategory: .genshinImpact,
            entertainmentSubCategory: nil,
            isCompletable: true,
            frequency: .daily,
            interval: 1,
            addEndOfDayNotification: true
        ),
        EntryTemplateDefinition(
            id: "weeklies",
            title: "Weeklies",
            detail: "Weekly completable, Mondays",
            category: .game,
            gameSubCategory: .honkaiStarRail,
            entertainmentSubCategory: nil,
            isCompletable: true,
            frequency: .weekly,
            interval: 1,
            addEndOfDayNotification: true
        ),
        EntryTemplateDefinition(
            id: "banner",
            title: "Banner Window",
            detail: "One-shot game banner / event window",
            category: .game,
            gameSubCategory: .wutheringWaves,
            entertainmentSubCategory: nil,
            isCompletable: false,
            frequency: nil,
            interval: 1,
            addEndOfDayNotification: false
        ),
        EntryTemplateDefinition(
            id: "dentist",
            title: "Dentist / Appointment",
            detail: "IRL visit with location + reminder",
            category: .irl,
            gameSubCategory: nil,
            entertainmentSubCategory: nil,
            isCompletable: true,
            frequency: nil,
            interval: 1,
            addEndOfDayNotification: true
        ),
        EntryTemplateDefinition(
            id: "anime",
            title: "Anime Progress",
            detail: "Entertainment habit, no notifications",
            category: .entertainment,
            gameSubCategory: nil,
            entertainmentSubCategory: .anime,
            isCompletable: false,
            frequency: .daily,
            interval: 1,
            addEndOfDayNotification: false
        )
    ]

    @MainActor
    func makeEntry(modelContext: ModelContext, startDate: Date = .now) -> Entry {
        let entry = Entry.makeDefault(
            category: category,
            gameSubCategory: gameSubCategory,
            entertainmentSubCategory: entertainmentSubCategory
        )
        entry.title = title
        entry.startDate = startDate
        entry.isCompletable = isCompletable

        if let frequency {
            let rule = RecurrenceRule(frequency: frequency, interval: interval)
            if frequency == .weekly {
                rule.daysOfWeek = [.monday]
            }
            rule.entry = entry
            entry.recurrence = rule
        }

        if addEndOfDayNotification, entry.supportsNotifications {
            let preset = NotificationPreset.endOfDayCheckIn
            let note = NotificationRule(
                triggerKind: preset.triggerKind,
                triggerDate: preset.triggerDate(),
                messageTemplate: preset.messageTemplate
            )
            note.entry = entry
            entry.notificationRules = [note]
        }

        if category == .entertainment, entry.progress == nil {
            entry.progress = EntryProgress(
                unitLabel: entertainmentSubCategory?.defaultUnitLabel ?? "episode"
            )
            entry.progress?.entry = entry
        }

        modelContext.insert(entry)
        return entry
    }
}
