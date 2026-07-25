import SwiftUI

enum GameIdentity {
    static func accent(for game: GameSubCategory?) -> Color {
        switch game {
        case .genshinImpact:
            return Color(red: 0.58, green: 0.64, blue: 0.68)
        case .honkaiStarRail:
            return Color(red: 0.60, green: 0.60, blue: 0.68)
        case .wutheringWaves:
            return Color(red: 0.55, green: 0.66, blue: 0.64)
        case .other, .none:
            return LifeOSTheme.game
        }
    }

    static func gradient(for game: GameSubCategory?) -> LinearGradient {
        let base = accent(for: game)
        return LinearGradient(
            colors: [base.opacity(0.22), LifeOSTheme.canvas.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
