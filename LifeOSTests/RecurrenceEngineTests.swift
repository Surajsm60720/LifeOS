import XCTest
@testable import LifeOS

final class RecurrenceEngineTests: XCTestCase {
    private var calendar: Calendar!
    private var engine: RecurrenceEngine!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        engine = RecurrenceEngine()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testDailyOccurrences() {
        let entry = Entry(title: "Daily", category: .irl, startDate: date(2026, 7, 1))
        entry.recurrence = RecurrenceRule(frequency: .daily, interval: 1)

        let results = engine.occurrences(
            for: entry,
            in: date(2026, 7, 1)...date(2026, 7, 5, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(calendar.component(.day, from: results[0]), 1)
        XCTAssertEqual(calendar.component(.day, from: results[4]), 5)
    }

    func testBiweeklyOccurrences() {
        let entry = Entry(title: "Biweekly", category: .irl, startDate: date(2026, 7, 1))
        entry.recurrence = RecurrenceRule(frequency: .weekly, interval: 2)

        let results = engine.occurrences(
            for: entry,
            in: date(2026, 7, 1)...date(2026, 7, 31, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(calendar.component(.day, from: results[0]), 1)
        XCTAssertEqual(calendar.component(.day, from: results[1]), 15)
        XCTAssertEqual(calendar.component(.day, from: results[2]), 29)
    }

    func testWeeklyWithWeekdayMask() {
        let entry = Entry(title: "MonWed", category: .game, startDate: date(2026, 7, 1))
        entry.recurrence = RecurrenceRule(
            frequency: .weekly,
            interval: 1,
            daysOfWeek: [.monday, .wednesday]
        )

        let results = engine.occurrences(
            for: entry,
            in: date(2026, 7, 1)...date(2026, 7, 10, hour: 23),
            calendar: calendar
        )

        let weekdays = results.map { calendar.component(.weekday, from: $0) }
        XCTAssertTrue(weekdays.allSatisfy { $0 == Weekday.monday.rawValue || $0 == Weekday.wednesday.rawValue })
        XCTAssertFalse(results.isEmpty)
    }

    func testMonthlyClampsEndOfMonth() {
        let entry = Entry(title: "Month End", category: .irl, startDate: date(2026, 1, 31))
        entry.recurrence = RecurrenceRule(frequency: .monthly, interval: 1)

        let results = engine.occurrences(
            for: entry,
            in: date(2026, 1, 1)...date(2026, 3, 31, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(calendar.component(.day, from: results[0]), 31)
        XCTAssertEqual(calendar.component(.month, from: results[1]), 2)
        XCTAssertEqual(calendar.component(.day, from: results[1]), 28)
        XCTAssertEqual(calendar.component(.day, from: results[2]), 31)
    }

    func testEveryNMonths() {
        let entry = Entry(title: "Quarterly", category: .irl, startDate: date(2026, 1, 15))
        entry.recurrence = RecurrenceRule(frequency: .everyNMonths, interval: 3)

        let results = engine.occurrences(
            for: entry,
            in: date(2026, 1, 1)...date(2026, 12, 31, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(calendar.component(.month, from: results[0]), 1)
        XCTAssertEqual(calendar.component(.month, from: results[1]), 4)
        XCTAssertEqual(calendar.component(.month, from: results[2]), 7)
        XCTAssertEqual(calendar.component(.month, from: results[3]), 10)
    }

    func testOccurrenceCountLimit() {
        let entry = Entry(title: "Limited", category: .irl, startDate: date(2026, 7, 1))
        entry.recurrence = RecurrenceRule(frequency: .daily, interval: 1, occurrenceCount: 3)

        let results = engine.occurrences(
            for: entry,
            in: date(2026, 7, 1)...date(2026, 7, 31, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(results.count, 3)
    }

    func testEndDateStopsSeries() {
        let entry = Entry(title: "Ends", category: .irl, startDate: date(2026, 7, 1))
        entry.recurrence = RecurrenceRule(
            frequency: .daily,
            interval: 1,
            endDate: date(2026, 7, 3, hour: 23)
        )

        let results = engine.occurrences(
            for: entry,
            in: date(2026, 7, 1)...date(2026, 7, 31, hour: 23),
            calendar: calendar
        )

        XCTAssertEqual(results.count, 3)
    }

    func testNonRecurringSingleOccurrence() {
        let entry = Entry(title: "Once", category: .irl, startDate: date(2026, 7, 10, hour: 14))
        let results = engine.occurrences(
            for: entry,
            in: date(2026, 7, 1)...date(2026, 7, 31, hour: 23),
            calendar: calendar
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(calendar.component(.day, from: results[0]), 10)
    }

    func testOccursOnDay() {
        let entry = Entry(title: "Daily", category: .irl, startDate: date(2026, 7, 1))
        entry.recurrence = RecurrenceRule(frequency: .daily)
        XCTAssertTrue(engine.occurs(on: date(2026, 7, 5), entry: entry, calendar: calendar))
        XCTAssertFalse(engine.occurs(on: date(2026, 6, 30), entry: entry, calendar: calendar))
    }
}
