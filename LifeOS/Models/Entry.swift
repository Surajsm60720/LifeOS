import Foundation
import SwiftData
import SwiftUI

@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    var title: String
    var categoryRaw: String
    var subCategory: String?
    var startDate: Date
    var duration: TimeInterval?
    var location: String?
    var notes: String?
    var isCompletable: Bool
    var colorOverrideHex: String?

    @Relationship(deleteRule: .cascade) var recurrence: RecurrenceRule?
    @Relationship(deleteRule: .cascade) var notificationRules: [NotificationRule]
    @Relationship(deleteRule: .cascade) var progress: EntryProgress?
    @Relationship(deleteRule: .cascade) var completions: [EntryCompletion]

    init(
        title: String,
        category: EntryCategory,
        subCategory: String? = nil,
        startDate: Date = .now,
        duration: TimeInterval? = nil,
        location: String? = nil,
        notes: String? = nil,
        isCompletable: Bool = false,
        colorOverrideHex: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.categoryRaw = category.rawValue
        self.subCategory = subCategory
        self.startDate = startDate
        self.duration = duration
        self.location = location
        self.notes = notes
        self.isCompletable = isCompletable
        self.colorOverrideHex = colorOverrideHex
        self.notificationRules = []
        self.completions = []
    }

    var category: EntryCategory {
        get { EntryCategory(rawValue: categoryRaw) ?? .irl }
        set { categoryRaw = newValue.rawValue }
    }

    var gameSubCategory: GameSubCategory? {
        get { subCategory.flatMap(GameSubCategory.init(rawValue:)) }
        set { subCategory = newValue?.rawValue }
    }

    var entertainmentSubCategory: EntertainmentSubCategory? {
        get { subCategory.flatMap(EntertainmentSubCategory.init(rawValue:)) }
        set { subCategory = newValue?.rawValue }
    }

    var colorOverride: Color? {
        get {
            guard let hex = colorOverrideHex else { return nil }
            return Color(hex: hex)
        }
        set {
            colorOverrideHex = newValue?.hexString
        }
    }

    var displayColor: Color {
        colorOverride ?? CategoryColors.color(for: category)
    }

    var supportsRecurrence: Bool {
        switch category {
        case .irl:
            return true
        case .game:
            return gameSubCategory?.supportsRecurrence ?? false
        case .entertainment:
            return true
        }
    }

    var supportsNotifications: Bool {
        switch category {
        case .irl:
            return true
        case .game:
            return gameSubCategory?.supportsNotifications ?? false
        case .entertainment:
            return false
        }
    }

    var supportsLocation: Bool {
        category == .irl
    }

    var supportsProgress: Bool {
        category == .entertainment
    }

    func isCompleted(on occurrenceDate: Date, calendar: Calendar = .current) -> Bool {
        let normalized = RecurrenceEngine.shared.normalizeOccurrenceStart(occurrenceDate, for: self, calendar: calendar)
        return completions.contains { completion in
            calendar.isDate(completion.occurrenceStart, inSameDayAs: normalized)
        }
    }

    func completion(for occurrenceDate: Date, calendar: Calendar = .current) -> EntryCompletion? {
        let normalized = RecurrenceEngine.shared.normalizeOccurrenceStart(occurrenceDate, for: self, calendar: calendar)
        return completions.first { completion in
            calendar.isDate(completion.occurrenceStart, inSameDayAs: normalized)
        }
    }

    static func makeDefault(
        category: EntryCategory,
        gameSubCategory: GameSubCategory? = nil,
        entertainmentSubCategory: EntertainmentSubCategory? = nil
    ) -> Entry {
        let subCategory: String?
        let isCompletable: Bool

        switch category {
        case .irl:
            subCategory = nil
            isCompletable = false
        case .game:
            let game = gameSubCategory ?? .genshinImpact
            subCategory = game.rawValue
            isCompletable = game.defaultCompletable
        case .entertainment:
            let entertainment = entertainmentSubCategory ?? .anime
            subCategory = entertainment.rawValue
            isCompletable = false
        }

        let entry = Entry(
            title: "",
            category: category,
            subCategory: subCategory,
            isCompletable: isCompletable
        )

        if category == .entertainment {
            let entertainment = entertainmentSubCategory ?? .anime
            entry.progress = EntryProgress(unitLabel: entertainment.defaultUnitLabel)
        }

        return entry
    }
}
