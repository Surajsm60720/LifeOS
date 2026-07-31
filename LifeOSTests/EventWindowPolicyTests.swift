import XCTest
@testable import LifeOS

final class EventWindowPolicyTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
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
