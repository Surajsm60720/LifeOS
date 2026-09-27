import XCTest
@testable import LifeOS

final class PityRulesTests: XCTestCase {
    func testIncrementDoesNotTouchLifetime() {
        var state = sample(current: 88, hard: 90, lifetime: 10)
        state = PityRules.increment(state, by: 10)
        XCTAssertEqual(state.currentPity, 98)
        XCTAssertEqual(state.lifetimePulls, 10)

        state = PityRules.increment(state, by: 5_000)
        XCTAssertEqual(state.currentPity, PityRules.incrementCap)
    }

    func testDecrementFloorsAtZero() {
        var state = sample(current: 1, lifetime: 1)
        state = PityRules.decrement(state, by: 5)
        XCTAssertEqual(state.currentPity, 0)
        XCTAssertEqual(state.lifetimePulls, 1)
    }

    func testFiftyFiftyWinStaysOnFiftyFifty() {
        let state = sample(kind: .fiftyFifty, current: 76, guaranteed: false, lifetime: 76)
        let next = PityRules.applyFiveStar(state, outcome: .featured)
        XCTAssertEqual(next.currentPity, 0)
        XCTAssertFalse(next.isGuaranteed)
        XCTAssertEqual(next.lifetimePulls, 76)
    }

    func testFiftyFiftyLossMovesToGuaranteed() {
        let state = sample(kind: .fiftyFifty, current: 80, guaranteed: false)
        let next = PityRules.applyFiveStar(state, outcome: .offBanner)
        XCTAssertEqual(next.currentPity, 0)
        XCTAssertTrue(next.isGuaranteed)
    }

    func testGuaranteedConsumeReturnsToFiftyFifty() {
        let state = sample(kind: .fiftyFifty, current: 12, guaranteed: true)
        let next = PityRules.applyFiveStar(state, outcome: .offBanner)
        XCTAssertEqual(next.currentPity, 0)
        XCTAssertFalse(next.isGuaranteed)
        XCTAssertEqual(next.fatePoints, 0)
    }

    func testAlwaysGuaranteedOnlyResetsPity() {
        let state = sample(kind: .alwaysGuaranteed, current: 64, guaranteed: false)
        let next = PityRules.applyFiveStar(state, outcome: .offBanner)
        XCTAssertEqual(next.currentPity, 0)
        XCTAssertFalse(next.isGuaranteed)
    }

    func testFateCapPromotesGuaranteeOnSecondLoss() {
        var state = sample(kind: .fiftyFifty, current: 70, fateCap: 2, fate: 0)
        state = PityRules.applyFiveStar(state, outcome: .offBanner)
        XCTAssertEqual(state.fatePoints, 1)
        XCTAssertFalse(state.isGuaranteed)

        state.currentPity = 40
        state = PityRules.applyFiveStar(state, outcome: .offBanner)
        XCTAssertEqual(state.fatePoints, 2)
        XCTAssertTrue(state.isGuaranteed)
    }

    func testProximityEscalatesThroughSoftAndHard() {
        let early = sample(current: 10, hard: 90, soft: 74)
        XCTAssertEqual(PityRules.proximity(for: early), .early)

        let approaching = sample(current: 72, hard: 90, soft: 74)
        XCTAssertEqual(PityRules.proximity(for: approaching), .approaching)

        let soft = sample(current: 74, hard: 90, soft: 74)
        XCTAssertEqual(PityRules.proximity(for: soft), .softPity)

        let hard = sample(current: 90, hard: 90, soft: 74)
        XCTAssertEqual(PityRules.proximity(for: hard), .atHard)

        let over = sample(current: 91, hard: 90, soft: 74)
        XCTAssertEqual(PityRules.proximity(for: over), .overPity)
    }

    func testNeedsOutcomePrompt() {
        XCTAssertTrue(PityRules.needsOutcomePrompt(for: sample(kind: .fiftyFifty, guaranteed: false)))
        XCTAssertTrue(PityRules.needsOutcomePrompt(for: sample(kind: .sixtyForty, guaranteed: false)))
        XCTAssertTrue(PityRules.needsOutcomePrompt(for: sample(kind: .custom, guaranteed: false)))
        XCTAssertFalse(PityRules.needsOutcomePrompt(for: sample(kind: .fiftyFifty, guaranteed: true)))
        XCTAssertFalse(PityRules.needsOutcomePrompt(for: sample(kind: .alwaysGuaranteed)))
        XCTAssertFalse(PityRules.needsOutcomePrompt(for: sample(kind: .none)))
    }

    func testCatalogKeysAreUnique() {
        let keys = PityCatalog.presets.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count)
        XCTAssertEqual(PityCatalog.presets.count, 9)
        XCTAssertFalse(keys.contains("gi.chronicled"))
    }

    private func sample(
        kind: PityGuaranteeKind = .fiftyFifty,
        current: Int = 0,
        hard: Int = 90,
        soft: Int? = 74,
        guaranteed: Bool = false,
        lifetime: Int = 0,
        fateCap: Int = 0,
        fate: Int = 0
    ) -> PitySnapshot {
        PitySnapshot(
            currentPity: current,
            lifetimePulls: lifetime,
            isGuaranteed: guaranteed,
            fatePoints: fate,
            hardPity: hard,
            softPity: soft,
            guaranteeKind: kind,
            fatePointCap: fateCap
        )
    }
}
