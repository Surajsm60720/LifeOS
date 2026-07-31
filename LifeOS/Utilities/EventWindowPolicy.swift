import Foundation

enum EventWindowPolicy {
    /// Any entry longer than one day (24 hours) appears in Ongoing Events.
    static let minimumDuration: TimeInterval = 86_400
    static let recentlyEndedGraceDays = 14
    static let startingSoonHorizonDays = 60
    static let maximumDuration: TimeInterval = 365 * 86_400

    struct GroupedWindows: Sendable {
        let active: [EventWindow]
        let upcoming: [EventWindow]
        let recentlyEnded: [EventWindow]

        var totalVisible: Int { active.count + upcoming.count }

        var activeCount: Int { active.count }
        var upcomingCount: Int { upcoming.count }
    }
}

struct EventWindow: Identifiable {
    enum Status: Sendable {
        case active
        case upcoming
        case recentlyEnded
    }

    let entry: Entry
    let startDate: Date
    let endDate: Date
    let status: Status
    let daysRemaining: Int
    let progress: Double

    var id: UUID { entry.id }
}

enum EventWindowEngine {
    static func groupedWindows(
        from entries: [Entry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> EventWindowPolicy.GroupedWindows {
        let windows = entries.compactMap { buildWindow(for: $0, now: now, calendar: calendar) }

        let active = windows
            .filter { $0.status == .active }
            .sorted { $0.endDate < $1.endDate }

        let upcoming = windows
            .filter { $0.status == .upcoming }
            .sorted { $0.startDate < $1.startDate }

        let recentlyEnded = windows
            .filter { $0.status == .recentlyEnded }
            .sorted { $0.endDate > $1.endDate }

        return EventWindowPolicy.GroupedWindows(
            active: active,
            upcoming: upcoming,
            recentlyEnded: recentlyEnded
        )
    }

    static func buildWindow(
        for entry: Entry,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> EventWindow? {
        guard entry.isEventWindow, let endDate = entry.endDate(calendar: calendar) else { return nil }

        let startDay = calendar.startOfDay(for: entry.startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let today = calendar.startOfDay(for: now)

        let status: EventWindow.Status
        if today >= startDay && today <= endDay {
            status = .active
        } else if today < startDay {
            let horizon = calendar.date(
                byAdding: .day,
                value: EventWindowPolicy.startingSoonHorizonDays,
                to: today
            ) ?? today
            guard startDay <= horizon else { return nil }
            status = .upcoming
        } else {
            let graceStart = calendar.date(
                byAdding: .day,
                value: -EventWindowPolicy.recentlyEndedGraceDays,
                to: today
            ) ?? today
            guard endDay >= graceStart else { return nil }
            status = .recentlyEnded
        }

        let totalDays = max(1, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        let elapsedDays = min(
            totalDays,
            max(0, (calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1)
        )
        let progress = min(1, max(0, Double(elapsedDays) / Double(totalDays)))

        let daysRemaining: Int
        switch status {
        case .active:
            daysRemaining = max(0, calendar.dateComponents([.day], from: today, to: endDay).day ?? 0)
        case .upcoming:
            daysRemaining = max(0, calendar.dateComponents([.day], from: today, to: startDay).day ?? 0)
        case .recentlyEnded:
            daysRemaining = 0
        }

        return EventWindow(
            entry: entry,
            startDate: startDay,
            endDate: endDay,
            status: status,
            daysRemaining: daysRemaining,
            progress: progress
        )
    }
}
