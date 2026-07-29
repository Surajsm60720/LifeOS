import Foundation
import SwiftData

@Model
final class NotificationRule {
    var ruleID: UUID = UUID()
    var triggerKindRaw: String
    var triggerDate: Date?
    var triggerInterval: TimeInterval?
    var messageTemplate: String
    var isActive: Bool

    @Relationship(inverse: \Entry.notificationRules)
    var entry: Entry?

    init(
        triggerKind: NotificationTriggerKind,
        triggerDate: Date? = nil,
        triggerInterval: TimeInterval? = nil,
        messageTemplate: String = "Reminder: {title}",
        isActive: Bool = true
    ) {
        self.ruleID = UUID()
        self.triggerKindRaw = triggerKind.rawValue
        self.triggerDate = triggerDate
        self.triggerInterval = triggerInterval
        self.messageTemplate = messageTemplate
        self.isActive = isActive
    }

    var triggerKind: NotificationTriggerKind {
        get { NotificationTriggerKind(rawValue: triggerKindRaw) ?? .ifNotCompletedBy }
        set { triggerKindRaw = newValue.rawValue }
    }

    func renderedMessage(for entry: Entry) -> String {
        messageTemplate
            .replacingOccurrences(of: "{title}", with: entry.title)
            .replacingOccurrences(of: "{category}", with: entry.category.displayName)
    }

    var triggerSummary: String {
        let calendar = Calendar.current
        switch triggerKind {
        case .fixedTime, .ifNotCompletedBy:
            let time = triggerDate ?? calendar.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "\(triggerKind.displayName) · \(formatter.string(from: time))"
        case .relativeToStart:
            let minutes = Int((triggerInterval ?? 0) / 60)
            if minutes == 0 {
                return "\(triggerKind.displayName) · at start"
            }
            let sign = minutes > 0 ? "+" : ""
            return "\(triggerKind.displayName) · \(sign)\(minutes) min"
        }
    }

    /// Extra lines for list/detail UIs (timing behavior, recurrence, completion needs).
    func detailLines(for entry: Entry) -> [String] {
        var lines: [String] = [triggerSummary, triggerKind.helpText]

        if triggerKind == .ifNotCompletedBy {
            lines.append(
                entry.isCompletable
                    ? "Skips the day once the entry is marked complete"
                    : "Needs Track Completion on the entry to fire"
            )
        }

        if let recurrence = entry.recurrence {
            lines.append("Repeats: \(recurrence.summaryDescription)")
        } else {
            lines.append("One-time entry (no repeat schedule)")
        }

        let startFormatter = DateFormatter()
        startFormatter.dateStyle = .medium
        startFormatter.timeStyle = entry.isAllDay ? .none : .short
        let startLabel = entry.isAllDay ? "Entry date" : "Entry start"
        lines.append("\(startLabel): \(startFormatter.string(from: entry.startDate))")

        return lines
    }
}
