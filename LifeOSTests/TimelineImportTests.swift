import XCTest
import SwiftData
@testable import LifeOS

@MainActor
final class TimelineImportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let now = TimelineImportTests.date(2026, 10, 25, 12, 0)

    override func setUp() {
        super.setUp()

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: LifeOSSharedStore.schema, configurations: [config])
        context = ModelContext(container)

        for game in GameSubCategory.gachaGames {
            GameServerSettings.resetCustomBannerSwitch(for: game)
            GameServerSettings.resetCustomReset(for: game)
            UserDefaults.standard.removeObject(forKey: "lifeos.gameServer.\(game.rawValue)")
        }
    }

    override func tearDown() {
        for game in GameSubCategory.gachaGames {
            GameServerSettings.resetCustomBannerSwitch(for: game)
            GameServerSettings.resetCustomReset(for: game)
            UserDefaults.standard.removeObject(forKey: "lifeos.gameServer.\(game.rawValue)")
        }
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Date resolution

    func testDateOnlyWindowIsInclusiveAndAllDay() throws {
        let draft = try buildDraft("""
        {
          "id": "genshin-6.1-astral-accord",
          "kind": "event",
          "title": "Astral Accord",
          "start": "2026-10-29",
          "end": "2026-11-11"
        }
        """)

        let item = try XCTUnwrap(draft.items.first)
        XCTAssertTrue(item.isAllDay)
        XCTAssertEqual(item.duration, 14 * 86_400)

        let components = Calendar.current.dateComponents([.year, .month, .day], from: item.startDate)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 29)
    }

    func testSingleDayAllDayItemHasNoDuration() throws {
        let draft = try buildDraft("""
        {
          "id": "genshin-6.1-milestone",
          "kind": "event",
          "title": "Milestone",
          "start": "2026-10-29"
        }
        """)

        let item = try XCTUnwrap(draft.items.first)
        XCTAssertTrue(item.isAllDay)
        XCTAssertNil(item.duration)
    }

    func testBannerPhaseOneStartsAtPatchLiveAndPhaseTwoAtSwitchHour() throws {
        GameServerSettings.setServer(.america, for: .genshinImpact)

        let draft = try buildDraft("""
        {
          "id": "genshin-6.1-phase-1",
          "kind": "banner",
          "title": "Phase 1",
          "start": "2026-10-29",
          "end": "2026-11-18",
          "phase": 1
        },
        {
          "id": "genshin-6.1-phase-2",
          "kind": "banner",
          "title": "Phase 2",
          "start": "2026-11-18",
          "end": "2026-12-09",
          "phase": 2
        }
        """)

        let serverCalendar = GameServerSettings.calendar(for: .genshinImpact)
        let phaseOne = try XCTUnwrap(draft.items.first { $0.title == "Phase 1" })
        let phaseTwo = try XCTUnwrap(draft.items.first { $0.title == "Phase 2" })

        XCTAssertFalse(phaseOne.isAllDay)
        XCTAssertEqual(serverCalendar.component(.hour, from: phaseOne.startDate), 11)
        XCTAssertEqual(serverCalendar.component(.minute, from: phaseOne.startDate), 0)

        XCTAssertFalse(phaseTwo.isAllDay)
        XCTAssertEqual(serverCalendar.component(.hour, from: phaseTwo.startDate), 18)
        XCTAssertEqual(serverCalendar.component(.minute, from: phaseTwo.startDate), 0)
        XCTAssertEqual(serverCalendar.component(.day, from: phaseTwo.startDate), 18)
    }

    func testServerClocksAreFixedOffsetsWithoutDaylightSaving() throws {
        GameServerSettings.setServer(.america, for: .genshinImpact)
        XCTAssertEqual(GameServer.america.timeZone.secondsFromGMT(), -5 * 3_600)

        let summer = try buildDraft("""
        {
          "id": "genshin-5.8-summer",
          "kind": "banner",
          "title": "Summer Window",
          "start": "2026-07-01 18:00",
          "end": "2026-07-08 18:00"
        }
        """)

        let winter = try buildDraft("""
        {
          "id": "genshin-6.4-winter",
          "kind": "banner",
          "title": "Winter Window",
          "start": "2027-01-01 18:00",
          "end": "2027-01-08 18:00"
        }
        """)

        XCTAssertEqual(summer.items.first?.duration, 7 * 86_400)
        XCTAssertEqual(winter.items.first?.duration, 7 * 86_400)
    }

    func testGenshinAmericaResetIsTwoThirtyISTAllYear() throws {
        GameServerSettings.setServer(.america, for: .genshinImpact)
        let serverCalendar = GameServerSettings.calendar(for: .genshinImpact)

        var ist = Calendar(identifier: .gregorian)
        ist.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        for (month, label) in [(1, "winter"), (7, "summer")] {
            let reset = try XCTUnwrap(
                serverCalendar.date(from: DateComponents(year: 2026, month: month, day: 15, hour: 4))
            )
            XCTAssertEqual(ist.component(.hour, from: reset), 14, label)
            XCTAssertEqual(ist.component(.minute, from: reset), 30, label)
        }
    }

    func testLocalPickerRoundTripsAmericaResetAsTwoThirtyIST() throws {
        GameServerSettings.setServer(.america, for: .genshinImpact)

        var ist = Calendar(identifier: .gregorian)
        ist.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        let reference = try XCTUnwrap(
            ist.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))
        )
        let pickerDate = GameServerSettings.dateForLocalPicker(
            minutes: 4 * 60,
            game: .genshinImpact,
            reference: reference
        )

        XCTAssertEqual(ist.component(.hour, from: pickerDate), 14)
        XCTAssertEqual(ist.component(.minute, from: pickerDate), 30)

        // Dialing 2:30 PM IST must persist as 04:00 on the America server clock.
        let adjusted = try XCTUnwrap(
            ist.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 14, minute: 30))
        )
        XCTAssertEqual(
            GameServerSettings.minutesFromLocalPicker(date: adjusted, game: .genshinImpact),
            4 * 60
        )

        // A one-hour local correction (the old 1:30 PM mistake) stores as 03:00 server.
        let oneThirty = try XCTUnwrap(
            ist.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 13, minute: 30))
        )
        XCTAssertEqual(
            GameServerSettings.minutesFromLocalPicker(date: oneThirty, game: .genshinImpact),
            3 * 60
        )
    }

    func testExplicitTimesOverrideServerDefaults() throws {
        GameServerSettings.setServer(.asia, for: .honkaiStarRail)

        let draft = try buildDraft("""
        {
          "id": "hsr-3.7-event",
          "kind": "event",
          "title": "Timed Event",
          "start": "2026-11-18 04:00",
          "end": "2026-11-20 03:59"
        }
        """, game: "Honkai Star Rail")

        let serverCalendar = GameServerSettings.calendar(for: .honkaiStarRail)
        let item = try XCTUnwrap(draft.items.first)
        XCTAssertFalse(item.isAllDay)
        XCTAssertEqual(serverCalendar.component(.hour, from: item.startDate), 4)
        XCTAssertEqual(item.duration, 2 * 86_400 - 60)
    }

    // MARK: - Parsing

    func testDecodeToleratesFencesProseAndOffsets() throws {
        let text = """
        Here is the file you asked for:
        ```json
        {
          "format": "lifeos.timeline",
          "version": 1,
          "game": "Wuthering Waves",
          "items": [
            {
              "id": "wuwa-2.7-event",
              "kind": "event",
              "title": "Fenced Event",
              "start": "2026-11-18T10:00:00+08:00",
              "end": "2026-11-20T03:59:00Z"
            }
          ]
        }
        ```
        """

        let draft = try TimelineImportService.buildDraft(
            TimelineImportService.decode(Data(text.utf8)),
            now: now
        )

        let item = try XCTUnwrap(draft.items.first)
        let serverCalendar = GameServerSettings.calendar(for: .wutheringWaves)
        XCTAssertEqual(serverCalendar.component(.hour, from: item.startDate), 10)
        XCTAssertEqual(serverCalendar.component(.hour, from: item.endDate(calendar: serverCalendar) ?? .distantPast), 3)
    }

    func testUnknownKindsAreSkipped() throws {
        let draft = try buildDraft("""
        {
          "id": "genshin-6.1-patch",
          "kind": "patch",
          "title": "Version 6.1",
          "start": "2026-10-29",
          "end": "2026-12-09"
        },
        {
          "id": "genshin-6.1-event",
          "kind": "event",
          "title": "Kept",
          "start": "2026-10-29",
          "end": "2026-11-11"
        }
        """)

        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items.first?.title, "Kept")
        XCTAssertEqual(draft.skippedKinds, 1)
    }

    func testDuplicateIdsAreSkipped() throws {
        let draft = try buildDraft("""
        {
          "id": "dup",
          "kind": "event",
          "title": "First",
          "start": "2026-10-29",
          "end": "2026-11-01"
        },
        {
          "id": "dup",
          "kind": "event",
          "title": "Second",
          "start": "2026-11-02",
          "end": "2026-11-05"
        }
        """)

        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items.first?.title, "First")
        XCTAssertTrue(draft.warnings.contains { $0.contains("repeats an id") })
    }

    func testYearBehindIsCorrected() throws {
        let draft = try buildDraft("""
        {
          "id": "genshin-6.1-last-year",
          "kind": "event",
          "title": "Last Year",
          "start": "2025-10-29",
          "end": "2025-11-11"
        }
        """)

        let item = try XCTUnwrap(draft.items.first)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: item.startDate)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(draft.correctedYears, 2)
        XCTAssertTrue(draft.warnings.contains { $0.contains("Corrected the year") })
    }

    func testEndBeforeStartIsRejected() throws {
        XCTAssertThrowsError(
            try buildDraft("""
            {
              "id": "genshin-6.1-backwards",
              "kind": "event",
              "title": "Backwards",
              "start": "2026-11-11",
              "end": "2026-10-29"
            }
            """)
        )
    }

    // MARK: - Planning and upsert

    func testReimportUpdatesRowsAndPreservesEdits() throws {
        let first = try prepare("""
        {
          "id": "genshin-6.1-astral-accord",
          "kind": "event",
          "title": "Astral Accord",
          "start": "2026-10-29",
          "end": "2026-11-11"
        }
        """)

        XCTAssertEqual(first.createCount, 1)
        XCTAssertEqual(try TimelineImportService.apply(first, modelContext: context).created, 1)

        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)
        entry.notes = "My own note"
        try context.save()

        let second = try prepare("""
        {
          "id": "genshin-6.1-astral-accord",
          "kind": "event",
          "title": "Astral Accord (Revised)",
          "start": "2026-10-30",
          "end": "2026-11-12"
        }
        """)

        XCTAssertEqual(second.createCount, 0)
        XCTAssertEqual(second.updateCount, 1)
        let result = try TimelineImportService.apply(second, modelContext: context)
        XCTAssertEqual(result.updated, 1)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.count, 1)
        let updated = try XCTUnwrap(entries.first)
        XCTAssertEqual(updated.title, "Astral Accord (Revised)")
        XCTAssertEqual(updated.notes, "My own note")
        XCTAssertEqual(updated.duration, 14 * 86_400)
        XCTAssertEqual(
            Calendar.current.component(.day, from: updated.startDate),
            30
        )
    }

    func testManualEntryWithSameTitleAndDayIsSkipped() throws {
        let manualStart = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 29))
        )
        let manual = Entry(
            title: "Astral Accord",
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: manualStart,
            isAllDay: true
        )
        context.insert(manual)
        try context.save()

        let plan = try prepare("""
        {
          "id": "genshin-6.1-astral-accord",
          "kind": "event",
          "title": "Astral Accord",
          "start": "2026-10-29",
          "end": "2026-11-11"
        }
        """)

        XCTAssertEqual(plan.createCount, 0)
        XCTAssertEqual(plan.conflicts, ["Astral Accord"])
        XCTAssertTrue(plan.warnings.contains { $0.contains("already added by hand") })
    }

    func testRemovingAnImportDeletesOnlyItsEntries() throws {
        let plan = try prepare("""
        {
          "id": "genshin-6.1-astral-accord",
          "kind": "event",
          "title": "Astral Accord",
          "start": "2026-10-29",
          "end": "2026-11-11"
        }
        """)
        _ = try TimelineImportService.apply(plan, modelContext: context)

        let unrelated = Entry(title: "Dentist", category: .irl, startDate: now)
        context.insert(unrelated)
        try context.save()

        let removed = try TimelineImportService.removeImport(
            source: plan.draft.source,
            modelContext: context
        )
        XCTAssertEqual(removed, 1)

        let remaining = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.title, "Dentist")
    }

    func testImportGroupsListSources() throws {
        let plan = try prepare("""
        {
          "id": "genshin-6.1-astral-accord",
          "kind": "event",
          "title": "Astral Accord",
          "start": "2026-10-29",
          "end": "2026-11-11"
        }
        """)
        _ = try TimelineImportService.apply(plan, modelContext: context)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        let groups = TimelineImportService.importGroups(from: entries)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.source, "Genshin Impact 6.1")
        XCTAssertEqual(groups.first?.count, 1)
    }

    func testGenshinFixedEndgameRowsAreSkipped() throws {
        let draft = try buildDraft("""
        {
          "id": "genshin-6.1-spiral-abyss",
          "kind": "endgame",
          "title": "Spiral Abyss — Cycle 1",
          "start": "2026-11-01",
          "end": "2026-11-15"
        },
        {
          "id": "genshin-6.1-theater",
          "kind": "endgame",
          "title": "Imaginarium Theater",
          "start": "2026-11-01",
          "end": "2026-11-30"
        },
        {
          "id": "genshin-6.1-astral-accord",
          "kind": "event",
          "title": "Astral Accord",
          "start": "2026-10-29",
          "end": "2026-11-11"
        }
        """)

        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items.first?.title, "Astral Accord")
        XCTAssertTrue(draft.warnings.contains { $0.contains("recurring entries") })
    }

    func testStarRailEndgameRowsAreStillImported() throws {
        let draft = try buildDraft("""
        {
          "id": "hsr-3.7-moc",
          "kind": "endgame",
          "title": "Memory of Chaos",
          "start": "2026-11-01",
          "end": "2026-11-15"
        }
        """, game: "Honkai Star Rail")

        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items.first?.title, "Memory of Chaos")
    }

    func testGenshinFileWithOnlyEndgameRowsIsRejected() {
        XCTAssertThrowsError(
            try buildDraft("""
            {
              "id": "genshin-6.1-spiral-abyss",
              "kind": "endgame",
              "title": "Spiral Abyss",
              "start": "2026-11-01",
              "end": "2026-11-15"
            }
            """)
        ) { error in
            XCTAssertEqual(error as? TimelineImportService.ImportError, .onlyFixedEndgame)
        }
    }

    func testUnknownGameIsRejected() throws {
        XCTAssertThrowsError(
            try buildDraft("""
            {
              "id": "fortnite-event",
              "kind": "event",
              "title": "Fortnite Event",
              "start": "2026-11-18",
              "end": "2026-12-01"
            }
            """, game: "Fortnite")
        )
    }

    // MARK: - Helpers

    private func buildDraft(
        _ items: String,
        game: String = "Genshin Impact",
        patch: String = "6.1"
    ) throws -> TimelineImportService.Draft {
        let data = try XCTUnwrap(json(items, game: game, patch: patch).data(using: .utf8))
        return try TimelineImportService.buildDraft(
            TimelineImportService.decode(data),
            now: now
        )
    }

    private func prepare(_ items: String) throws -> TimelineImportService.Plan {
        let data = try XCTUnwrap(json(items).data(using: .utf8))
        return try TimelineImportService.prepare(data: data, modelContext: context, now: now)
    }

    private func json(
        _ items: String,
        game: String = "Genshin Impact",
        patch: String = "6.1"
    ) -> String {
        """
        {
          "format": "lifeos.timeline",
          "version": 1,
          "game": "\(game)",
          "patch": "\(patch)",
          "items": [\(items)]
        }
        """
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }
}

private extension TimelineImportService.Item {
    func endDate(calendar: Calendar) -> Date? {
        guard let duration else { return nil }
        if isAllDay {
            let days = max(1, Int(duration / 86_400))
            return calendar.date(byAdding: .day, value: days - 1, to: startDate)
        }
        return startDate.addingTimeInterval(duration)
    }
}
