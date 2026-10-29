import Foundation
import SwiftData

/// Hands-off snapshots and archives written to a folder outside the app container.
///
/// Two different things live here:
///
/// - **Weekly snapshots** are complete backups — every entry, expense, location,
///   recurrence, notification rule, progress record, completion, and pity counter.
///   The newest one alone is a full restore point.
/// - **Monthly/yearly archives** are period-scoped extracts shaped for an LLM
///   (see `ArchiveService`). They are not importable as backups.
///
/// iOS has no reliable timer, so "when" is expressed as a slot. The app checks
/// whether the slot has passed whenever it launches, returns to the foreground, or
/// is handed a background refresh — whichever happens first does the work.
enum AutomaticBackup {
    // MARK: - Keys

    static let enabledKey = "lifeos.autoBackupEnabled"
    static let weekdayKey = "lifeos.autoBackupWeekday"
    static let hourKey = "lifeos.autoBackupHour"
    static let minuteKey = "lifeos.autoBackupMinute"

    static let monthlyEnabledKey = "lifeos.autoBackupMonthlyEnabled"
    static let yearlyEnabledKey = "lifeos.autoBackupYearlyEnabled"

    private static let lastSuccessKey = "lifeos.autoBackupLastSuccess"
    private static let lastAttemptKey = "lifeos.autoBackupLastAttempt"
    private static let lastErrorKey = "lifeos.autoBackupLastError"

    private static let lastMonthlyLabelKey = "lifeos.autoBackupMonthlyLastLabel"
    private static let lastMonthlyAtKey = "lifeos.autoBackupMonthlyLastAt"
    private static let lastMonthlyAttemptKey = "lifeos.autoBackupMonthlyLastAttempt"
    private static let lastMonthlyErrorKey = "lifeos.autoBackupMonthlyLastError"

    private static let lastYearlyLabelKey = "lifeos.autoBackupYearlyLastLabel"
    private static let lastYearlyAtKey = "lifeos.autoBackupYearlyLastAt"
    private static let lastYearlyAttemptKey = "lifeos.autoBackupYearlyLastAttempt"
    private static let lastYearlyErrorKey = "lifeos.autoBackupYearlyLastError"

    // MARK: - Defaults

    /// Sunday at 8 PM. Adjustable in Settings. Monthly/yearly archives reuse the
    /// same time on the first day of the following period.
    static let defaultWeekday = 1
    static let defaultHour = 20
    static let defaultMinute = 0

    /// Roughly three months of weekly snapshots. Older ones are pruned after each write.
    static let weeklyRetentionCount = 12
    /// Two years of month archives.
    static let monthlyRetentionCount = 24
    /// Ten years of year archives.
    static let yearlyRetentionCount = 10
    /// Never generate more than this many months in one catch-up run.
    private static let monthlyCatchUpLimit = 12
    /// Never generate more than this many years in one catch-up run.
    private static let yearlyCatchUpLimit = 5

    static let weeklyPrefix = "LifeOS-Weekly-"
    static let monthlyPrefix = "LifeOS-Month-"
    static let yearlyPrefix = "LifeOS-Year-"
    static let manualPrefix = "LifeOS-Manual-"

    /// A failed attempt (unreachable iCloud folder, offline, revoked permission) is
    /// retried after this long instead of on every foreground transition.
    private static let retryBackoff: TimeInterval = 30 * 60

    struct Record: Equatable, Sendable {
        let url: URL
        let createdAt: Date
        let entryCount: Int
        let pityCount: Int
        let byteCount: Int
    }

    struct RunOutcome: Equatable, Sendable {
        var records: [Record] = []
        var failures: [String] = []

        var wroteSomething: Bool { !records.isEmpty }
        var succeeded: Bool { failures.isEmpty }
    }

    // MARK: - Defaults

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            enabledKey: false,
            weekdayKey: defaultWeekday,
            hourKey: defaultHour,
            minuteKey: defaultMinute,
            monthlyEnabledKey: false,
            yearlyEnabledKey: false,
        ])
    }

    // MARK: - Settings

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var isMonthlyEnabled: Bool {
        UserDefaults.standard.bool(forKey: monthlyEnabledKey)
    }

    static var isYearlyEnabled: Bool {
        UserDefaults.standard.bool(forKey: yearlyEnabledKey)
    }

    static func isArchiveEnabled(_ kind: ArchiveService.Kind) -> Bool {
        switch kind {
        case .month: return isMonthlyEnabled
        case .year: return isYearlyEnabled
        }
    }

    /// `Calendar` weekday numbering: 1 = Sunday … 7 = Saturday.
    static var weekday: Int {
        let value = UserDefaults.standard.integer(forKey: weekdayKey)
        return (1...7).contains(value) ? value : defaultWeekday
    }

    static var hour: Int {
        guard UserDefaults.standard.object(forKey: hourKey) != nil else { return defaultHour }
        let value = UserDefaults.standard.integer(forKey: hourKey)
        return (0...23).contains(value) ? value : defaultHour
    }

    static var minute: Int {
        guard UserDefaults.standard.object(forKey: minuteKey) != nil else { return defaultMinute }
        let value = UserDefaults.standard.integer(forKey: minuteKey)
        return (0...59).contains(value) ? value : defaultMinute
    }

    static var lastSuccessAt: Date? {
        UserDefaults.standard.object(forKey: lastSuccessKey) as? Date
    }

    static var lastErrorMessage: String? {
        UserDefaults.standard.string(forKey: lastErrorKey)
    }

    static func lastArchiveLabel(_ kind: ArchiveService.Kind) -> String? {
        UserDefaults.standard.string(forKey: labelKey(for: kind))
    }

    static func lastArchiveAt(_ kind: ArchiveService.Kind) -> Date? {
        UserDefaults.standard.object(forKey: atKey(for: kind)) as? Date
    }

    static func lastArchiveErrorMessage(_ kind: ArchiveService.Kind) -> String? {
        UserDefaults.standard.string(forKey: errorKey(for: kind))
    }

    static func clearErrors() {
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
        for kind in ArchiveService.Kind.allCases {
            UserDefaults.standard.removeObject(forKey: errorKey(for: kind))
        }
    }

    /// Call after changing the schedule so the UI and the pending background
    /// request both reflect the new slot.
    static func settingsDidChange() {
        clearErrors()
    }

    // MARK: - Schedule math

    static func weekdayName(for weekday: Int, locale: Locale = .current) -> String {
        // 2024-01-07 was a Sunday, so `weekday + 6` walks the week reliably without
        // depending on the locale's first weekday.
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 6 + max(1, min(7, weekday))
        guard let date = calendar.date(from: components) else { return "" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func nextScheduledDate(after date: Date, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        components.second = 0

        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? date.addingTimeInterval(7 * 86_400)
    }

    /// Nil when weekly backups are off or no folder is configured. May be in the
    /// past, which means the slot has already passed and the next check will run it.
    static func nextDueDate(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard isEnabled, BackupDestination.isConfigured else { return nil }
        guard let lastSuccess = lastSuccessAt else { return now }
        return nextScheduledDate(after: lastSuccess, calendar: calendar)
    }

    static func isDue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard isEnabled, BackupDestination.isConfigured else { return false }

        if let lastSuccess = lastSuccessAt,
           nextScheduledDate(after: lastSuccess, calendar: calendar) > now {
            return false
        }

        if let lastAttempt = UserDefaults.standard.object(forKey: lastAttemptKey) as? Date,
           lastAttempt > (lastSuccessAt ?? .distantPast),
           now.timeIntervalSince(lastAttempt) < retryBackoff {
            return false
        }

        return true
    }

    /// When the archive for the just-finished period may run: the first day of the
    /// current period at the shared time.
    static func archiveSlot(
        for kind: ArchiveService.Kind,
        periodStart: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: periodStart) ?? periodStart
    }

    /// True once the period has ended and its slot has passed, unless that period
    /// was already archived (or a recent attempt failed and is backing off).
    static func isArchiveDue(
        _ kind: ArchiveService.Kind,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard isArchiveEnabled(kind), BackupDestination.isConfigured else { return false }

        let current = ArchiveService.period(kind, containing: now, calendar: calendar)
        guard now >= archiveSlot(for: kind, periodStart: current.start, calendar: calendar) else {
            return false
        }

        let lastCompleted = ArchiveService.lastCompletedPeriod(kind, now: now, calendar: calendar)
        if let stored = lastArchiveLabel(kind), stored >= lastCompleted.label { return false }

        if let attempt = UserDefaults.standard.object(forKey: attemptKey(for: kind)) as? Date,
           attempt > (lastArchiveAt(kind) ?? .distantPast),
           now.timeIntervalSince(attempt) < retryBackoff {
            return false
        }

        return true
    }

    /// Earliest of the weekly slot and the next archive slots. Nil when nothing is on.
    static func nextWakeDate(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard BackupDestination.isConfigured else { return nil }
        var candidates: [Date] = []

        if isEnabled {
            if isDue(now: now, calendar: calendar) {
                candidates.append(now)
            } else if let lastSuccess = lastSuccessAt {
                let next = nextScheduledDate(after: lastSuccess, calendar: calendar)
                // A slot in the past means the last attempt failed and is backing off.
                candidates.append(next <= now ? now.addingTimeInterval(retryBackoff) : next)
            } else {
                candidates.append(now)
            }
        }

        for kind in ArchiveService.Kind.allCases where isArchiveEnabled(kind) {
            if isArchiveDue(kind, now: now, calendar: calendar) {
                candidates.append(now)
                continue
            }

            let lastCompleted = ArchiveService.lastCompletedPeriod(kind, now: now, calendar: calendar)
            if let stored = lastArchiveLabel(kind), stored >= lastCompleted.label {
                // Nothing owed; wake for the next period boundary.
                let current = ArchiveService.period(kind, containing: now, calendar: calendar)
                let thisSlot = archiveSlot(for: kind, periodStart: current.start, calendar: calendar)
                candidates.append(
                    thisSlot > now
                        ? thisSlot
                        : archiveSlot(for: kind, periodStart: current.end, calendar: calendar)
                )
            } else {
                // Owed but not due right now (backoff / slot not reached yet).
                let current = ArchiveService.period(kind, containing: now, calendar: calendar)
                let thisSlot = archiveSlot(for: kind, periodStart: current.start, calendar: calendar)
                candidates.append(thisSlot > now ? thisSlot : now.addingTimeInterval(retryBackoff))
            }
        }

        return candidates.min()
    }

    /// "Every Sunday at 8:00 PM" / "Off".
    static func scheduleSummary(locale: Locale = .current) -> String {
        guard isEnabled else { return "Off" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "h:mm a"

        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 7
        components.hour = hour
        components.minute = minute
        let time = calendar.date(from: components).map { formatter.string(from: $0) } ?? ""

        return "Every \(weekdayName(for: weekday, locale: locale)) at \(time)"
    }

    // MARK: - Running

    /// Runs whichever weekly/archive slots are due. Safe to call on every launch,
    /// foreground transition, and background refresh.
    @MainActor
    @discardableResult
    static func runAllIfDue(modelContext: ModelContext, now: Date = .now) -> RunOutcome {
        var outcome = RunOutcome()

        if isDue(now: now) {
            do {
                outcome.records.append(try writeWeekly(modelContext: modelContext, now: now))
            } catch {
                recordWeeklyFailure(error, at: now)
                outcome.failures.append(error.localizedDescription)
            }
        }

        for kind in ArchiveService.Kind.allCases where isArchiveDue(kind, now: now) {
            for period in periodsToArchive(kind, now: now) {
                do {
                    outcome.records.append(
                        try archiveNow(kind, modelContext: modelContext, period: period, now: now)
                    )
                } catch {
                    recordArchiveFailure(kind, error: error, at: now)
                    outcome.failures.append(error.localizedDescription)
                    break
                }
            }
        }

        return outcome
    }

    /// A complete snapshot written on demand. It uses its own prefix and does not
    /// touch the weekly schedule, so pressing it repeatedly can never evict the
    /// weekly restore points.
    @MainActor
    @discardableResult
    static func backupNow(modelContext: ModelContext, now: Date = .now) throws -> Record {
        let payload = try snapshotPayload(modelContext: modelContext)

        return try BackupDestination.withAccess { folder -> Record in
            let target = folder.appendingPathComponent(manualFileName(at: now))
            try payload.data.write(to: target, options: .atomic)
            return Record(
                url: target,
                createdAt: now,
                entryCount: payload.entryCount,
                pityCount: payload.pityCount,
                byteCount: payload.data.count
            )
        }
    }

    /// Internal: writes a full weekly snapshot and advances the weekly schedule.
    @MainActor
    @discardableResult
    static func writeWeekly(modelContext: ModelContext, now: Date = .now) throws -> Record {
        let payload = try snapshotPayload(modelContext: modelContext)

        let record = try BackupDestination.withAccess { folder -> Record in
            let target = folder.appendingPathComponent(fileName(at: now))
            try payload.data.write(to: target, options: .atomic)
            prune(in: folder, prefix: weeklyPrefix, keeping: weeklyRetentionCount)
            return Record(
                url: target,
                createdAt: now,
                entryCount: payload.entryCount,
                pityCount: payload.pityCount,
                byteCount: payload.data.count
            )
        }

        UserDefaults.standard.set(now, forKey: lastSuccessKey)
        UserDefaults.standard.set(now, forKey: lastAttemptKey)
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
        return record
    }

    /// Writes one month/year archive. Passing `period` explicitly is how catch-up
    /// fills gaps; the UI's manual buttons pass the last completed period.
    @MainActor
    @discardableResult
    static func archiveNow(
        _ kind: ArchiveService.Kind,
        modelContext: ModelContext,
        period: ArchiveService.Period? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Record {
        let targetPeriod = period ?? ArchiveService.lastCompletedPeriod(kind, now: now, calendar: calendar)
        let entries = try modelContext.fetch(
            FetchDescriptor<Entry>(sortBy: [SortDescriptor(\Entry.startDate)])
        )

        let document = ArchiveService.makeDocument(
            entries: entries,
            kind: kind,
            period: targetPeriod,
            now: now,
            calendar: calendar
        )
        let data = try ArchiveService.encode(document)

        // Same rule as backups: never leave a file that cannot be read back.
        _ = try ArchiveService.decode(data)

        let fileName = ArchiveService.fileName(kind: kind, period: targetPeriod)
        let record = try BackupDestination.withAccess { folder -> Record in
            let target = folder.appendingPathComponent(fileName)
            try data.write(to: target, options: .atomic)
            prune(
                in: folder,
                prefix: prefix(for: kind),
                keeping: kind == .month ? monthlyRetentionCount : yearlyRetentionCount
            )
            return Record(
                url: target,
                createdAt: now,
                entryCount: document.totals.events,
                pityCount: 0,
                byteCount: data.count
            )
        }

        advanceArchiveState(kind, period: targetPeriod, at: now)
        return record
    }

    static func periodsToArchive(
        _ kind: ArchiveService.Kind,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ArchiveService.Period] {
        ArchiveService.periodsToArchive(
            kind,
            after: lastArchiveLabel(kind),
            now: now,
            limit: kind == .month ? monthlyCatchUpLimit : yearlyCatchUpLimit,
            calendar: calendar
        )
    }

    // MARK: - File names

    static func fileName(at date: Date) -> String {
        weeklyPrefix + timestamp(date) + ".json"
    }

    static func manualFileName(at date: Date) -> String {
        manualPrefix + timestamp(date) + ".json"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }

    static func prefix(for kind: ArchiveService.Kind) -> String {
        switch kind {
        case .month: return monthlyPrefix
        case .year: return yearlyPrefix
        }
    }

    /// Keeps only the newest `limit` files with `prefix`. Manual exports, archives,
    /// and anything the user dropped in the folder are left alone.
    static func prune(in folder: URL, prefix: String, keeping limit: Int) {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let snapshots = contents
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for url in snapshots.dropFirst(max(0, limit)) {
            try? manager.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private struct SnapshotPayload {
        let data: Data
        let entryCount: Int
        let pityCount: Int
    }

    @MainActor
    private static func snapshotPayload(modelContext: ModelContext) throws -> SnapshotPayload {
        let entries = try modelContext.fetch(
            FetchDescriptor<Entry>(sortBy: [SortDescriptor(\Entry.startDate)])
        )
        let trackers = (try? modelContext.fetch(
            FetchDescriptor<PityTracker>(sortBy: [SortDescriptor(\PityTracker.sortOrder)])
        )) ?? []

        let data = try BackupService.exportData(entries: entries, pityTrackers: trackers)
        // Round-trip before the file leaves the app. A truncated JSON file that looks
        // like a backup is worse than no file at all.
        _ = try BackupService.decode(data)

        return SnapshotPayload(data: data, entryCount: entries.count, pityCount: trackers.count)
    }

    private static func recordWeeklyFailure(_ error: Error, at now: Date) {
        UserDefaults.standard.set(now, forKey: lastAttemptKey)
        UserDefaults.standard.set(error.localizedDescription, forKey: lastErrorKey)
    }

    private static func recordArchiveFailure(
        _ kind: ArchiveService.Kind,
        error: Error,
        at now: Date
    ) {
        UserDefaults.standard.set(now, forKey: attemptKey(for: kind))
        UserDefaults.standard.set(error.localizedDescription, forKey: errorKey(for: kind))
    }

    private static func advanceArchiveState(
        _ kind: ArchiveService.Kind,
        period: ArchiveService.Period,
        at now: Date
    ) {
        let stored = lastArchiveLabel(kind)
        // Labels are zero-padded, so string comparison is chronological.
        if stored == nil || period.label > stored! {
            UserDefaults.standard.set(period.label, forKey: labelKey(for: kind))
        }
        UserDefaults.standard.set(now, forKey: atKey(for: kind))
        UserDefaults.standard.set(now, forKey: attemptKey(for: kind))
        UserDefaults.standard.removeObject(forKey: errorKey(for: kind))
    }

    private static func labelKey(for kind: ArchiveService.Kind) -> String {
        kind == .month ? lastMonthlyLabelKey : lastYearlyLabelKey
    }

    private static func atKey(for kind: ArchiveService.Kind) -> String {
        kind == .month ? lastMonthlyAtKey : lastYearlyAtKey
    }

    private static func attemptKey(for kind: ArchiveService.Kind) -> String {
        kind == .month ? lastMonthlyAttemptKey : lastYearlyAttemptKey
    }

    private static func errorKey(for kind: ArchiveService.Kind) -> String {
        kind == .month ? lastMonthlyErrorKey : lastYearlyErrorKey
    }
}
