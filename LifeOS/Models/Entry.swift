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
    /// Legacy single-location string; migrated into `locations` then cleared.
    var location: String?
    var notes: String?
    var isCompletable: Bool
    var colorOverrideHex: String?

    /// Legacy flat expense; migrated into `expenseLines` then cleared.
    var expenseAmount: Decimal?
    var expenseCategory: String?

    var trackExpense: Bool = false
    var eventTypeRaw: String?
    var plannedActivity: String?
    var playedWithRaw: String = ""

    @Relationship(deleteRule: .cascade) var locations: [LocationEntry]
    @Relationship(deleteRule: .cascade) var expenseLines: [ExpenseLine]
    @Relationship(deleteRule: .cascade) var expenseBalances: [ExpenseBalance]
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
        colorOverrideHex: String? = nil,
        trackExpense: Bool = false,
        eventTypeRaw: String? = nil,
        plannedActivity: String? = nil,
        playedWithRaw: String = ""
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
        self.trackExpense = trackExpense
        self.eventTypeRaw = eventTypeRaw
        self.plannedActivity = plannedActivity
        self.playedWithRaw = playedWithRaw
        self.locations = []
        self.expenseLines = []
        self.expenseBalances = []
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

    var eventType: GameEventType? {
        get { eventTypeRaw.flatMap(GameEventType.init(rawValue:)) }
        set { eventTypeRaw = newValue?.rawValue }
    }

    var playedWith: [String] {
        get {
            playedWithRaw
                .split(whereSeparator: { $0 == "\n" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            playedWithRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    var expenseTotal: Decimal {
        expenseLines.reduce(Decimal(0)) { $0 + $1.amount }
    }

    var expenseOwedToYou: Decimal {
        expenseBalances.reduce(Decimal(0)) { $0 + $1.amount }
    }

    var hasExpense: Bool {
        trackExpense || !expenseLines.isEmpty || expenseAmount != nil
    }

    var locationSummary: String? {
        let names = locations.map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty {
            return names.joined(separator: " → ")
        }
        if let location, !location.isEmpty {
            return location
        }
        return nil
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
            return !hasExpense
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

    var supportsExpense: Bool {
        category == .irl && recurrence == nil
    }

    var supportsEventType: Bool {
        category == .game && (gameSubCategory?.supportsEventType ?? false)
    }

    var supportsSessionLog: Bool {
        category == .game && (gameSubCategory?.supportsSessionLog ?? false)
    }

    var supportsProgress: Bool {
        category == .entertainment
    }

    func clearExpense(modelContext: ModelContext? = nil) {
        trackExpense = false
        expenseAmount = nil
        expenseCategory = nil
        for line in expenseLines {
            modelContext?.delete(line)
        }
        expenseLines.removeAll()
        for balance in expenseBalances {
            modelContext?.delete(balance)
        }
        expenseBalances.removeAll()
    }

    func clearSessionLog() {
        plannedActivity = nil
        playedWithRaw = ""
    }

    func clearEventType() {
        eventTypeRaw = nil
    }

    func clearLocations(modelContext: ModelContext? = nil) {
        for place in locations {
            modelContext?.delete(place)
        }
        locations.removeAll()
        location = nil
    }

    /// Split `expenseTotal` equally among names; last person gets remainder.
    func applyEqualSplit(among names: [String], modelContext: ModelContext? = nil) {
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for balance in expenseBalances {
            modelContext?.delete(balance)
        }
        expenseBalances.removeAll()

        guard !cleaned.isEmpty else { return }

        let total = expenseTotal
        let count = Decimal(cleaned.count)
        let share = (total / count as NSDecimalNumber).rounding(accordingToBehavior: Self.splitRounding) as Decimal
        var assigned: Decimal = 0

        for (index, name) in cleaned.enumerated() {
            let amount: Decimal
            if index == cleaned.count - 1 {
                amount = total - assigned
            } else {
                amount = share
                assigned += share
            }
            let balance = ExpenseBalance(personName: name, amount: amount)
            balance.entry = self
            expenseBalances.append(balance)
            modelContext?.insert(balance)
        }
    }

    private static let splitRounding: NSDecimalNumberHandler = {
        NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 2,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
    }()

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
