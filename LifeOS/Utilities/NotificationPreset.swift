import Foundation

enum NotificationPreset: String, CaseIterable, Identifiable {
    case endOfDayCheckIn
    case morningDailies
    case thirtyMinutesBefore
    case atStart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .endOfDayCheckIn: "End-of-day check-in (9 PM)"
        case .morningDailies: "Morning dailies (9 AM)"
        case .thirtyMinutesBefore: "30 min before start"
        case .atStart: "At start time"
        }
    }

    var triggerKind: NotificationTriggerKind {
        switch self {
        case .endOfDayCheckIn, .morningDailies: .ifNotCompletedBy
        case .thirtyMinutesBefore, .atStart: .relativeToStart
        }
    }

    var messageTemplate: String {
        switch self {
        case .endOfDayCheckIn: "Still open: {title}"
        case .morningDailies: "Morning check — {title}"
        case .thirtyMinutesBefore: "Starting soon: {title}"
        case .atStart: "Time for {title}"
        }
    }

    func triggerDate(calendar: Calendar = .current, now: Date = .now) -> Date? {
        switch self {
        case .endOfDayCheckIn:
            return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)
        case .morningDailies:
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)
        case .thirtyMinutesBefore, .atStart:
            return nil
        }
    }

    var triggerOffsetMinutes: Int? {
        switch self {
        case .thirtyMinutesBefore: return -30
        case .atStart: return 0
        case .endOfDayCheckIn, .morningDailies: return nil
        }
    }
}
