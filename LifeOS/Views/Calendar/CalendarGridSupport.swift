import Foundation
import SwiftUI

/// Shared month-grid geometry and activity density helpers for Month / Year calendars.
enum CalendarGridSupport {
    /// Leading/trailing `nil` pads so days align to weekday columns.
    /// Pads to a full 6-week (42-cell) grid so Month/Year cards share one height.
    static func monthGridCells(for date: Date, calendar: Calendar = .current, fixedWeeks: Bool = false) -> [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 1...daysInMonth {
            var components = calendar.dateComponents([.year, .month], from: date)
            components.day = day
            cells.append(calendar.date(from: components))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        if fixedWeeks {
            while cells.count < 42 {
                cells.append(nil)
            }
            return Array(cells.prefix(42))
        }
        return cells
    }

    /// Weekday symbols ordered to match `monthGridCells` / `firstWeekday`.
    static func orderedWeekdaySymbols(calendar: Calendar = .current, veryShort: Bool = true) -> [String] {
        let symbols = veryShort ? calendar.veryShortWeekdaySymbols : calendar.shortWeekdaySymbols
        return Array(symbols[calendar.firstWeekday - 1..<symbols.count] + symbols[0..<calendar.firstWeekday - 1])
    }

    /// GitHub-style contribution bands for year mini-calendars.
    /// 0 · 1–2 · 3 · 4 · 5 · 6+
    static func heatLevel(count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1, 2: return 1
        case 3: return 2
        case 4: return 3
        case 5: return 4
        default: return 5
        }
    }

    /// Heat fill for a day with `count` entries, normalized against `peak` (at least 1).
    static func heatFill(count: Int, peak: Int, accent: Color = LifeOSTheme.accent) -> Color {
        guard count > 0, peak > 0 else {
            return Color.white.opacity(0.04)
        }
        let t = min(1, Double(count) / Double(max(peak, 1)))
        // Ease so 1–2 entries stay readable; busy days approach accent.
        let opacity = 0.12 + (0.55 * pow(t, 0.72))
        return accent.opacity(opacity)
    }

    /// Count-only fills (no category tint) — brighter steps as daily volume rises.
    static func yearDayFill(count: Int) -> Color {
        let base = LifeOSTheme.accent
        switch heatLevel(count: count) {
        case 0: return Color.white.opacity(0.045)
        case 1: return base.opacity(0.18)  // 1–2
        case 2: return base.opacity(0.36)  // 3
        case 3: return base.opacity(0.54)  // 4
        case 4: return base.opacity(0.72)  // 5
        default: return base.opacity(0.94) // 6+
        }
    }

    /// Representative count for legend swatches matching `heatLevel` bands.
    static func representativeCount(forHeatLevel level: Int) -> Int {
        switch level {
        case 0: return 0
        case 1: return 1
        case 2: return 3
        case 3: return 4
        case 4: return 5
        default: return 6
        }
    }

    static func peakDailyCount(in occurrencesByDay: [Date: [CalendarEntryOccurrence]]) -> Int {
        occurrencesByDay.values.map(\.count).max() ?? 0
    }

    static func groupByDay(
        _ occurrences: [CalendarEntryOccurrence],
        calendar: Calendar = .current
    ) -> [Date: [CalendarEntryOccurrence]] {
        Dictionary(grouping: occurrences) { occurrence in
            calendar.startOfDay(for: occurrence.occurrenceDate)
        }
    }

    static func groupByMonth(
        _ occurrences: [CalendarEntryOccurrence],
        calendar: Calendar = .current
    ) -> [Int: [CalendarEntryOccurrence]] {
        Dictionary(grouping: occurrences) { occurrence in
            calendar.component(.month, from: occurrence.occurrenceDate)
        }
    }

    static func categoryColors(for items: [CalendarEntryOccurrence], limit: Int = 3) -> [Color] {
        var seen = Set<String>()
        var colors: [Color] = []
        for item in items {
            let key: String
            let color: Color
            if item.entry.category == .game {
                key = "game-\(item.entry.subCategory ?? "other")"
                color = GameIdentity.accent(for: item.entry.gameSubCategory)
            } else {
                key = item.entry.category.rawValue
                color = item.entry.displayColor
            }
            guard seen.insert(key).inserted else { continue }
            colors.append(color)
            if colors.count >= limit { break }
        }
        return colors
    }

    /// Cached because the Year view calls `monthTitle` 12 times per render and
    /// `DateFormatter` construction dominates the cost of the call otherwise.
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    static func monthTitle(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = monthTitleFormatter
        if formatter.calendar != calendar {
            formatter.calendar = calendar
        }
        return formatter.string(from: date)
    }

    static func dateForMonth(_ month: Int, inYearOf date: Date, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = calendar.component(.year, from: date)
        components.month = month
        components.day = 1
        return calendar.date(from: components) ?? date
    }
}
