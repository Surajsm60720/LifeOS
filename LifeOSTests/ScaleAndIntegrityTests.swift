import XCTest
import SwiftData
@testable import LifeOS

/// Scale + data-integrity harness used to qualify the store for v1.0.
///
/// These cover the "can LifeOS survive years of heavy use, and can I always get my
/// data back" questions: bulk insert/fetch cost, recurrence expansion cost at range,
/// full backup round-trip fidelity, and malformed-input handling.
@MainActor
final class ScaleAndIntegrityTests: XCTestCase {
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

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        return calendar.date(from: c)!
    }

    /// Builds `days * perDay` entries spread across a year, with realistic children.
    @discardableResult
    private func seedEntries(days: Int, perDay: Int) -> [Entry] {
        let start = date(2026, 1, 1)
        var made: [Entry] = []
        made.reserveCapacity(days * perDay)

        for dayOffset in 0..<days {
            let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: start)!
            for slot in 0..<perDay {
                let when = calendar.date(byAdding: .hour, value: slot % 24, to: dayStart)!
                let category: EntryCategory = [.irl, .game, .entertainment][slot % 3]

                let entry = Entry(
                    title: "Event \(dayOffset)-\(slot)",
                    category: category,
                    subCategory: category == .game ? GameSubCategory.genshinImpact.rawValue
                        : (category == .entertainment ? EntertainmentSubCategory.anime.rawValue : nil),
                    startDate: when,
                    duration: 3600,
                    notes: "Auto-generated note for load testing entry \(dayOffset)-\(slot)",
                    isCompletable: slot % 2 == 0
                )

                // Attach children to a slice so the graph is realistic, not just flat rows.
                if slot % 5 == 0 {
                    let loc = LocationEntry(name: "Place \(slot)", latitude: 12.9, longitude: 77.5)
                    loc.entry = entry
                    entry.locations = [loc]
                    context.insert(loc)
                }
                if slot % 7 == 0 && category == .irl {
                    entry.trackExpense = true
                    let line = ExpenseLine(title: "Item \(slot)", amount: 250)
                    line.entry = entry
                    entry.expenseLines = [line]
                    context.insert(line)

                    let bal = ExpenseBalance(personName: "Friend \(slot)", amount: 125)
                    bal.entry = entry
                    entry.expenseBalances = [bal]
                    context.insert(bal)
                }
                if slot % 11 == 0 {
                    let comp = EntryCompletion(occurrenceStart: when, completedAt: when.addingTimeInterval(1800))
                    comp.entry = entry
                    entry.completions = [comp]
                    context.insert(comp)
                }

                context.insert(entry)
                made.append(entry)
            }
        }
        return made
    }

    // MARK: - A. Bulk write / read at 10k+

    func testInsertAndFetch10kEntries() throws {
        // 365 days x 28/day = 10,220 entries — beyond the user's stated worst case.
        let clockStart = Date()
        seedEntries(days: 365, perDay: 28)
        try context.save()
        let writeSeconds = Date().timeIntervalSince(clockStart)

        let fetchStart = Date()
        let all = try context.fetch(FetchDescriptor<Entry>())
        let fetchSeconds = Date().timeIntervalSince(fetchStart)

        XCTAssertEqual(all.count, 10_220)
        print("[SCALE] insert+save 10,220 entries: \(String(format: "%.2f", writeSeconds))s")
        print("[SCALE] fetch-all 10,220 entries:  \(String(format: "%.2f", fetchSeconds))s")

        // Generous ceilings; these are regression tripwires, not benchmarks.
        XCTAssertLessThan(writeSeconds, 60, "Bulk insert of 10k entries got pathologically slow")
        XCTAssertLessThan(fetchSeconds, 10, "Fetch-all of 10k entries got pathologically slow")
    }

    /// Ceiling probe: ~5 years of heavy use (50k entries). Not a normal-path test —
    /// it documents where the store starts to hurt.
    func testCeilingProbe50kEntries() throws {
        let insertStart = Date()
        seedEntries(days: 365 * 5, perDay: 28)
        try context.save()
        let insertSeconds = Date().timeIntervalSince(insertStart)

        let fetchStart = Date()
        let all = try context.fetch(FetchDescriptor<Entry>())
        let fetchSeconds = Date().timeIntervalSince(fetchStart)

        let exportStart = Date()
        let data = try BackupService.exportData(entries: all)
        let exportSeconds = Date().timeIntervalSince(exportStart)

        print("[CEILING] entries: \(all.count)")
        print("[CEILING] insert+save: \(String(format: "%.2f", insertSeconds))s")
        print("[CEILING] fetch-all:   \(String(format: "%.2f", fetchSeconds))s")
        print("[CEILING] backup JSON: \(String(format: "%.1f", Double(data.count) / 1_048_576.0)) MB in \(String(format: "%.2f", exportSeconds))s")

        XCTAssertEqual(all.count, 51_100)
    }

    /// A predicate-scoped fetch (one day out of a full year) should be far cheaper
    /// than pulling the whole table. This is the pattern calendar views should use.
    func testPredicateScopedFetchIsCheaperThanFullFetch() throws {
        seedEntries(days: 365, perDay: 28)
        try context.save()

        let dayStart = date(2026, 6, 15, hour: 0)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        var scoped = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.startDate >= dayStart && $0.startDate < dayEnd }
        )
        scoped.fetchLimit = 500

        let scopedStart = Date()
        let scopedResults = try context.fetch(scoped)
        let scopedSeconds = Date().timeIntervalSince(scopedStart)

        let fullStart = Date()
        let fullResults = try context.fetch(FetchDescriptor<Entry>())
        let fullSeconds = Date().timeIntervalSince(fullStart)

        print("[SCALE] scoped one-day fetch: \(scopedResults.count) rows in \(String(format: "%.4f", scopedSeconds))s")
        print("[SCALE] unscoped full fetch:  \(fullResults.count) rows in \(String(format: "%.4f", fullSeconds))s")

        XCTAssertEqual(scopedResults.count, 28)
        XCTAssertLessThan(scopedSeconds, fullSeconds, "Predicate pushdown gave no benefit — check store indexing")
    }

    // MARK: - B. Recurrence expansion cost

    func testRecurrenceExpansionIsBoundedByRequestedRange() throws {
        // 500 daily-recurring entries starting years before the queried window.
        let engine = RecurrenceEngine()
        var entries: [Entry] = []
        for i in 0..<500 {
            let e = Entry(title: "Daily \(i)", category: .irl, startDate: date(2020, 1, 1))
            e.recurrence = RecurrenceRule(frequency: .daily, interval: 1)
            e.recurrence?.entry = e
            entries.append(e)
        }

        // One day: 500 entries x 1 occurrence each.
        let dayInterval = DateInterval(start: date(2026, 6, 15, hour: 0), duration: 86_400)
        let dayStart = Date()
        let dayOccurrences = engine.expandEntries(entries, in: dayInterval, calendar: calendar)
        let daySeconds = Date().timeIntervalSince(dayStart)

        // One year: 500 entries x 365 occurrences = 182,500 objects.
        let yearInterval = DateInterval(start: date(2026, 1, 1, hour: 0), duration: 365 * 86_400)
        let yearStart = Date()
        let yearOccurrences = engine.expandEntries(entries, in: yearInterval, calendar: calendar)
        let yearSeconds = Date().timeIntervalSince(yearStart)

        print("[SCALE] day expansion:  \(dayOccurrences.count) occurrences in \(String(format: "%.4f", daySeconds))s")
        print("[SCALE] year expansion: \(yearOccurrences.count) occurrences in \(String(format: "%.3f", yearSeconds))s")

        XCTAssertEqual(dayOccurrences.count, 500, "Day expansion must not leak occurrences outside the range")
        XCTAssertLessThan(daySeconds, 1.0, "Single-day expansion should be trivially fast")
        XCTAssertLessThan(yearSeconds, 30, "Year expansion of daily recurrences is pathologically slow")
    }

    // MARK: - C. Backup round-trip fidelity (the reinstall scenario)

    func testFullBackupRoundTripPreservesEveryField() throws {
        let entry = Entry(
            title: "Kitchen Sink",
            category: .irl,
            subCategory: nil,
            startDate: date(2026, 7, 28, hour: 18),
            duration: 5400,
            location: "Legacy Location String",
            notes: "Multi\nline\tnotes with émoji 🎉 and \"quotes\"",
            isCompletable: true,
            colorOverrideHex: "FF8800",
            trackExpense: true,
            eventTypeRaw: nil,
            plannedActivity: "Dinner then walk",
            playedWithRaw: "Alex\nJordan"
        )
        entry.expenseCategory = "Food"

        let loc = LocationEntry(name: "Café ☕️", latitude: 12.971598, longitude: 77.594566)
        loc.entry = entry
        entry.locations = [loc]

        let line = ExpenseLine(title: "Pizza", amount: Decimal(string: "1234.56")!)
        line.entry = entry
        entry.expenseLines = [line]

        let bal = ExpenseBalance(personName: "Alex", amount: Decimal(string: "617.28")!)
        bal.entry = entry
        entry.expenseBalances = [bal]

        let rule = NotificationRule(
            triggerKind: .ifNotCompletedBy,
            triggerDate: date(2026, 7, 28, hour: 21),
            messageTemplate: "Still open: {title}",
            isActive: true
        )
        rule.entry = entry
        entry.notificationRules = [rule]

        let comp = EntryCompletion(
            occurrenceStart: date(2026, 7, 28, hour: 18),
            completedAt: date(2026, 7, 28, hour: 22)
        )
        comp.entry = entry
        entry.completions = [comp]

        context.insert(entry)
        try context.save()

        // Export -> wipe -> import, exactly like reinstalling the app.
        let data = try BackupService.exportData(entries: [entry])
        let document = try BackupService.decode(data)
        let summary = try BackupService.replace(
            document: document,
            modelContext: context,
            entryStore: EntryStore()
        )
        XCTAssertEqual(summary.inserted, 1)

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)

        XCTAssertEqual(restored.id, entry.id)
        XCTAssertEqual(restored.title, "Kitchen Sink")
        XCTAssertEqual(restored.categoryRaw, EntryCategory.irl.rawValue)
        XCTAssertEqual(restored.startDate, date(2026, 7, 28, hour: 18))
        XCTAssertEqual(restored.duration, 5400)
        XCTAssertEqual(restored.location, "Legacy Location String")
        XCTAssertEqual(restored.notes, "Multi\nline\tnotes with émoji 🎉 and \"quotes\"")
        XCTAssertTrue(restored.isCompletable)
        XCTAssertEqual(restored.colorOverrideHex, "FF8800")
        XCTAssertEqual(restored.expenseCategory, "Food")
        XCTAssertTrue(restored.trackExpense)
        XCTAssertEqual(restored.plannedActivity, "Dinner then walk")
        XCTAssertEqual(restored.playedWith, ["Alex", "Jordan"])

        XCTAssertEqual(restored.locations.count, 1)
        XCTAssertEqual(restored.locations.first?.name, "Café ☕️")
        XCTAssertEqual(restored.locations.first?.latitude ?? 0, 12.971598, accuracy: 0.000001)
        XCTAssertEqual(restored.locations.first?.longitude ?? 0, 77.594566, accuracy: 0.000001)

        XCTAssertEqual(restored.expenseLines.count, 1)
        XCTAssertEqual(restored.expenseLines.first?.amount, Decimal(string: "1234.56"))
        XCTAssertEqual(restored.expenseBalances.first?.amount, Decimal(string: "617.28"))

        XCTAssertEqual(restored.notificationRules.count, 1)
        XCTAssertEqual(restored.notificationRules.first?.ruleID, rule.ruleID)
        XCTAssertEqual(restored.notificationRules.first?.messageTemplate, "Still open: {title}")

        XCTAssertEqual(restored.completions.count, 1)
        XCTAssertEqual(restored.completions.first?.occurrenceStart, date(2026, 7, 28, hour: 18))
    }

    func testRecurrenceWeekdayMaskSurvivesRoundTrip() throws {
        let entry = Entry(title: "MonWedFri", category: .game, startDate: date(2026, 7, 1))
        entry.subCategory = GameSubCategory.genshinImpact.rawValue
        let rule = RecurrenceRule(
            frequency: .weekly,
            interval: 2,
            daysOfWeek: [.monday, .wednesday, .friday],
            occurrenceCount: 12
        )
        rule.entry = entry
        entry.recurrence = rule
        context.insert(entry)
        try context.save()

        let data = try BackupService.exportData(entries: [entry])
        let document = try BackupService.decode(data)
        _ = try BackupService.replace(document: document, modelContext: context, entryStore: EntryStore())

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)
        let rr = try XCTUnwrap(restored.recurrence)

        XCTAssertEqual(rr.frequency, .weekly)
        XCTAssertEqual(rr.interval, 2)
        XCTAssertEqual(rr.occurrenceCount, 12)
        XCTAssertEqual(Set(rr.daysOfWeek ?? []), Set([.monday, .wednesday, .friday]),
                       "Weekday mask was lost or corrupted across backup round-trip")
    }

    func testEntertainmentProgressSurvivesRoundTrip() throws {
        let entry = Entry(title: "Some Anime", category: .entertainment, startDate: date(2026, 7, 1))
        entry.subCategory = EntertainmentSubCategory.anime.rawValue
        let progress = EntryProgress(currentUnit: 7, totalUnits: 24, unitLabel: "episode", targetUnitsPerSession: 3)
        progress.entry = entry
        entry.progress = progress
        context.insert(entry)
        try context.save()

        let data = try BackupService.exportData(entries: [entry])
        let document = try BackupService.decode(data)
        _ = try BackupService.replace(document: document, modelContext: context, entryStore: EntryStore())

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)
        let p = try XCTUnwrap(restored.progress)
        XCTAssertEqual(p.currentUnit, 7)
        XCTAssertEqual(p.totalUnits, 24)
        XCTAssertEqual(p.unitLabel, "episode")
        XCTAssertEqual(p.targetUnitsPerSession, 3)
    }

    // MARK: - D. Backup at scale

    func testBackupRoundTripAt10kEntries() throws {
        seedEntries(days: 365, perDay: 28)
        try context.save()
        let originals = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(originals.count, 10_220)

        // Snapshot child counts *before* the wipe — reading relationships off
        // deleted models afterwards returns partial data.
        let expectedLocations = try context.fetch(FetchDescriptor<LocationEntry>()).count
        let expectedCompletions = try context.fetch(FetchDescriptor<EntryCompletion>()).count

        let exportStart = Date()
        let data = try BackupService.exportData(entries: originals)
        let exportSeconds = Date().timeIntervalSince(exportStart)

        let mb = Double(data.count) / 1_048_576.0
        print("[SCALE] backup JSON for 10,220 entries: \(String(format: "%.1f", mb)) MB in \(String(format: "%.2f", exportSeconds))s")

        let decodeStart = Date()
        let document = try BackupService.decode(data)
        let decodeSeconds = Date().timeIntervalSince(decodeStart)
        XCTAssertEqual(document.entries.count, 10_220)

        let importStart = Date()
        let summary = try BackupService.replace(
            document: document,
            modelContext: context,
            entryStore: EntryStore()
        )
        let importSeconds = Date().timeIntervalSince(importStart)

        print("[SCALE] decode: \(String(format: "%.2f", decodeSeconds))s, import: \(String(format: "%.2f", importSeconds))s")

        XCTAssertEqual(summary.inserted, 10_220)

        let restored = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(restored.count, 10_220, "Entry count drifted across a full backup/restore cycle")

        // Child rows must not be orphaned or duplicated by the wipe+restore.
        let locations = try context.fetch(FetchDescriptor<LocationEntry>())
        XCTAssertEqual(locations.count, expectedLocations, "Location rows leaked or were dropped during restore")

        let completions = try context.fetch(FetchDescriptor<EntryCompletion>())
        XCTAssertEqual(completions.count, expectedCompletions, "Completion rows leaked or were dropped during restore")

        XCTAssertLessThan(exportSeconds, 120, "Export of 10k entries is pathologically slow")
        XCTAssertLessThan(importSeconds, 120, "Import of 10k entries is pathologically slow")
    }

    /// Re-importing the same file in Merge mode must be idempotent, not additive.
    func testRepeatedMergeIsIdempotent() throws {
        seedEntries(days: 10, perDay: 5)
        try context.save()
        let originals = try context.fetch(FetchDescriptor<Entry>())
        let baselineCount = originals.count
        let expectedLines = try context.fetch(FetchDescriptor<ExpenseLine>()).count
        let expectedCompletions = try context.fetch(FetchDescriptor<EntryCompletion>()).count

        let data = try BackupService.exportData(entries: originals)
        let document = try BackupService.decode(data)

        _ = try BackupService.merge(document: document, modelContext: context)
        _ = try BackupService.merge(document: document, modelContext: context)
        _ = try BackupService.merge(document: document, modelContext: context)

        let after = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(after.count, baselineCount, "Merging the same backup repeatedly duplicated entries")

        let lines = try context.fetch(FetchDescriptor<ExpenseLine>())
        XCTAssertEqual(lines.count, expectedLines, "Repeated merge duplicated expense line child rows")

        let completions = try context.fetch(FetchDescriptor<EntryCompletion>())
        XCTAssertEqual(completions.count, expectedCompletions, "Repeated merge duplicated completion rows")
    }

    // MARK: - E. Cascade delete hygiene

    func testDeletingEntryCascadesToAllChildren() throws {
        let entry = Entry(title: "Doomed", category: .irl, startDate: date(2026, 7, 1), trackExpense: true)
        let loc = LocationEntry(name: "Somewhere"); loc.entry = entry; entry.locations = [loc]
        let line = ExpenseLine(title: "Thing", amount: 10); line.entry = entry; entry.expenseLines = [line]
        let bal = ExpenseBalance(personName: "X", amount: 5); bal.entry = entry; entry.expenseBalances = [bal]
        let rule = NotificationRule(triggerKind: .fixedTime, triggerDate: date(2026, 7, 1), messageTemplate: "hi")
        rule.entry = entry; entry.notificationRules = [rule]
        let comp = EntryCompletion(occurrenceStart: date(2026, 7, 1), completedAt: date(2026, 7, 1))
        comp.entry = entry; entry.completions = [comp]

        context.insert(entry)
        context.insert(loc)
        context.insert(line)
        context.insert(bal)
        context.insert(rule)
        context.insert(comp)
        try context.save()

        context.delete(entry)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocationEntry>()).count, 0, "Orphaned LocationEntry rows survive entry deletion")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExpenseLine>()).count, 0, "Orphaned ExpenseLine rows survive entry deletion")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExpenseBalance>()).count, 0, "Orphaned ExpenseBalance rows survive entry deletion")
        XCTAssertEqual(try context.fetch(FetchDescriptor<NotificationRule>()).count, 0, "Orphaned NotificationRule rows survive entry deletion")
        XCTAssertEqual(try context.fetch(FetchDescriptor<EntryCompletion>()).count, 0, "Orphaned EntryCompletion rows survive entry deletion")
    }

    // MARK: - F. Malformed / hostile input

    func testMalformedBackupsFailGracefullyWithoutCrashing() {
        let cases: [(String, Data)] = [
            ("empty data", Data()),
            ("not json", Data("this is not json at all".utf8)),
            ("truncated json", Data(#"{"format":"lifeos.backup","version":1,"entr"#.utf8)),
            ("wrong format id", Data(#"{"format":"nope","version":1,"exportedAt":"2026-07-28T00:00:00Z","preferences":{},"entries":[]}"#.utf8)),
            ("future version", Data(#"{"format":"lifeos.backup","version":99,"exportedAt":"2026-07-28T00:00:00Z","preferences":{},"entries":[]}"#.utf8)),
            ("missing entries key", Data(#"{"format":"lifeos.backup","version":1,"exportedAt":"2026-07-28T00:00:00Z","preferences":{}}"#.utf8)),
            ("entries wrong type", Data(#"{"format":"lifeos.backup","version":1,"exportedAt":"2026-07-28T00:00:00Z","preferences":{},"entries":"nope"}"#.utf8)),
            ("null bytes", Data([0x00, 0x01, 0x02, 0xFF, 0xFE])),
        ]

        for (label, data) in cases {
            XCTAssertThrowsError(try BackupService.decode(data), "\(label) should throw, not crash or silently succeed")
        }
    }

    func testEmptyBackupIsValidAndWipesCleanly() throws {
        seedEntries(days: 2, perDay: 2)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).count, 4)

        let emptyDoc = BackupService.makeDocument(entries: [])
        let data = try BackupService.encode(emptyDoc)
        let decoded = try BackupService.decode(data)
        let summary = try BackupService.replace(document: decoded, modelContext: context, entryStore: EntryStore())

        XCTAssertEqual(summary.inserted, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).count, 0)
    }

    func testUnknownEnumRawValuesDegradeToDefaultsInsteadOfCrashing() throws {
        let json = """
        {
          "format": "lifeos.backup",
          "version": 1,
          "exportedAt": "2026-07-28T00:00:00Z",
          "preferences": {},
          "entries": [{
            "id": "\(UUID().uuidString)",
            "title": "Weird",
            "categoryRaw": "notARealCategory",
            "startDate": "2026-07-28T10:00:00Z",
            "isCompletable": false,
            "trackExpense": false,
            "playedWithRaw": "",
            "locations": [], "expenseLines": [], "expenseBalances": [],
            "notificationRules": [], "completions": [],
            "recurrence": { "frequencyRaw": "notAFrequency", "interval": 1 }
          }]
        }
        """
        let document = try BackupService.decode(Data(json.utf8))
        let summary = try BackupService.replace(document: document, modelContext: context, entryStore: EntryStore())
        XCTAssertEqual(summary.inserted, 1)

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(restored.category, .irl, "Unknown category should fall back to .irl")
        XCTAssertEqual(restored.recurrence?.frequency, .daily, "Unknown frequency should fall back to .daily")
    }

    // MARK: - G. Date / boundary edge cases

    func testExtremeAndBoundaryValuesRoundTrip() throws {
        let longTitle = String(repeating: "A", count: 10_000)
        let entry = Entry(
            title: longTitle,
            category: .irl,
            startDate: date(2026, 12, 31, hour: 23),
            duration: TimeInterval(23 * 3600 + 59 * 60),
            notes: String(repeating: "note ", count: 20_000),
            isCompletable: true
        )
        context.insert(entry)
        try context.save()

        let data = try BackupService.exportData(entries: [entry])
        let document = try BackupService.decode(data)
        _ = try BackupService.replace(document: document, modelContext: context, entryStore: EntryStore())

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(restored.title.count, 10_000)
        XCTAssertEqual(restored.notes?.count, 100_000)
        XCTAssertEqual(restored.duration, TimeInterval(23 * 3600 + 59 * 60))
    }

    func testLeapDayAndDSTBoundaryRecurrence() throws {
        // Leap day: monthly from Jan 31 must clamp into Feb of a leap year.
        let engine = RecurrenceEngine()
        let leap = Entry(title: "Leap", category: .irl, startDate: date(2028, 1, 31))
        leap.recurrence = RecurrenceRule(frequency: .monthly, interval: 1)

        let results = engine.occurrences(
            for: leap,
            in: date(2028, 1, 1)...date(2028, 3, 31, hour: 23),
            calendar: calendar
        )
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(calendar.component(.day, from: results[1]), 29, "Feb 2028 is a leap year; expected clamp to 29")

        // DST: expand across a US spring-forward boundary in a DST-observing zone.
        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var c = DateComponents(); c.year = 2026; c.month = 3; c.day = 6; c.hour = 9
        let dstEntry = Entry(title: "DST", category: .irl, startDate: dstCalendar.date(from: c)!)
        dstEntry.recurrence = RecurrenceRule(frequency: .daily, interval: 1)

        var endC = DateComponents(); endC.year = 2026; endC.month = 3; endC.day = 12; endC.hour = 23
        let dstResults = engine.occurrences(
            for: dstEntry,
            in: dstCalendar.date(from: c)!...dstCalendar.date(from: endC)!,
            calendar: dstCalendar
        )
        XCTAssertEqual(dstResults.count, 7, "Daily recurrence dropped or duplicated a day across the DST transition")
        for occurrence in dstResults {
            XCTAssertEqual(dstCalendar.component(.hour, from: occurrence), 9,
                           "Local wall-clock hour drifted across the DST boundary")
        }
    }
}
