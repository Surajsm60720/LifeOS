import SwiftUI

enum PityVisuals {
    /// Escalates from the game accent into muted gold, then orange, then a
    /// restrained red as the counter climbs through soft pity and past hard.
    static func heatColor(proximity: PityProximity, game: GameSubCategory) -> Color {
        let base = GameIdentity.accent(for: game)
        switch proximity {
        case .early:
            return base
        case .approaching:
            return Color(red: 0.78, green: 0.70, blue: 0.56)
        case .softPity:
            return Color.orange.opacity(0.92)
        case .atHard:
            return Color(red: 0.90, green: 0.46, blue: 0.34)
        case .overPity:
            return Color(red: 0.86, green: 0.32, blue: 0.30)
        }
    }

    static func strokeColor(proximity: PityProximity, game: GameSubCategory) -> Color {
        let heat = heatColor(proximity: proximity, game: game)
        switch proximity {
        case .early:
            return LifeOSTheme.stroke
        case .approaching:
            return heat.opacity(0.35)
        case .softPity:
            return heat.opacity(0.50)
        case .atHard, .overPity:
            return heat.opacity(0.70)
        }
    }

    static func countColor(proximity: PityProximity, game: GameSubCategory) -> Color {
        switch proximity {
        case .early:
            return .white
        default:
            return heatColor(proximity: proximity, game: game)
        }
    }

    static func proximityLabel(for state: PitySnapshot) -> String? {
        switch PityRules.proximity(for: state) {
        case .early:
            return nil
        case .approaching:
            let left = PityRules.remaining(for: state)
            return left == 1 ? "1 left" : "\(left) left"
        case .softPity:
            return "Soft pity · \(PityRules.remaining(for: state)) left"
        case .atHard:
            return "Hard pity"
        case .overPity:
            return "Over pity"
        }
    }

    static func guaranteeChip(for state: PitySnapshot) -> String {
        if state.guaranteeKind == .alwaysGuaranteed {
            return "Guaranteed"
        }
        if state.guaranteeKind.usesFeaturedCoinFlip {
            if state.isGuaranteed { return "Guaranteed" }
            if state.guaranteeKind == .custom {
                let label = state.guaranteeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return label.isEmpty ? "Custom" : label
            }
            return state.guaranteeKind.chipLabel
        }
        return state.guaranteeKind.chipLabel
    }
}
