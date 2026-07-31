import Foundation

enum NotificationPreset: String, CaseIterable, Identifiable {
    case endOfDayCheckIn
    case morningDailies
    case thirtyMinutesBefore
    case atStart
    case lastDayReminder
    case oneDayBeforeEnd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .endOfDayCheckIn: "End-of-day check-in (9 PM)"
        case .morningDailies: "Morning dailies (9 AM)"
        case .thirtyMinutesBefore: "30 min before start"
        case .atStart: "At start time"
        case .lastDayReminder: "Last day reminder (9 PM)"
        case .oneDayBeforeEnd: "1 day before end (9 PM)"
        }
    }

    var triggerKind: NotificationTriggerKind {
        switch self {
        case .endOfDayCheckIn, .morningDailies: .ifNotCompletedBy
        case .thirtyMinutesBefore, .atStart: .relativeToStart
        case .lastDayReminder, .oneDayBeforeEnd: .relativeToEnd
        }
    }

    var messageTemplate: String {
        switch self {
        case .endOfDayCheckIn: "Still open: {title}"
        case .morningDailies: "Morning check — {title}"
        case .thirtyMinutesBefore: "Starting soon: {title}"
        case .atStart: "Time for {title}"
        case .lastDayReminder: "Last day for {title}"
        case .oneDayBeforeEnd: "Ends tomorrow: {title}"
        }
    }

    func triggerDate(calendar: Calendar = .current, now: Date = .now) -> Date? {
        switch self {
        case .endOfDayCheckIn, .lastDayReminder, .oneDayBeforeEnd:
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
        case .endOfDayCheckIn, .morningDailies, .lastDayReminder, .oneDayBeforeEnd: return nil
        }
    }

    var triggerOffsetDays: Int? {
        switch self {
        case .lastDayReminder: return 0
        case .oneDayBeforeEnd: return -1
        default: return nil
        }
    }
}
