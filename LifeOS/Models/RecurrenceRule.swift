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
}
