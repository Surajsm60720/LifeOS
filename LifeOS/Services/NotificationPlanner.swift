import Foundation
import UserNotifications

/// Builds and syncs local notifications off the hot UI path.
/// Important: never blanket-cancel imminent pending requests — that was cancelling
/// reminders right before they fired whenever the app refreshed.
actor NotificationPlanner {
    static let shared = NotificationPlanner()

    private let center = UNUserNotificationCenter.current()
    private let engine = RecurrenceEngine.shared
    private let maxPending = 64
    private let identifierPrefix = "lifeos-entry-"
    private let testPrefix = "lifeos-test-"
    private let protectWindow: TimeInterval = 120

    private var refreshTask: Task<Void, Never>?
    private var lastRefreshAt: Date = .distantPast

    struct ScheduleSnapshot: Sendable {
        struct Item: Sendable {
            let entryID: UUID
            let entryTitle: String
            let categoryName: String
            let isCompletable: Bool
            let supportsNotifications: Bool
            let startDate: Date
            let recurrence: RecurrenceSnapshot?
            let completedOccurrenceStarts: [Date]
            let rules: [RuleSnapshot]
        }

        struct RecurrenceSnapshot: Sendable {
            let frequency: RecurrenceFrequency
            let interval: Int
            let daysOfWeek: Set<Weekday>?
            let endDate: Date?
            let occurrenceCount: Int?
        }

        struct RuleSnapshot: Sendable {
            let ruleID: UUID
            let triggerKind: NotificationTriggerKind
            let triggerDate: Date?
            let triggerInterval: TimeInterval?
            let messageTemplate: String
            let isActive: Bool
        }

        let items: [Item]
    }

    /// Capture SwiftData models on the MainActor, then schedule concurrently.
    @MainActor
    static func snapshot(from entries: [Entry]) -> ScheduleSnapshot {
        ScheduleSnapshot(
            items: entries.map { entry in
                ScheduleSnapshot.Item(
                    entryID: entry.id,
                    entryTitle: entry.title,
                    categoryName: entry.category.displayName,
                    isCompletable: entry.isCompletable,
                    supportsNotifications: entry.supportsNotifications,
                    startDate: entry.startDate,
                    recurrence: entry.recurrence.map {
                        ScheduleSnapshot.RecurrenceSnapshot(
                            frequency: $0.frequency,
                            interval: max(1, $0.interval),
                            daysOfWeek: $0.daysOfWeek,
                            endDate: $0.endDate,
                            occurrenceCount: $0.occurrenceCount
                        )
                    },
                    completedOccurrenceStarts: entry.completions.map(\.occurrenceStart),
                    rules: entry.notificationRules.map {
                        ScheduleSnapshot.RuleSnapshot(
                            ruleID: $0.ruleID,
                            triggerKind: $0.triggerKind,
                            triggerDate: $0.triggerDate,
                            triggerInterval: $0.triggerInterval,
                            messageTemplate: $0.messageTemplate,
                            isActive: $0.isActive
                        )
                    }
                )
            }
        )
    }

    @MainActor
    static func refreshPendingNotifications(entries: [Entry], now: Date = .now, force: Bool = false) async {
        let snap = snapshot(from: entries)
        await shared.refresh(snapshot: snap, now: now, force: force)
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func pendingManagedCount() async -> Int {
        let pending = await center.pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(identifierPrefix) }.count
    }

    func pendingManagedSummaries() async -> [String] {
        let pending = await center.pendingNotificationRequests()
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return pending
            .filter { $0.identifier.hasPrefix(identifierPrefix) || $0.identifier.hasPrefix(testPrefix) }
            .compactMap { request -> (Date, String)? in
                guard let fire = nextFireDate(for: request) else { return nil }
                return (fire, "\(formatter.string(from: fire)) — \(request.content.body)")
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    /// Immediate proof that the system will deliver banners for this app.
    func scheduleTestNotification(after seconds: TimeInterval = 5) async -> Bool {
        guard await requestAuthorizationIfNeeded() else { return false }
        let id = testPrefix + UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = "LifeOS"
        content.body = "Test reminder — notifications are working."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func refresh(snapshot: ScheduleSnapshot, now: Date = .now, force: Bool = false) async {
        if !force, now.timeIntervalSince(lastRefreshAt) < 2 {
            return
        }

        refreshTask?.cancel()
        let task = Task {
            await self.performRefresh(snapshot: snapshot, now: now)
        }
        refreshTask = task
        await task.value
    }

    func cancel(entryID: UUID, on date: Date = .now, calendar: Calendar = .current) async {
        let pending = await center.pendingNotificationRequests()
        let dayKey = dayKey(for: date, calendar: calendar)
        let prefix = identifierPrefix + entryID.uuidString + "-" + dayKey
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAll(entryID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix + entryID.uuidString) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Core sync

    private func performRefresh(snapshot: ScheduleSnapshot, now: Date) async {
        guard await requestAuthorizationIfNeeded() else { return }
        lastRefreshAt = now

        let calendar = Calendar.current
        let desired = buildDesiredRequests(snapshot: snapshot, now: now, calendar: calendar)
        let desiredIDs = Set(desired.map(\.identifier))

        let pending = await center.pendingNotificationRequests()
        let managed = pending.filter { $0.identifier.hasPrefix(identifierPrefix) }

        // Keep anything already scheduled that is about to fire — do not cancel/recreate it.
        var protectedIDs = Set<String>()
        for request in managed {
            if let fire = nextFireDate(for: request), fire.timeIntervalSince(now) <= protectWindow, fire > now {
                protectedIDs.insert(request.identifier)
            }
        }

        let obsolete = managed
            .map(\.identifier)
            .filter { id in
                !desiredIDs.contains(id) && !protectedIDs.contains(id)
            }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }

        let existingIDs = Set(managed.map(\.identifier))
        let toAdd = desired.filter { !existingIDs.contains($0.identifier) && !protectedIDs.contains($0.identifier) }

        // Prefer soonest fires when capping at 64.
        let sortedAdd = toAdd.sorted { (nextFireDate(for: $0) ?? .distantFuture) < (nextFireDate(for: $1) ?? .distantFuture) }
        let remainingSlots = max(0, maxPending - (existingIDs.subtracting(Set(obsolete)).count))

        for request in sortedAdd.prefix(remainingSlots) {
            try? await center.add(request)
        }
    }

    private func buildDesiredRequests(
        snapshot: ScheduleSnapshot,
        now: Date,
        calendar: Calendar
    ) -> [UNNotificationRequest] {
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = DateFormatting.endOfDay(now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: todayStart) ?? todayEnd
        let range = todayStart...weekEnd

        var requests: [UNNotificationRequest] = []

        for item in snapshot.items where item.supportsNotifications {
            let activeRules = item.rules.filter(\.isActive)
            guard !activeRules.isEmpty else { continue }

            let occurrences = occurrenceDates(for: item, in: range, calendar: calendar)

            for rule in activeRules {
                switch rule.triggerKind {
                case .ifNotCompletedBy:
                    guard item.isCompletable else { continue }
                    for occurrence in occurrences {
                        if isCompleted(item: item, occurrence: occurrence, calendar: calendar) { continue }
                        let fire = fireDate(for: rule, occurrence: occurrence, calendar: calendar)
                        guard fire > now else { continue }
                        if let request = makeRequest(
                            entryID: item.entryID,
                            title: item.entryTitle,
                            categoryName: item.categoryName,
                            rule: rule,
                            fireDate: fire,
                            occurrence: occurrence,
                            now: now,
                            calendar: calendar
                        ) {
                            requests.append(request)
                        }
                    }

                case .fixedTime, .relativeToStart:
                    for occurrence in occurrences {
                        let fire = fireDate(for: rule, occurrence: occurrence, calendar: calendar)
                        guard fire > now else { continue }
                        if let request = makeRequest(
                            entryID: item.entryID,
                            title: item.entryTitle,
                            categoryName: item.categoryName,
                            rule: rule,
                            fireDate: fire,
                            occurrence: occurrence,
                            now: now,
                            calendar: calendar
                        ) {
                            requests.append(request)
                        }
                    }
                }
            }
        }

        return requests
    }

    private func occurrenceDates(
        for item: ScheduleSnapshot.Item,
        in range: ClosedRange<Date>,
        calendar: Calendar
    ) -> [Date] {
        // Build a lightweight ephemeral entry-like expansion via engine helpers.
        if let recurrence = item.recurrence {
            return engine.occurrences(
                frequency: recurrence.frequency,
                interval: recurrence.interval,
                daysOfWeek: recurrence.daysOfWeek,
                endDate: recurrence.endDate,
                occurrenceCount: recurrence.occurrenceCount,
                anchor: item.startDate,
                in: range,
                calendar: calendar
            )
        }
        guard range.contains(item.startDate) else { return [] }
        return [item.startDate]
    }

    private func isCompleted(item: ScheduleSnapshot.Item, occurrence: Date, calendar: Calendar) -> Bool {
        item.completedOccurrenceStarts.contains { calendar.isDate($0, inSameDayAs: occurrence) }
    }

    private func fireDate(
        for rule: ScheduleSnapshot.RuleSnapshot,
        occurrence: Date,
        calendar: Calendar
    ) -> Date {
        switch rule.triggerKind {
        case .fixedTime, .ifNotCompletedBy:
            if let triggerDate = rule.triggerDate {
                let time = calendar.dateComponents([.hour, .minute], from: triggerDate)
                return calendar.date(
                    bySettingHour: time.hour ?? 21,
                    minute: time.minute ?? 0,
                    second: 0,
                    of: calendar.startOfDay(for: occurrence)
                ) ?? occurrence
            }
            return calendar.date(
                bySettingHour: 21,
                minute: 0,
                second: 0,
                of: calendar.startOfDay(for: occurrence)
            ) ?? occurrence
        case .relativeToStart:
            return occurrence.addingTimeInterval(rule.triggerInterval ?? 0)
        }
    }

    private func makeRequest(
        entryID: UUID,
        title: String,
        categoryName: String,
        rule: ScheduleSnapshot.RuleSnapshot,
        fireDate: Date,
        occurrence: Date,
        now: Date,
        calendar: Calendar
    ) -> UNNotificationRequest? {
        let interval = fireDate.timeIntervalSince(now)
        guard interval > 0 else { return nil }

        let trigger: UNNotificationTrigger
        if interval <= 12 * 60 * 60 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, ceil(interval)), repeats: false)
        } else {
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let content = UNMutableNotificationContent()
        content.title = "LifeOS"
        content.body = rule.messageTemplate
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{category}", with: categoryName)
        content.sound = .default

        let identifier = identifierPrefix
            + entryID.uuidString
            + "-"
            + dayKey(for: occurrence, calendar: calendar)
            + "-"
            + rule.ruleID.uuidString

        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func nextFireDate(for request: UNNotificationRequest) -> Date? {
        if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger {
            return calendarTrigger.nextTriggerDate()
        }
        if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
            return intervalTrigger.nextTriggerDate()
        }
        return nil
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: day)
    }
}
