import XCTest
import SwiftData
@testable import LifeOS

/// Locks in the fixes made during the pre-1.0 audit. Each test maps to a specific
/// finding, so a regression names the behaviour that broke rather than just failing.
@MainActor
final class AuditRegressionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: LifeOSSharedStore.schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        return calendar.date(from: c)!
    }

    // MARK: - Backup compatibility

    func testOlderBackupVersionsRemainReadable() throws {
        // The gate previously required an exact version match, so bumping
        // `currentVersion` would have orphaned every backup already on disk.
        XCTAssertLessThanOrEqual(
            BackupService.minimumSupportedVersion,
            BackupService.currentVersion,
            "Minimum supported version must not exceed the current version"
        )

        let entry = Entry(title: "Old Backup Entry", category: .irl, startDate: date(2026, 3, 1))
        context.insert(entry)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Entry>())
        let data = try BackupService.exportData(entries: all)
        let decoded = try BackupService.decode(data)
        XCTAssertEqual(decoded.version, BackupService.currentVersion)
        XCTAssertEqual(decoded.entries.count, 1)
    }

    func testBackupFromNewerVersionIsRejectedWithClearMessage() throws {
        let future = BackupService.currentVersion + 1
        var document = BackupService.makeDocument(entries: [])
        document.version = future

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        XCTAssertThrowsError(try BackupService.decode(data)) { error in
            let message = (error as? BackupService.BackupError)?.errorDescription ?? ""
            XCTAssertTrue(
                message.contains("newer version"),
                "Expected a message telling the user to update the app, got: \(message)"
            )
        }
    }

    func testDuplicateRuleIDsInBackupDoNotTrap() throws {
        // `ruleID` is not DB-enforced unique. A corrupted or hand-edited backup with
        // duplicates previously hit `Dictionary(uniqueKeysWithValues:)` and crashed.
        let entry = Entry(title: "Dupe Rules", category: .irl, startDate: date(2026, 4, 1))
        entry.isCompletable = true
        context.insert(entry)

        let sharedID = UUID()
        for _ in 0..<2 {
            let rule = NotificationRule(
                triggerKind: .ifNotCompletedBy,
                triggerDate: date(2026, 4, 1, hour: 21),
                messageTemplate: "Reminder"
            )
            rule.ruleID = sharedID
            rule.entry = entry
            entry.notificationRules.append(rule)
            context.insert(rule)
        }
        try context.save()

        let data = try BackupService.exportData(entries: [entry])
        let document = try BackupService.decode(data)

        // Must not trap.
        XCTAssertNoThrow(try BackupService.merge(document: document, modelContext: context))
    }

    func testUnknownCategoryIsCoercedOnMergeUpdate() throws {
        // Insert and merge-update must coerce identically; the merge path used to
        // write the raw string straight onto the model.
        let entry = Entry(title: "Coerce Me", category: .irl, startDate: date(2026, 5, 1))
        context.insert(entry)
        try context.save()

        var document = BackupService.makeDocument(entries: [entry])
        document.entries[0].categoryRaw = "notARealCategory"

        _ = try BackupService.merge(document: document, modelContext: context)

        let updated = try XCTUnwrap(context.fetch(FetchDescriptor<Entry>()).first { $0.title == "Coerce Me" })
        XCTAssertNotNil(
            EntryCategory(rawValue: updated.categoryRaw),
            "Merge left an uncoercible categoryRaw (\(updated.categoryRaw)) on the model"
        )
        XCTAssertEqual(updated.categoryRaw, EntryCategory.irl.rawValue)
    }

    // MARK: - Recurrence expansion

    func testExpansionIsCappedForHeavyDailyRecurrence() {
        // Year view over a large library of daily habits previously materialized
        // hundreds of thousands of occurrence objects with no ceiling.
        var entries: [Entry] = []
        for i in 0..<500 {
            let entry = Entry(title: "Habit \(i)", category: .irl, startDate: date(2026, 1, 1))
            entry.recurrence = RecurrenceRule(frequency: .daily, interval: 1)
            entries.append(entry)
        }

        let year = DateInterval(start: date(2026, 1, 1, hour: 0), end: date(2026, 12, 31, hour: 23))
        let occurrences = RecurrenceEngine.shared.expandEntries(entries, in: year, calendar: calendar)

        XCTAssertLessThanOrEqual(
            occurrences.count,
            RecurrenceEngine.maxExpandedOccurrences,
            "expandEntries exceeded its aggregate cap"
        )
        XCTAssertFalse(occurrences.isEmpty)
    }

    func testExpansionSkipsEntriesOutsideRange() {
        // The O(1) pre-filter must not drop entries that legitimately overlap.
        let inRange = Entry(title: "In", category: .irl, startDate: date(2026, 6, 15))
        let future = Entry(title: "Future", category: .irl, startDate: date(2030, 1, 1))
        let ended = Entry(title: "Ended", category: .irl, startDate: date(2020, 1, 1))
        ended.recurrence = RecurrenceRule(frequency: .daily, interval: 1, endDate: date(2021, 1, 1))

        let june = DateInterval(start: date(2026, 6, 1, hour: 0), end: date(2026, 6, 30, hour: 23))
        let result = RecurrenceEngine.shared.expandEntries([inRange, future, ended], in: june, calendar: calendar)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.entry.title, "In")
    }

    func testCountMatchesExpansion() {
        // `countOccurrences` is the allocation-free path used for header subtitles;
        // it must agree with the full expansion.
        var entries: [Entry] = []
        for i in 0..<40 {
            let entry = Entry(title: "Mixed \(i)", category: .irl, startDate: date(2026, 3, 1))
            if i % 3 == 0 {
                entry.recurrence = RecurrenceRule(frequency: .daily, interval: 2)
            } else if i % 3 == 1 {
                entry.recurrence = RecurrenceRule(frequency: .weekly, interval: 1)
            }
            entries.append(entry)
        }

        let month = DateInterval(start: date(2026, 3, 1, hour: 0), end: date(2026, 3, 31, hour: 23))
        let expanded = RecurrenceEngine.shared.expandEntries(entries, in: month, calendar: calendar)
        let counted = RecurrenceEngine.shared.countOccurrences(entries, in: month, calendar: calendar)

        XCTAssertEqual(expanded.count, counted)
    }

    func testOccurrenceIDsAreUniquePerOccurrence() {
        // The id moved from an interpolated string to a composite key; it still has
        // to disambiguate rows for SwiftUI's ForEach.
        let entry = Entry(title: "Daily", category: .irl, startDate: date(2026, 2, 1))
        entry.recurrence = RecurrenceRule(frequency: .daily, interval: 1)

        let week = DateInterval(start: date(2026, 2, 1, hour: 0), end: date(2026, 2, 7, hour: 23))
        let occurrences = RecurrenceEngine.shared.expandEntries([entry], in: week, calendar: calendar)

        XCTAssertEqual(Set(occurrences.map(\.id)).count, occurrences.count, "Occurrence IDs collided")
    }

    func testNormalizeOccurrenceStartStillMatchesCompletions() {
        // `normalizeOccurrenceStart` no longer re-runs a full expansion. It must still
        // produce a value that `isCompleted` matches for the same day.
        let entry = Entry(title: "Habit", category: .irl, startDate: date(2026, 7, 1, hour: 14))
        entry.isCompletable = true
        entry.recurrence = RecurrenceRule(frequency: .daily, interval: 1)
        context.insert(entry)

        let targetDay = date(2026, 7, 10, hour: 14)
        let normalized = RecurrenceEngine.shared.normalizeOccurrenceStart(targetDay, for: entry, calendar: calendar)

        let completion = EntryCompletion(occurrenceStart: normalized)
        completion.entry = entry
        entry.completions.append(completion)
        context.insert(completion)

        XCTAssertTrue(
            entry.isCompleted(on: targetDay, calendar: calendar),
            "Completion recorded via normalizeOccurrenceStart was not detected by isCompleted"
        )
        XCTAssertFalse(entry.isCompleted(on: date(2026, 7, 11, hour: 14), calendar: calendar))
    }

    // MARK: - Store mutation signal

    func testDataVersionAdvancesOnMutations() {
        // Views cache expansions and invalidate on `dataVersion`. If a mutation path
        // stops bumping it, those caches go stale and the UI silently lies.
        let store = EntryStore()
        let entry = Entry(title: "Versioned", category: .irl, startDate: date(2026, 8, 1))
        entry.isCompletable = true
        context.insert(entry)

        let afterInsert = store.dataVersion
        store.toggleCompletion(for: entry, on: date(2026, 8, 1), modelContext: context)
        XCTAssertGreaterThan(store.dataVersion, afterInsert, "toggleCompletion did not bump dataVersion")

        let afterToggle = store.dataVersion
        store.delete(entry: entry, modelContext: context)
        XCTAssertGreaterThan(store.dataVersion, afterToggle, "delete did not bump dataVersion")
    }

    // MARK: - All-day entries

    func testAllDayEntryRoundTripsThroughBackup() throws {
        let entry = Entry(
            title: "Leave",
            category: .irl,
            startDate: date(2026, 7, 15, hour: 14),
            isAllDay: true
        )
        entry.normalizeStartDateIfAllDay(calendar: calendar)
        context.insert(entry)
        try context.save()

        let data = try BackupService.exportData(entries: [entry])
        let document = try BackupService.decode(data)
        XCTAssertEqual(document.entries.first?.isAllDay, true)

        let freshConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        let freshContainer = try ModelContainer(for: LifeOSSharedStore.schema, configurations: [freshConfig])
        let freshContext = ModelContext(freshContainer)
        _ = try BackupService.merge(document: document, modelContext: freshContext)

        let restored = try freshContext.fetch(FetchDescriptor<Entry>()).first!
        XCTAssertTrue(restored.isAllDay)
        XCTAssertEqual(
            restored.startDate,
            Calendar.current.startOfDay(for: restored.startDate),
            "All-day start dates should be stored at the start of the day"
        )
    }

    func testAllDayRecurringOccurrencesNormalizeToDayStart() {
        let entry = Entry(
            title: "Daily Leave",
            category: .irl,
            startDate: date(2026, 7, 1),
            isAllDay: true,
            isCompletable: true
        )
        entry.recurrence = RecurrenceRule(frequency: .daily, interval: 1)
        context.insert(entry)

        let tapDay = date(2026, 7, 10, hour: 15)
        let normalized = RecurrenceEngine.shared.normalizeOccurrenceStart(tapDay, for: entry, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: normalized), 0)
        XCTAssertTrue(calendar.isDate(normalized, inSameDayAs: tapDay))
    }

    // MARK: - App lock

    func testAppLockStartsLockedWhenEnabled() {
        // A cold launch used to render app content for a frame before locking.
        UserDefaults.standard.set(AppLockMode.biometric.rawValue, forKey: AppLockManager.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLockManager.storageKey) }

        let manager = AppLockManager()
        XCTAssertTrue(manager.isEnabled)
        XCTAssertTrue(manager.isLocked, "Lock must be engaged before the first frame renders")
    }

    func testAppLockStartsUnlockedWhenDisabled() {
        UserDefaults.standard.removeObject(forKey: AppLockManager.storageKey)

        let manager = AppLockManager()
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isLocked)
    }

    func testLockIfEnabledIsInertWhenDisabled() {
        UserDefaults.standard.removeObject(forKey: AppLockManager.storageKey)

        let manager = AppLockManager()
        manager.lockIfEnabled()
        XCTAssertFalse(manager.isLocked, "Backgrounding must not lock when App Lock is off")
    }
}
