import XCTest
@testable import LifeOS

final class ExpenseShareFormatterTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testFullSettlementIncludesItemsBalancesAndShare() {
        let entry = Entry(
            title: "Dinner",
            category: .irl,
            startDate: date(2026, 7, 28),
            notes: "Birthday night",
            trackExpense: true
        )
        entry.locations = [
            LocationEntry(name: "Cafe XYZ"),
            LocationEntry(name: "Home")
        ]
        entry.expenseLines = [
            ExpenseLine(title: "Pizza", amount: 800),
            ExpenseLine(title: "Drinks", amount: 400)
        ]
        entry.expenseBalances = [
            ExpenseBalance(personName: "Alex", amount: 400),
            ExpenseBalance(personName: "Sam", amount: 200)
        ]

        let text = ExpenseShareFormatter.plainSettlement(
            for: entry,
            occurrenceDate: date(2026, 7, 28),
            calendar: calendar
        )

        XCTAssertTrue(text.contains("Dinner"))
        XCTAssertTrue(text.contains("Cafe XYZ → Home") || text.contains("Cafe XYZ"))
        XCTAssertTrue(text.contains("Items"))
        XCTAssertTrue(text.contains("• Pizza — 800"))
        XCTAssertTrue(text.contains("• Drinks — 400"))
        XCTAssertTrue(text.contains("Total — 1200"))
        XCTAssertTrue(text.contains("Settlements"))
        XCTAssertTrue(text.contains("• Alex owes you 400"))
        XCTAssertTrue(text.contains("• Sam owes you 200"))
        XCTAssertTrue(text.contains("Owed to you — 600"))
        XCTAssertTrue(text.contains("Your share (if settled): 1200 − 600 = 600"))
        XCTAssertTrue(text.contains("Notes: Birthday night"))
    }

    func testOmitsSettlementsAndNotesWhenEmpty() {
        let entry = Entry(title: "Solo Lunch", category: .irl, startDate: date(2026, 7, 10), trackExpense: true)
        entry.expenseLines = [ExpenseLine(title: "Sandwich", amount: 12)]

        let text = ExpenseShareFormatter.plainSettlement(
            for: entry,
            occurrenceDate: date(2026, 7, 10),
            calendar: calendar
        )

        XCTAssertTrue(text.contains("Solo Lunch"))
        XCTAssertTrue(text.contains("• Sandwich — 12"))
        XCTAssertTrue(text.contains("Total — 12"))
        XCTAssertFalse(text.contains("Settlements"))
        XCTAssertFalse(text.contains("Your share"))
        XCTAssertFalse(text.contains("Notes:"))
    }

    func testEmptyLineTitleFallsBackToItem() {
        let entry = Entry(title: "Misc", category: .irl, startDate: date(2026, 7, 11), trackExpense: true)
        entry.expenseLines = [ExpenseLine(title: "  ", amount: 5)]

        let text = ExpenseShareFormatter.plainSettlement(
            for: entry,
            occurrenceDate: date(2026, 7, 11),
            calendar: calendar
        )

        XCTAssertTrue(text.contains("• Item — 5"))
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
