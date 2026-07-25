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
        XCTAssertFalse(entry.supportsProgress)
    }
}
