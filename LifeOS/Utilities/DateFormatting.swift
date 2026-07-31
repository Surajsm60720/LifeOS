import Foundation

enum DateFormatting {
    static let recapRange: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let recapLine: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let weekdayShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    static func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func monthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    static func yearInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: date, duration: 31_536_000)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(interval / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append(hours == 1 ? "1 hr" : "\(hours) hr") }
        if minutes > 0, days == 0 { parts.append(minutes == 1 ? "1 min" : "\(minutes) min") }
        if parts.isEmpty { return "1 min" }
        return parts.joined(separator: " ")
    }

    static func formatDateRange(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        if calendar.isDate(startDay, inSameDayAs: endDay) {
            return recapLine.string(from: startDay)
        }
        return "\(recapLine.string(from: startDay)) – \(recapLine.string(from: endDay))"
    }
}
