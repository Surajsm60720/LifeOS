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
    enum Status: Sendable, Equatable {
        case active
        case upcoming
        case recentlyEnded
    }

    enum Kind: Sendable, Equatable {
        case durationWindow
        case currentPeriod
    }

    let entry: Entry
    let startDate: Date
    let endDate: Date
    let status: Status
    let daysRemaining: Int
    let progress: Double
    let kind: Kind
    let occurrenceDate: Date
    let isPeriodComplete: Bool
    let periodCaption: String?

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
        if entry.recurrence != nil {
            return buildCurrentPeriodWindow(for: entry, now: now, calendar: calendar)
        }
        return buildDurationWindow(for: entry, now: now, calendar: calendar)
    }

    private static func buildDurationWindow(
        for entry: Entry,
        now: Date,
        calendar: Calendar
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

        let metrics = progressMetrics(from: startDay, to: endDay, today: today, calendar: calendar)
        let daysRemaining = remainingDays(status: status, today: today, startDay: startDay, endDay: endDay, calendar: calendar)

        return EventWindow(
            entry: entry,
            startDate: startDay,
            endDate: endDay,
            status: status,
            daysRemaining: daysRemaining,
            progress: metrics.progress,
            kind: .durationWindow,
            occurrenceDate: entry.startDate,
            isPeriodComplete: false,
            periodCaption: nil
        )
    }

    private static func buildCurrentPeriodWindow(
        for entry: Entry,
        now: Date,
        calendar: Calendar
    ) -> EventWindow? {
        guard let rule = entry.recurrence else { return nil }

        let caption: String
        switch rule.frequency {
        case .daily:
            return nil
        case .weekly:
            caption = "This week"
        case .monthly, .everyNMonths:
            caption = "This month"
        }

        let today = calendar.startOfDay(for: now)
        let lookback = dateByAddingPeriods(-2, to: now, rule: rule, calendar: calendar) ?? entry.startDate
        let lookahead = dateByAddingPeriods(2, to: now, rule: rule, calendar: calendar) ?? now
        let rangeStart = max(calendar.startOfDay(for: entry.startDate), calendar.startOfDay(for: lookback))
        guard rangeStart <= lookahead else { return nil }

        let occurrences = RecurrenceEngine.shared.occurrences(
            for: entry,
            in: rangeStart...lookahead,
            calendar: calendar
        )
        guard let current = occurrences.last(where: { calendar.startOfDay(for: $0) <= today }) else {
            return nil
        }

        let startDay = calendar.startOfDay(for: current)
        let dayAfterCurrent = calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay
        let following = RecurrenceEngine.shared.occurrences(
            for: entry,
            in: dayAfterCurrent...lookahead,
            calendar: calendar
        )
        let synthesizedNext = dateByAddingPeriods(1, to: current, rule: rule, calendar: calendar) ?? current
        let endDay = calendar.startOfDay(for: following.first ?? synthesizedNext)

        let cycleOccurrences = occurrences.filter {
            let day = calendar.startOfDay(for: $0)
            return day >= startDay && day < endDay
        }
        let completableOccurrences = cycleOccurrences.isEmpty ? [current] : cycleOccurrences
        let occurrenceDate = completableOccurrences.first(where: { calendar.isDate($0, inSameDayAs: now) })
            ?? current
        let isPeriodComplete = entry.isCompletable
            && completableOccurrences.allSatisfy { entry.isCompleted(on: $0, calendar: calendar) }
        let metrics = progressMetrics(from: startDay, to: endDay, today: today, calendar: calendar)

        return EventWindow(
            entry: entry,
            startDate: startDay,
            endDate: endDay,
            status: .active,
            daysRemaining: remainingDays(
                status: .active,
                today: today,
                startDay: startDay,
                endDay: endDay,
                calendar: calendar
            ),
            progress: metrics.progress,
            kind: .currentPeriod,
            occurrenceDate: occurrenceDate,
            isPeriodComplete: isPeriodComplete,
            periodCaption: caption
        )
    }

    private static func dateByAddingPeriods(
        _ count: Int,
        to date: Date,
        rule: RecurrenceRule,
        calendar: Calendar
    ) -> Date? {
        let interval = max(1, rule.interval) * count
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case .monthly, .everyNMonths:
            return calendar.date(byAdding: .month, value: interval, to: date)
        }
    }

    private static func progressMetrics(
        from startDay: Date,
        to endDay: Date,
        today: Date,
        calendar: Calendar
    ) -> (totalDays: Int, progress: Double) {
        let totalDays = max(1, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        let elapsedDays = min(
            totalDays,
            max(0, (calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1)
        )
        let progress = min(1, max(0, Double(elapsedDays) / Double(totalDays)))
        return (totalDays, progress)
    }

    private static func remainingDays(
        status: EventWindow.Status,
        today: Date,
        startDay: Date,
        endDay: Date,
        calendar: Calendar
    ) -> Int {
        switch status {
        case .active:
            return max(0, calendar.dateComponents([.day], from: today, to: endDay).day ?? 0)
        case .upcoming:
            return max(0, calendar.dateComponents([.day], from: today, to: startDay).day ?? 0)
        case .recentlyEnded:
            return 0
        }
    }
}
