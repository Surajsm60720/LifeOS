import Foundation
import SwiftData

@Model
final class RecurrenceRule {
    var frequencyRaw: String
    var interval: Int
    var daysOfWeekRaw: String?
    var endDate: Date?
    var occurrenceCount: Int?

    @Relationship(inverse: \Entry.recurrence)
    var entry: Entry?

    init(
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        daysOfWeek: Set<Weekday>? = nil,
        endDate: Date? = nil,
        occurrenceCount: Int? = nil
    ) {
        self.frequencyRaw = frequency.rawValue
        self.interval = max(1, interval)
        self.daysOfWeekRaw = daysOfWeek.map(Self.encodeWeekdays)
        self.endDate = endDate
        self.occurrenceCount = occurrenceCount
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    var daysOfWeek: Set<Weekday>? {
        get {
            guard let raw = daysOfWeekRaw else { return nil }
            return Self.decodeWeekdays(raw)
        }
        set {
            daysOfWeekRaw = newValue.map(Self.encodeWeekdays)
        }
    }

    private static func encodeWeekdays(_ days: Set<Weekday>) -> String {
        days.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
    }

    private static func decodeWeekdays(_ raw: String) -> Set<Weekday> {
        Set(
            raw.split(separator: ",").compactMap { Int($0) }.compactMap(Weekday.init(rawValue:))
        )
    }

    /// Human-readable schedule for lists (e.g. "Weekly · Mon, Wed · 10 occurrences").
    var summaryDescription: String {
        var parts: [String] = []

        switch frequency {
        case .daily:
            parts.append(interval == 1 ? "Daily" : "Every \(interval) days")
        case .weekly:
            parts.append(interval == 1 ? "Weekly" : "Every \(interval) weeks")
        case .monthly:
            parts.append(interval == 1 ? "Monthly" : "Every \(interval) months")
        case .everyNMonths:
            parts.append("Every \(max(interval, 1)) months")
        }

        if frequency == .weekly, let days = daysOfWeek, !days.isEmpty {
            let ordered = Weekday.allCases.filter { days.contains($0) }
            parts.append(ordered.map(\.shortName).joined(separator: ", "))
        }

        if let occurrenceCount {
            parts.append(occurrenceCount == 1 ? "1 occurrence" : "\(occurrenceCount) occurrences")
        }

        if let endDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            parts.append("until \(formatter.string(from: endDate))")
        }

        return parts.joined(separator: " · ")
    }
}
