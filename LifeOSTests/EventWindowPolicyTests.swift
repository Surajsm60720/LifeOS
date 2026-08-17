import XCTest
@testable import LifeOS

final class EventWindowPolicyTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
    }

    func testShortDurationIsNotEventWindow() {
        let entry = Entry(
            title: "Meeting",
            category: .irl,
            startDate: date(2026, 7, 1),
            duration: 3600
        )
        XCTAssertFalse(entry.isEventWindow)
    }

    func testExactlyOneDayIsEventWindow() {
        let entry = Entry(
            title: "Single Day",
            category: .entertainment,
            subCategory: EntertainmentSubCategory.manga.rawValue,
            startDate: date(2026, 7, 1),
            duration: 86_400
        )
        XCTAssertTrue(entry.isEventWindow)
    }

    func testTwoDayDurationIsEventWindow() {
        let entry = Entry(
            title: "Manga Binge",
            category: .entertainment,
            subCategory: EntertainmentSubCategory.manga.rawValue,
            startDate: date(2026, 7, 1),
            isAllDay: true,
            duration: 2 * 86_400
        )
        XCTAssertTrue(entry.isEventWindow)
        XCTAssertEqual(entry.endDate(calendar: calendar), date(2026, 7, 2, hour: 23, minute: 59, second: 59))
    }

    func testWeekLongDurationIsEventWindow() {
        let entry = Entry(
            title: "Banner",
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: date(2026, 7, 1),
            isAllDay: true,
            duration: 7 * 86_400
        )
        XCTAssertTrue(entry.isEventWindow)
        XCTAssertEqual(entry.endDate(calendar: calendar), date(2026, 7, 7, hour: 23, minute: 59, second: 59))
    }

    func testRecurringEntryIsNeverEventWindow() {
        let entry = Entry(
            title: "Daily",
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: date(2026, 7, 1),
            duration: 30 * 86_400
        )
        entry.recurrence = RecurrenceRule(frequency: .daily)
        XCTAssertFalse(entry.isEventWindow)
    }

    func testDailyRecurringIsOmittedFromOngoing() {
        let entry = weeklyGame("Dailies", start: date(2026, 7, 1), frequency: .daily)

        let grouped = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 7, 8),
            calendar: calendar
        )

        XCTAssertTrue(grouped.active.isEmpty)
        XCTAssertTrue(grouped.upcoming.isEmpty)
        XCTAssertTrue(grouped.recentlyEnded.isEmpty)
    }

    func testWeeklyRecurringIsActiveInCurrentWeek() {
        let entry = weeklyGame("Weekly Boss", start: date(2026, 7, 1), frequency: .weekly)

        let grouped = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 7, 8),
            calendar: calendar
        )

        XCTAssertEqual(grouped.active.count, 1)
        XCTAssertEqual(grouped.active.first?.entry.title, "Weekly Boss")
        XCTAssertEqual(grouped.active.first?.kind, .currentPeriod)
        XCTAssertEqual(grouped.active.first?.periodCaption, "This week")
        XCTAssertEqual(grouped.active.first?.status, .active)
        XCTAssertEqual(grouped.active.first?.startDate, date(2026, 7, 8))
        XCTAssertEqual(grouped.active.first?.endDate, date(2026, 7, 15))
        XCTAssertFalse(grouped.active.first?.isPeriodComplete ?? true)
        XCTAssertTrue(grouped.upcoming.isEmpty)
        XCTAssertTrue(grouped.recentlyEnded.isEmpty)
    }

    func testWeeklyRecurringNextWeekIsOmittedUntilThatWeek() {
        let entry = weeklyGame("Weekly Boss", start: date(2026, 7, 15), frequency: .weekly)

        let grouped = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 7, 8),
            calendar: calendar
        )

        XCTAssertTrue(grouped.active.isEmpty)
        XCTAssertTrue(grouped.upcoming.isEmpty)
        XCTAssertTrue(grouped.recentlyEnded.isEmpty)
    }

    func testMonthlyRecurringSpansOccurrenceToNextOccurrence() {
        let entry = weeklyGame("Monthly Reset", start: date(2026, 8, 16), frequency: .monthly)

        let grouped = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 8, 17),
            calendar: calendar
        )

        XCTAssertEqual(grouped.active.count, 1)
        XCTAssertEqual(grouped.active.first?.startDate, date(2026, 8, 16))
        XCTAssertEqual(grouped.active.first?.endDate, date(2026, 9, 16))
        XCTAssertEqual(grouped.active.first?.periodCaption, "This month")
        XCTAssertTrue(grouped.upcoming.isEmpty)
        XCTAssertTrue(grouped.recentlyEnded.isEmpty)
    }

    func testMonthlyRecurringOmitsDaysBeforeFirstOccurrence() {
        let entry = weeklyGame("Monthly Reset", start: date(2026, 8, 16), frequency: .monthly)

        let grouped = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 8, 15),
            calendar: calendar
        )

        XCTAssertTrue(grouped.active.isEmpty)
        XCTAssertTrue(grouped.upcoming.isEmpty)
    }

    func testMonthlyRecurringRollsToNextCycleOnOccurrenceDay() {
        let entry = weeklyGame("Monthly Reset", start: date(2026, 8, 16), frequency: .monthly)

        let grouped = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 9, 16),
            calendar: calendar
        )

        XCTAssertEqual(grouped.active.count, 1)
        XCTAssertEqual(grouped.active.first?.startDate, date(2026, 9, 16))
        XCTAssertEqual(grouped.active.first?.endDate, date(2026, 10, 16))
    }

    func testMonthlyRecurringIsActiveInCurrentCycleOnly() {
        let entry = weeklyGame("Monthly Reset", start: date(2026, 7, 10), frequency: .monthly)

        let thisCycle = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 7, 20),
            calendar: calendar
        )
        XCTAssertEqual(thisCycle.active.count, 1)
        XCTAssertEqual(thisCycle.active.first?.startDate, date(2026, 7, 10))
        XCTAssertEqual(thisCycle.active.first?.endDate, date(2026, 8, 10))
        XCTAssertTrue(thisCycle.upcoming.isEmpty)

        let stillSameCycle = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 8, 5),
            calendar: calendar
        )
        XCTAssertEqual(stillSameCycle.active.count, 1)
        XCTAssertEqual(stillSameCycle.active.first?.startDate, date(2026, 7, 10))
        XCTAssertEqual(stillSameCycle.active.first?.endDate, date(2026, 8, 10))

        let june = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 6, 20),
            calendar: calendar
        )
        XCTAssertTrue(june.active.isEmpty)
        XCTAssertTrue(june.upcoming.isEmpty)
    }

    func testEveryTwoWeeksStaysActiveUntilNextOccurrence() {
        let entry = weeklyGame("Abyss", start: date(2026, 7, 1), frequency: .weekly)
        entry.recurrence?.interval = 2

        let midCycle = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 7, 8),
            calendar: calendar
        )
        XCTAssertEqual(midCycle.active.count, 1)
        XCTAssertEqual(midCycle.active.first?.startDate, date(2026, 7, 1))
        XCTAssertEqual(midCycle.active.first?.endDate, date(2026, 7, 15))

        let nextOccurrence = EventWindowEngine.groupedWindows(
            from: [entry],
            now: date(2026, 7, 15),
            calendar: calendar
        )
        XCTAssertEqual(nextOccurrence.active.count, 1)
        XCTAssertEqual(nextOccurrence.active.first?.startDate, date(2026, 7, 15))
        XCTAssertEqual(nextOccurrence.active.first?.endDate, date(2026, 7, 29))
    }

    func testCompletableWeeklyIsPeriodCompleteWhenOccurrenceDone() {
        let start = date(2026, 7, 1)
        let entry = weeklyGame("Weekly Boss", start: start, frequency: .weekly)
        entry.isCompletable = true

        let now = date(2026, 7, 8)
        let occurrence = RecurrenceEngine.shared.occurrences(
            for: entry,
            in: now.addingTimeInterval(-7 * 86_400)...now.addingTimeInterval(7 * 86_400),
            calendar: calendar
        ).first { calendar.isDate($0, inSameDayAs: now) } ?? now

        entry.completions = [EntryCompletion(occurrenceStart: occurrence)]

        let grouped = EventWindowEngine.groupedWindows(
            from: [entry],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(grouped.active.count, 1)
        XCTAssertEqual(grouped.active.first?.status, .active)
        XCTAssertTrue(grouped.active.first?.isPeriodComplete ?? false)
    }

    func testGroupedWindowsActiveAndUpcoming() {
        let active = Entry(
            title: "Active Banner",
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: date(2026, 7, 1),
            isAllDay: true,
            duration: 14 * 86_400
        )
        let upcoming = Entry(
            title: "Future Endgame",
            category: .game,
            subCategory: GameSubCategory.honkaiStarRail.rawValue,
            startDate: date(2026, 8, 1),
            isAllDay: true,
            duration: 21 * 86_400
        )

        let grouped = EventWindowEngine.groupedWindows(
            from: [active, upcoming],
            now: date(2026, 7, 10),
            calendar: calendar
        )

        XCTAssertEqual(grouped.active.count, 1)
        XCTAssertEqual(grouped.active.first?.entry.title, "Active Banner")
        XCTAssertEqual(grouped.active.first?.kind, .durationWindow)
        XCTAssertEqual(grouped.upcoming.count, 1)
        XCTAssertEqual(grouped.upcoming.first?.entry.title, "Future Endgame")
    }

    func testFormatDurationIncludesDays() {
        XCTAssertEqual(DateFormatting.formatDuration(42 * 86_400), "42 days")
        XCTAssertEqual(DateFormatting.formatDuration(3600), "1 hr")
    }

    func testFormatDateRange() {
        let range = DateFormatting.formatDateRange(
            start: date(2026, 7, 1),
            end: date(2026, 7, 14),
            calendar: calendar
        )
        XCTAssertTrue(range.contains("Jul"))
    }

    private func weeklyGame(
        _ title: String,
        start: Date,
        frequency: RecurrenceFrequency
    ) -> Entry {
        let entry = Entry(
            title: title,
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: start,
            duration: 3600
        )
        entry.recurrence = RecurrenceRule(frequency: frequency)
        return entry
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }
}
