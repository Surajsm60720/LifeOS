import XCTest
@testable import LifeOS

final class EntryCapabilityTests: XCTestCase {
    func testGameOtherDisablesRecurrenceAndNotifications() {
        let entry = Entry.makeDefault(category: .game, gameSubCategory: .other)
        XCTAssertFalse(entry.supportsRecurrence)
        XCTAssertFalse(entry.supportsNotifications)
        XCTAssertFalse(entry.isCompletable)
    }

    func testPrimaryGamesEnableCompletionAndNotifications() {
        let entry = Entry.makeDefault(category: .game, gameSubCategory: .genshinImpact)
        XCTAssertTrue(entry.supportsRecurrence)
        XCTAssertTrue(entry.supportsNotifications)
        XCTAssertTrue(entry.isCompletable)
    }

    func testEntertainmentHasProgressNoNotifications() {
        let entry = Entry.makeDefault(category: .entertainment, entertainmentSubCategory: .manga)
        XCTAssertTrue(entry.supportsProgress)
        XCTAssertFalse(entry.supportsNotifications)
        XCTAssertTrue(entry.supportsRecurrence)
        XCTAssertEqual(entry.progress?.unitLabel, "chapter")
    }

    func testIRLSupportsLocation() {
        let entry = Entry.makeDefault(category: .irl)
        XCTAssertTrue(entry.supportsLocation)
        XCTAssertTrue(entry.supportsExpense)
        XCTAssertFalse(entry.supportsProgress)
    }

    func testExpenseAndRecurrenceAreMutuallyExclusiveViaSupports() {
        let entry = Entry.makeDefault(category: .irl)
        entry.trackExpense = true
        entry.expenseLines = [ExpenseLine(title: "Dinner", amount: Decimal(42))]
        XCTAssertFalse(entry.supportsRecurrence)
        entry.clearExpense()
        entry.recurrence = RecurrenceRule(frequency: .weekly)
        XCTAssertFalse(entry.supportsExpense)
    }

    func testExpenseTotalAndEqualSplit() {
        let entry = Entry.makeDefault(category: .irl)
        entry.trackExpense = true
        entry.expenseLines = [
            ExpenseLine(title: "Dinner", amount: Decimal(100)),
            ExpenseLine(title: "Cab", amount: Decimal(50))
        ]
        XCTAssertEqual(entry.expenseTotal, Decimal(150))
        entry.applyEqualSplit(among: ["Alex", "Sam", "Riya"])
        XCTAssertEqual(entry.expenseBalances.count, 3)
        XCTAssertEqual(entry.expenseOwedToYou, Decimal(150))
        XCTAssertEqual(entry.expenseBalances.map(\.amount).reduce(0, +), Decimal(150))
    }

    func testPrimaryGamesSupportEventTypeOtherSupportsSession() {
        let primary = Entry.makeDefault(category: .game, gameSubCategory: .genshinImpact)
        XCTAssertTrue(primary.supportsEventType)
        XCTAssertFalse(primary.supportsSessionLog)

        let other = Entry.makeDefault(category: .game, gameSubCategory: .other)
        XCTAssertFalse(other.supportsEventType)
        XCTAssertTrue(other.supportsSessionLog)
    }
}
