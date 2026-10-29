import Foundation

struct PitySnapshot: Equatable, Sendable {
    var currentPity: Int
    var lifetimePulls: Int
    var isGuaranteed: Bool
    var fatePoints: Int
    var hardPity: Int
    var softPity: Int?
    var guaranteeKind: PityGuaranteeKind
    var fatePointCap: Int
    var guaranteeLabel: String? = nil
}

enum PityFiveStarOutcome: String, Sendable {
    case featured
    case offBanner
}

enum PityProximity: Int, Equatable, Sendable, Comparable {
    case early = 0
    case approaching = 1
    case softPity = 2
    case atHard = 3
    case overPity = 4

    static func < (lhs: PityProximity, rhs: PityProximity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum PityRules {
    static let incrementCap = 999

    static func increment(_ state: PitySnapshot, by amount: Int) -> PitySnapshot {
        guard amount > 0 else { return state }
        var next = state
        next.currentPity = min(incrementCap, state.currentPity + amount)
        return next
    }

    static func decrement(_ state: PitySnapshot, by amount: Int) -> PitySnapshot {
        guard amount > 0 else { return state }
        var next = state
        next.currentPity = max(0, state.currentPity - amount)
        return next
    }

    static func resetPityOnly(_ state: PitySnapshot) -> PitySnapshot {
        var next = state
        next.currentPity = 0
        return next
    }

    /// Smart 5★: zeros pity, then updates guarantee / fate from the outcome.
    static func applyFiveStar(_ state: PitySnapshot, outcome: PityFiveStarOutcome) -> PitySnapshot {
        var next = state
        next.currentPity = 0

        switch state.guaranteeKind {
        case .none, .alwaysGuaranteed:
            return next
        case .fiftyFifty, .seventyFiveTwentyFive, .sixtyForty, .eightyTwenty, .custom:
            if state.isGuaranteed {
                next.isGuaranteed = false
                next.fatePoints = 0
                return next
            }

            switch outcome {
            case .featured:
                next.isGuaranteed = false
                next.fatePoints = 0
            case .offBanner:
                if state.fatePointCap > 0 {
                    next.fatePoints = min(state.fatePointCap, state.fatePoints + 1)
                    next.isGuaranteed = next.fatePoints >= state.fatePointCap
                } else {
                    next.isGuaranteed = true
                }
            }
            return next
        }
    }

    static func toggleGuarantee(_ state: PitySnapshot) -> PitySnapshot {
        guard state.guaranteeKind.usesFeaturedCoinFlip else { return state }
        var next = state
        next.isGuaranteed.toggle()
        return next
    }

    static func setFatePoints(_ state: PitySnapshot, to value: Int) -> PitySnapshot {
        var next = state
        next.fatePoints = max(0, min(max(state.fatePointCap, 0), value))
        return next
    }

    static func remaining(for state: PitySnapshot) -> Int {
        max(0, state.hardPity - state.currentPity)
    }

    static func progress(for state: PitySnapshot) -> Double {
        guard state.hardPity > 0 else { return 0 }
        return min(1, Double(state.currentPity) / Double(state.hardPity))
    }

    static func proximity(for state: PitySnapshot) -> PityProximity {
        if state.currentPity > state.hardPity { return .overPity }
        if state.currentPity >= state.hardPity { return .atHard }
        if let soft = state.softPity, state.currentPity >= soft { return .softPity }
        if remaining(for: state) <= 20 { return .approaching }
        return .early
    }

    static func needsOutcomePrompt(for state: PitySnapshot) -> Bool {
        state.guaranteeKind.usesFeaturedCoinFlip && !state.isGuaranteed
    }
}
