import SwiftUI

enum LifeOSTheme {
    /// Near-black ink canvas
    static let canvas = Color(red: 0.06, green: 0.06, blue: 0.07)
    /// Slightly lifted surface
    static let elevated = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let stroke = Color.white.opacity(0.07)
    static let softText = Color(red: 0.62, green: 0.63, blue: 0.65)
    /// Neutral cool gray highlight — no warm/yellow punch
    static let accent = Color(red: 0.78, green: 0.80, blue: 0.84)

    /// Muted category markers (desaturated, low chroma)
    static let irl = Color(red: 0.55, green: 0.62, blue: 0.70)
    static let game = Color(red: 0.62, green: 0.60, blue: 0.58)
    static let entertainment = Color(red: 0.58, green: 0.58, blue: 0.64)

    static func category(_ category: EntryCategory) -> Color {
        switch category {
        case .irl: irl
        case .game: game
        case .entertainment: entertainment
        }
    }
}
