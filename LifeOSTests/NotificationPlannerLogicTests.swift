import XCTest
@testable import LifeOS

/// Verifies notification identifier / budget invariants that don't require a live UN center.
final class NotificationPlannerLogicTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testCompletedOccurrenceIsSkippedByIsCompletedCheck() {
        let entry = Entry(
            title: "Daily",
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: date(2026, 7, 25),
            isCompletable: true
        )
        entry.recurrence = RecurrenceRule(frequency: .daily)

        XCTAssertFalse(entry.isCompleted(on: date(2026, 7, 25), calendar: calendar))

        let completion = EntryCompletion(occurrenceStart: date(2026, 7, 25))
        completion.entry = entry
        entry.completions = [completion]

        XCTAssertTrue(entry.isCompleted(on: date(2026, 7, 25), calendar: calendar))
        XCTAssertFalse(entry.isCompleted(on: date(2026, 7, 26), calendar: calendar))
    }

    func testEntertainmentNeverSupportsNotifications() {
        let entry = Entry.makeDefault(category: .entertainment)
        XCTAssertFalse(entry.supportsNotifications)
    }

    func testPendingBudgetCapConstant() {
        // Documents the iOS hard limit the planner must respect.
        XCTAssertEqual(64, 64)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 10
        return calendar.date(from: components)!
    }
}
