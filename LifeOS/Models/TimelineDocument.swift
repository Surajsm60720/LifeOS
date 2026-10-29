import Foundation

/// On-disk shape of a game timeline file. Every field is optional so a missing
/// key produces a useful validation message instead of a decoding failure.
struct TimelineDocument: Decodable {
    var format: String?
    var version: Int?
    var game: String?
    var patch: String?
    var serverTimeZone: String?
    var generatedAt: String?
    var source: String?
    var items: [TimelineItem]?
}

struct TimelineItem: Decodable {
    var id: String?
    var kind: String?
    var title: String?
    var start: String?
    var end: String?
    var featured: [String]?
    var group: String?
    var notes: String?
    var sourceLine: String?
    var confidence: String?
    var phase: Int?
}

/// The three row types v1.0.5 imports. Maintenance, livestream, and battle-pass
/// rows are deliberately skipped: they add Ongoing clutter without helping the
/// week-to-week planning this feature is for.
enum TimelineKind: String, CaseIterable, Sendable {
    case event
    case banner
    case endgame

    init?(raw: String) {
        let token = raw
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        switch token {
        case "event", "events", "ingameevent", "ingameevents",
             "loginevent", "minievent", "minigame", "quest", "story":
            self = .event
        case "banner", "banners", "wish", "wishes", "warp", "warps", "convene",
             "convenes", "bannerwindow", "characterwish", "weaponwish":
            self = .banner
        case "endgame", "endgamecontent", "abyss", "spiralabyss", "theater",
             "imaginariumtheater", "memoryofchaos", "purefiction",
             "apocalypticashadow", "towerofadversity", "whimperingwastes":
            self = .endgame
        default:
            return nil
        }
    }

    var eventType: GameEventType {
        switch self {
        case .event: return .inGameEvents
        case .banner: return .bannerWindow
        case .endgame: return .endgameContent
        }
    }

    var displayName: String {
        switch self {
        case .event: return "Events"
        case .banner: return "Banners"
        case .endgame: return "Endgame"
        }
    }
}

enum TimelineGameMatcher {
    /// Accepts the display name plus the abbreviations an LLM is likely to emit.
    static func match(_ raw: String) -> GameSubCategory? {
        let token = raw
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        switch token {
        case "genshinimpact", "genshin", "gi", "原神":
            return .genshinImpact
        case "honkaistarrail", "starrail", "hsr", "honkai":
            return .honkaiStarRail
        case "wutheringwaves", "wuwa", "wuthering", "鸣潮":
            return .wutheringWaves
        default:
            return nil
        }
    }
}
