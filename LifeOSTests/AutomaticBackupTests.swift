import XCTest
import SwiftData
@testable import LifeOS

@MainActor
final class AutomaticBackupTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar!
    private var folder: URL!

    override func setUp() {
        super.setUp()

        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: LifeOSSharedStore.schema, configurations: [config])
        context = ModelContext(container)

        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeOSAutoBackupTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! BackupDestination.store(url: folder)

        UserDefaults.standard.set(true, forKey: AutomaticBackup.enabledKey)
        UserDefaults.standard.set(false, forKey: AutomaticBackup.monthlyEnabledKey)
        UserDefaults.standard.set(false, forKey: AutomaticBackup.yearlyEnabledKey)
    }

    override func tearDown() {
        BackupDestination.clear()
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("lifeos.autoBackup") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: folder)
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Schedule math

    func testNextScheduledDateLandsOnConfiguredWeekdayAndTime() {
        setSlot(weekday: 2, hour: 9, minute: 30) // Monday

        // Wednesday 28 October 2026, 12:00 UTC.
        let from = date(2026, 10, 28, 12, 0)
        let next = AutomaticBackup.nextScheduledDate(after: from, calendar: calendar)

        XCTAssertEqual(next, date(2026, 11, 2, 9, 30))
        XCTAssertEqual(calendar.component(.weekday, from: next), 2)
    }

    func testNextScheduledDateRollsForwardAWeekWhenSlotAlreadyPassed() {
        setSlot(weekday: 2, hour: 9, minute: 30) // Monday

        // Monday 2 November 2026, 10:00 UTC — this week's slot is already gone.
        let from = date(2026, 11, 2, 10, 0)
        let next = AutomaticBackup.nextScheduledDate(after: from, calendar: calendar)

        XCTAssertEqual(next, date(2026, 11, 9, 9, 30))
    }

    func testWeekdayNamesCoverTheWholeWeek() {
        let names = (1...7).map { AutomaticBackup.weekdayName(for: $0, locale: Locale(identifier: "en_US_POSIX")) }
        XCTAssertEqual(names, ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"])
    }

    // MARK: - Weekly due logic

    func testNothingIsDueBeforeTheSlot() throws {
        setSlot(weekday: 1, hour: 20, minute: 0) // Sunday 8 PM
        let start = date(2026, 10, 28, 12, 0)   // Wednesday

        try AutomaticBackup.writeWeekly(modelContext: context, now: start)

        XCTAssertFalse(AutomaticBackup.isDue(now: start.addingTimeInterval(3_600), calendar: calendar))
        XCTAssertFalse(AutomaticBackup.isDue(now: date(2026, 11, 1, 19, 59), calendar: calendar))
    }

    func testSlotBecomesDueOnceItPasses() throws {
        setSlot(weekday: 1, hour: 20, minute: 0)
        let start = date(2026, 10, 28, 12, 0)

        try AutomaticBackup.writeWeekly(modelContext: context, now: start)

        XCTAssertTrue(AutomaticBackup.isDue(now: date(2026, 11, 1, 20, 1), calendar: calendar))
    }

    func testDisabledScheduleIsNeverDue() throws {
        try AutomaticBackup.writeWeekly(modelContext: context, now: date(2026, 10, 28, 12, 0))
        UserDefaults.standard.set(false, forKey: AutomaticBackup.enabledKey)

        XCTAssertFalse(AutomaticBackup.isDue(now: date(2026, 12, 1, 12, 0), calendar: calendar))
    }

    func testMissingFolderIsNeverDue() {
        BackupDestination.clear()

        XCTAssertFalse(AutomaticBackup.isDue(now: date(2026, 12, 1, 12, 0), calendar: calendar))
    }

    // MARK: - Writing

    func testWeeklySnapshotWritesReadableFile() throws {
        let entry = Entry(title: "Dentist", category: .irl, startDate: date(2026, 10, 28, 9, 0), isCompletable: true)
        context.insert(entry)
        let tracker = PityTracker(
            game: .genshinImpact,
            name: "Character",
            hardPity: 90,
            guaranteeKind: .fiftyFifty
        )
        context.insert(tracker)
        try context.save()

        let now = date(2026, 11, 1, 20, 0)
        let record = try AutomaticBackup.writeWeekly(modelContext: context, now: now)

        XCTAssertEqual(record.entryCount, 1)
        XCTAssertEqual(record.pityCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.url.path))
        XCTAssertEqual(record.url.lastPathComponent, AutomaticBackup.fileName(at: now))
        XCTAssertTrue(record.url.lastPathComponent.hasPrefix("LifeOS-Weekly-"))

        let document = try BackupService.decode(Data(contentsOf: record.url))
        XCTAssertEqual(document.entries.count, 1)
        XCTAssertEqual(document.pityTrackers?.count, 1)
        XCTAssertEqual(AutomaticBackup.lastSuccessAt, now)
        XCTAssertNil(AutomaticBackup.lastErrorMessage)
    }

    func testManualSnapshotUsesItsOwnPrefixAndLeavesWeeklyStateAlone() throws {
        let weeklyTime = date(2026, 10, 25, 20, 0)
        _ = try AutomaticBackup.writeWeekly(modelContext: context, now: weeklyTime)

        let manualTime = date(2026, 10, 28, 12, 0)
        let record = try AutomaticBackup.backupNow(modelContext: context, now: manualTime)

        XCTAssertTrue(record.url.lastPathComponent.hasPrefix("LifeOS-Manual-"))
        XCTAssertEqual(AutomaticBackup.lastSuccessAt, weeklyTime, "Manual snapshots must not move the weekly slot")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(AutomaticBackup.fileName(at: weeklyTime)).path),
            "The weekly restore point must survive a manual snapshot"
        )
    }

    func testFileNamesSortChronologically() {
        let earlier = AutomaticBackup.fileName(at: date(2026, 1, 4, 20, 0))
        let later = AutomaticBackup.fileName(at: date(2026, 1, 11, 20, 0))

        XCTAssertLessThan(earlier, later)
        XCTAssertTrue(earlier.hasPrefix(AutomaticBackup.weeklyPrefix))
        XCTAssertTrue(earlier.hasSuffix(".json"))
    }

    // MARK: - Retention

    func testRetentionKeepsNewestSnapshotsAndIgnoresOtherPrefixes() throws {
        for week in 0..<14 {
            let url = folder.appendingPathComponent("LifeOS-Weekly-2026-01-\(String(format: "%02d", week + 1))-2000.json")
            try Data("{}".utf8).write(to: url)
        }
        let manual = folder.appendingPathComponent("LifeOS-Manual-2026-01-01-1200.json")
        try Data("{}".utf8).write(to: manual)
        let monthly = folder.appendingPathComponent("LifeOS-Month-2025-12.json")
        try Data("{}".utf8).write(to: monthly)

        AutomaticBackup.prune(in: folder, prefix: AutomaticBackup.weeklyPrefix, keeping: 12)

        let remaining = try FileManager.default
            .contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(AutomaticBackup.weeklyPrefix) }
            .sorted()

        XCTAssertEqual(remaining.count, 12)
        XCTAssertEqual(remaining.first, "LifeOS-Weekly-2026-01-03-2000.json")
        XCTAssertEqual(remaining.last, "LifeOS-Weekly-2026-01-14-2000.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manual.path), "Manual snapshots must never be pruned")
        XCTAssertTrue(FileManager.default.fileExists(atPath: monthly.path), "Archives must never be pruned by the weekly rotation")
    }

    // MARK: - Archive periods

    func testMonthPeriodCoversTheWholeCalendarMonth() {
        let period = ArchiveService.period(.month, containing: date(2026, 2, 14, 12, 0), calendar: calendar)

        XCTAssertEqual(period.label, "2026-02")
        XCTAssertEqual(period.start, date(2026, 2, 1, 0, 0))
        XCTAssertEqual(period.end, date(2026, 3, 1, 0, 0))
    }

    func testMonthPeriodHandlesLeapFebruary() {
        let period = ArchiveService.period(.month, containing: date(2028, 2, 10, 0, 0), calendar: calendar)

        XCTAssertEqual(period.label, "2028-02")
        XCTAssertEqual(period.end, date(2028, 3, 1, 0, 0))
    }

    func testYearPeriodRunsJanuaryToDecember() {
        let period = ArchiveService.period(.year, containing: date(2026, 7, 4, 12, 0), calendar: calendar)

        XCTAssertEqual(period.label, "2026")
        XCTAssertEqual(period.start, date(2026, 1, 1, 0, 0))
        XCTAssertEqual(period.end, date(2027, 1, 1, 0, 0))
    }

    func testLastCompletedPeriodExcludesTheRunningPeriod() {
        let month = ArchiveService.lastCompletedPeriod(.month, now: date(2026, 10, 29, 12, 0), calendar: calendar)
        XCTAssertEqual(month.label, "2026-09")

        let year = ArchiveService.lastCompletedPeriod(.year, now: date(2027, 1, 1, 0, 0), calendar: calendar)
        XCTAssertEqual(year.label, "2026")
    }

    func testFirstEnableArchivesOnlyTheLastCompletedPeriod() {
        let periods = ArchiveService.periodsToArchive(
            .month,
            after: nil,
            now: date(2026, 10, 29, 12, 0),
            limit: 12,
            calendar: calendar
        )

        XCTAssertEqual(periods.map(\.label), ["2026-09"])
    }

    func testMissedPeriodsAreFilledInOrder() {
        let periods = ArchiveService.periodsToArchive(
            .month,
            after: "2026-05",
            now: date(2026, 10, 29, 12, 0),
            limit: 12,
            calendar: calendar
        )

        XCTAssertEqual(periods.map(\.label), ["2026-06", "2026-07", "2026-08", "2026-09"])
    }

    func testMissedPeriodsAreCappedToTheNewest() {
        let periods = ArchiveService.periodsToArchive(
            .month,
            after: "2025-01",
            now: date(2026, 10, 29, 12, 0),
            limit: 2,
            calendar: calendar
        )

        XCTAssertEqual(periods.map(\.label), ["2026-08", "2026-09"])
    }

    func testCompletePeriodNeedsNoArchive() {
        let periods = ArchiveService.periodsToArchive(
            .month,
            after: "2026-09",
            now: date(2026, 10, 29, 12, 0),
            limit: 12,
            calendar: calendar
        )

        XCTAssertTrue(periods.isEmpty)
    }

    // MARK: - Archive contents

    func testArchiveMaterializesRecurringOccurrences() {
        let entry = Entry(
            title: "Dailies",
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: date(2026, 9, 1, 8, 0),
            isCompletable: true,
            eventTypeRaw: GameEventType.dailies.rawValue
        )
        entry.recurrence = RecurrenceRule(frequency: .daily)
        context.insert(entry)

        let period = ArchiveService.period(.month, containing: date(2026, 9, 15, 12, 0), calendar: calendar)
        let document = ArchiveService.makeDocument(
            entries: [entry],
            kind: .month,
            period: period,
            now: date(2026, 10, 1, 20, 0),
            calendar: calendar
        )

        XCTAssertEqual(document.entries.count, 30)
        XCTAssertEqual(document.label, "2026-09")
        XCTAssertEqual(document.periodStart, "2026-09-01")
        XCTAssertEqual(document.periodEnd, "2026-09-30")
        XCTAssertEqual(document.entries.first?.date, "2026-09-01")
        XCTAssertEqual(document.entries.last?.date, "2026-09-30")
        XCTAssertEqual(document.totals.byGame["Genshin Impact"], 30)
        XCTAssertEqual(document.totals.byCategory["Games"], 30)
        XCTAssertEqual(document.totals.events, 30)
        XCTAssertEqual(document.totals.completed, 0)
        XCTAssertEqual(document.entries.first?.eventType, "Dailies")
        XCTAssertFalse(document.entries.first?.completed ?? true)
    }

    func testArchiveRecordsCompletionExpensesAndBalances() throws {
        let entry = Entry(
            title: "Dinner",
            category: .irl,
            startDate: date(2026, 9, 10, 19, 0),
            isCompletable: true,
            trackExpense: true
        )
        entry.expenseLines = [
            ExpenseLine(title: "Food", amount: 40),
            ExpenseLine(title: "Taxi", amount: 10),
        ]
        entry.expenseBalances = [ExpenseBalance(personName: "Ravi", amount: 25)]
        entry.completions = [EntryCompletion(occurrenceStart: date(2026, 9, 10, 19, 0))]
        context.insert(entry)

        let period = ArchiveService.period(.month, containing: date(2026, 9, 15, 12, 0), calendar: calendar)
        let document = ArchiveService.makeDocument(
            entries: [entry],
            kind: .month,
            period: period,
            calendar: calendar
        )

        let row = try XCTUnwrap(document.entries.first)
        XCTAssertEqual(row.title, "Dinner")
        XCTAssertEqual(row.completed, true)
        XCTAssertEqual(row.expenseTotal, 50)
        XCTAssertEqual(row.expenseLines?.count, 2)
        XCTAssertEqual(row.owedToYou, 25)
        XCTAssertEqual(row.balances?.first?.person, "Ravi")

        XCTAssertEqual(document.totals.completed, 1)
        XCTAssertEqual(document.totals.expenseTotal, 50)
        XCTAssertEqual(document.totals.owedToYou, 25)
    }

    func testArchiveOnlyIncludesEntriesInsideThePeriod() {
        let inside = Entry(title: "Inside", category: .irl, startDate: date(2026, 9, 30, 23, 0))
        let after = Entry(title: "After", category: .irl, startDate: date(2026, 10, 1, 0, 30))
        let before = Entry(title: "Before", category: .irl, startDate: date(2026, 8, 31, 23, 30))
        [inside, after, before].forEach(context.insert)

        let period = ArchiveService.period(.month, containing: date(2026, 9, 15, 12, 0), calendar: calendar)
        let document = ArchiveService.makeDocument(
            entries: [inside, after, before],
            kind: .month,
            period: period,
            calendar: calendar
        )

        XCTAssertEqual(document.entries.map(\.title), ["Inside"])
    }

    func testArchiveIsNotDecodableAsBackupAndViceVersa() throws {
        let period = ArchiveService.period(.month, containing: date(2026, 9, 15, 12, 0), calendar: calendar)
        let archiveData = try ArchiveService.exportData(entries: [], kind: .month, period: period, calendar: calendar)
        XCTAssertThrowsError(try BackupService.decode(archiveData))

        let backupData = try BackupService.exportData(entries: [], pityTrackers: [])
        XCTAssertThrowsError(try ArchiveService.decode(backupData))
    }

    func testArchiveRoundTripsAndUsesDistinctFormat() throws {
        let period = ArchiveService.period(.year, containing: date(2026, 7, 4, 12, 0), calendar: calendar)
        let data = try ArchiveService.exportData(entries: [], kind: .year, period: period, calendar: calendar)
        let document = try ArchiveService.decode(data)

        XCTAssertEqual(document.format, "lifeos.recap")
        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.kind, "year")
        XCTAssertEqual(document.label, "2026")
        XCTAssertEqual(document.periodStart, "2026-01-01")
        XCTAssertEqual(document.periodEnd, "2026-12-31")
        XCTAssertEqual(
            ArchiveService.fileName(kind: .year, period: period),
            "LifeOS-Year-2026.json"
        )
        XCTAssertEqual(
            ArchiveService.fileName(kind: .month, period: ArchiveService.period(.month, containing: date(2026, 9, 2, 12, 0), calendar: calendar)),
            "LifeOS-Month-2026-09.json"
        )
    }

    // MARK: - Archive scheduling

    func testMonthlyArchiveIsDueAfterItsSlot() throws {
        setSlot(weekday: 1, hour: 20, minute: 0)
        UserDefaults.standard.set(true, forKey: AutomaticBackup.monthlyEnabledKey)

        let august = ArchiveService.period(.month, containing: date(2026, 8, 10, 12, 0), calendar: calendar)
        try AutomaticBackup.archiveNow(
            .month,
            modelContext: context,
            period: august,
            now: date(2026, 9, 1, 20, 5),
            calendar: calendar
        )

        // October's slot (1 Oct, 20:00) has passed and September is still owed.
        XCTAssertTrue(AutomaticBackup.isArchiveDue(.month, now: date(2026, 10, 29, 12, 0), calendar: calendar))

        let september = ArchiveService.lastCompletedPeriod(.month, now: date(2026, 10, 29, 12, 0), calendar: calendar)
        try AutomaticBackup.archiveNow(
            .month,
            modelContext: context,
            period: september,
            now: date(2026, 10, 29, 12, 0),
            calendar: calendar
        )

        XCTAssertFalse(AutomaticBackup.isArchiveDue(.month, now: date(2026, 10, 29, 12, 1), calendar: calendar))
        XCTAssertEqual(AutomaticBackup.lastArchiveLabel(.month), "2026-09")
    }

    func testMonthlyArchiveWaitsForItsSlotOnTheFirstOfTheMonth() {
        setSlot(weekday: 1, hour: 20, minute: 0)
        UserDefaults.standard.set(true, forKey: AutomaticBackup.monthlyEnabledKey)

        // 1 October, 09:00 — the 20:00 slot has not arrived yet.
        XCTAssertFalse(AutomaticBackup.isArchiveDue(.month, now: date(2026, 10, 1, 9, 0), calendar: calendar))
        XCTAssertTrue(AutomaticBackup.isArchiveDue(.month, now: date(2026, 10, 1, 20, 1), calendar: calendar))
    }

    func testDisabledArchiveIsNeverDue() {
        setSlot(weekday: 1, hour: 20, minute: 0)
        UserDefaults.standard.set(false, forKey: AutomaticBackup.monthlyEnabledKey)

        XCTAssertFalse(AutomaticBackup.isArchiveDue(.month, now: date(2026, 10, 29, 12, 0), calendar: calendar))
    }

    func testArchiveNowWritesFileAndAdvancesState() throws {
        setSlot(weekday: 1, hour: 20, minute: 0)
        UserDefaults.standard.set(true, forKey: AutomaticBackup.monthlyEnabledKey)

        let period = ArchiveService.period(.month, containing: date(2026, 9, 10, 12, 0), calendar: calendar)
        let now = date(2026, 10, 1, 20, 5)
        let record = try AutomaticBackup.archiveNow(
            .month,
            modelContext: context,
            period: period,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(record.url.lastPathComponent, "LifeOS-Month-2026-09.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.url.path))
        XCTAssertEqual(AutomaticBackup.lastArchiveLabel(.month), "2026-09")
        XCTAssertEqual(AutomaticBackup.lastArchiveAt(.month), now)
        XCTAssertNil(AutomaticBackup.lastArchiveErrorMessage(.month))
    }

    func testArchiveIncludesProgressAndGameSessionDetails() throws {
        let anime = Entry(
            title: "Frieren",
            category: .entertainment,
            subCategory: EntertainmentSubCategory.anime.rawValue,
            startDate: date(2026, 9, 5, 21, 0)
        )
        anime.progress = EntryProgress(currentUnit: 12, totalUnits: 28, unitLabel: "episode", targetUnitsPerSession: 2)

        let game = Entry(
            title: "Spiral Abyss",
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: date(2026, 9, 6, 18, 0),
            eventTypeRaw: GameEventType.endgameContent.rawValue,
            plannedActivity: "Floor 12",
            playedWithRaw: "Ravi\nMeera"
        )
        [anime, game].forEach(context.insert)

        let period = ArchiveService.period(.month, containing: date(2026, 9, 15, 12, 0), calendar: calendar)
        let document = ArchiveService.makeDocument(
            entries: [anime, game],
            kind: .month,
            period: period,
            calendar: calendar
        )

        let animeRow = try XCTUnwrap(document.entries.first { $0.title == "Frieren" })
        XCTAssertEqual(animeRow.progress?.current, 12)
        XCTAssertEqual(animeRow.progress?.total, 28)
        XCTAssertEqual(animeRow.progress?.unit, "episode")
        XCTAssertEqual(animeRow.progress?.targetPerSession, 2)
        XCTAssertEqual(animeRow.subCategory, "Anime")

        let gameRow = try XCTUnwrap(document.entries.first { $0.title == "Spiral Abyss" })
        XCTAssertEqual(gameRow.eventType, "Endgame Content")
        XCTAssertEqual(gameRow.plannedActivity, "Floor 12")
        XCTAssertEqual(gameRow.playedWith, ["Ravi", "Meera"])
    }

    // MARK: - Legacy backups

    func testBackupsWithRemovedPityDropFieldsStillDecode() throws {
        let tracker = PityTracker(
            game: .genshinImpact,
            name: "Character",
            hardPity: 90,
            guaranteeKind: .fiftyFifty
        )
        context.insert(tracker)

        let data = try BackupService.exportData(entries: [], pityTrackers: [tracker])
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var trackers = try XCTUnwrap(root["pityTrackers"] as? [[String: Any]])
        trackers[0]["lastDropName"] = "Furina"
        trackers[0]["lastDropPity"] = 74
        trackers[0]["lastDropAt"] = "2026-10-01T12:00:00Z"
        trackers[0]["lastDropWasFeatured"] = true
        root["pityTrackers"] = trackers

        let legacy = try JSONSerialization.data(withJSONObject: root)
        let document = try BackupService.decode(legacy)

        XCTAssertEqual(document.version, BackupService.currentVersion)
        XCTAssertEqual(document.pityTrackers?.count, 1)
    }

    // MARK: - Helpers

    private func setSlot(weekday: Int, hour: Int, minute: Int) {
        UserDefaults.standard.set(weekday, forKey: AutomaticBackup.weekdayKey)
        UserDefaults.standard.set(hour, forKey: AutomaticBackup.hourKey)
        UserDefaults.standard.set(minute, forKey: AutomaticBackup.minuteKey)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }
}
