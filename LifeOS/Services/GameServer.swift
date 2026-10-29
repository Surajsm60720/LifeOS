import Foundation

/// A game's regional server.
///
/// Timeline images print calendar dates, not instants, and the same printed date
/// resolves differently on each server. The identifier here is only used for
/// storage; the time zone is the part that matters.
enum GameServer: String, Codable, CaseIterable, Sendable {
    case america
    case europe
    case asia
    case twHkMo
    case sea

    var displayName: String {
        switch self {
        case .america: return "America"
        case .europe: return "Europe"
        case .asia: return "Asia"
        case .twHkMo: return "TW / HK / MO"
        case .sea: return "SEA"
        }
    }

    /// HoYoverse and Kuro server time is a fixed UTC offset; it does not follow
    /// the player's daylight-saving rules. Genshin America is UTC−5 year-round,
    /// which is why its 04:00 reset is always 14:30 IST.
    var utcOffsetHours: Int {
        switch self {
        case .america: return -5
        case .europe: return 1
        case .asia: return 8
        case .twHkMo: return 8
        case .sea: return 7
        }
    }

    var timeZone: TimeZone {
        TimeZone(secondsFromGMT: utcOffsetHours * 3_600) ?? TimeZone(secondsFromGMT: 0)!
    }

    /// IANA identifier for the fixed offset. `Etc/GMT` signs are inverted by
    /// definition, so `Etc/GMT+5` is UTC−5.
    var timeZoneIdentifier: String {
        switch utcOffsetHours {
        case 0: return "Etc/GMT"
        default: return "Etc/GMT\(utcOffsetHours > 0 ? "-" : "+")\(abs(utcOffsetHours))"
        }
    }

    var utcOffsetDescription: String {
        let sign = utcOffsetHours < 0 ? "−" : "+"
        return "UTC\(sign)\(abs(utcOffsetHours))"
    }
}

/// Everything the importer needs to turn printed dates into real instants.
struct GameServerProfile: Sendable {
    let game: GameSubCategory
    let servers: [GameServer]
    let defaultServer: GameServer
    /// Daily reset, in minutes after midnight, server time. Defaults are per game
    /// and can be overridden in Settings; the value is used for the local-time
    /// readout so a server whose reset drifts can be corrected.
    let resetMinutes: Int
    /// The hour banners swap between phases. This is *not* the daily reset: in
    /// Genshin it is 18:00 server time, which is a different local day in IST.
    let defaultBannerSwitchMinutes: Int
    /// Roughly when the patch goes live after maintenance, used as the start of
    /// the first banner phase.
    let patchLiveMinutes: Int
}

/// Per-game server and timing settings, stored in `UserDefaults`.
enum GameServerSettings {
    static func profile(for game: GameSubCategory) -> GameServerProfile? {
        switch game {
        case .genshinImpact:
            return GameServerProfile(
                game: game,
                servers: [.america, .europe, .asia, .twHkMo],
                defaultServer: .america,
                resetMinutes: 4 * 60,
                defaultBannerSwitchMinutes: 18 * 60,
                patchLiveMinutes: 11 * 60
            )
        case .honkaiStarRail:
            return GameServerProfile(
                game: game,
                servers: [.america, .europe, .asia, .twHkMo],
                defaultServer: .asia,
                resetMinutes: 4 * 60,
                defaultBannerSwitchMinutes: 12 * 60,
                patchLiveMinutes: 11 * 60
            )
        case .wutheringWaves:
            return GameServerProfile(
                game: game,
                servers: [.america, .europe, .asia, .sea, .twHkMo],
                defaultServer: .asia,
                resetMinutes: 4 * 60,
                defaultBannerSwitchMinutes: 10 * 60,
                patchLiveMinutes: 10 * 60
            )
        case .other:
            return nil
        }
    }

    static func server(for game: GameSubCategory) -> GameServer {
        guard let profile = profile(for: game) else { return .asia }
        let stored = UserDefaults.standard.string(forKey: serverKey(game))
        let server = stored.flatMap(GameServer.init(rawValue:))
        guard let server, profile.servers.contains(server) else { return profile.defaultServer }
        return server
    }

    static func setServer(_ server: GameServer, for game: GameSubCategory) {
        UserDefaults.standard.set(server.rawValue, forKey: serverKey(game))
    }

    static func resetMinutes(for game: GameSubCategory) -> Int {
        guard let profile = profile(for: game) else { return 4 * 60 }
        guard UserDefaults.standard.object(forKey: resetKey(game)) != nil else {
            return profile.resetMinutes
        }
        let value = UserDefaults.standard.integer(forKey: resetKey(game))
        return (0..<24 * 60).contains(value) ? value : profile.resetMinutes
    }

    static func setResetMinutes(_ minutes: Int, for game: GameSubCategory) {
        let clamped = min(max(0, minutes), 24 * 60 - 1)
        UserDefaults.standard.set(clamped, forKey: resetKey(game))
    }

    static func hasCustomReset(for game: GameSubCategory) -> Bool {
        UserDefaults.standard.object(forKey: resetKey(game)) != nil
    }

    static func resetCustomReset(for game: GameSubCategory) {
        UserDefaults.standard.removeObject(forKey: resetKey(game))
    }

    static func bannerSwitchMinutes(for game: GameSubCategory) -> Int {
        guard let profile = profile(for: game) else { return 18 * 60 }
        guard UserDefaults.standard.object(forKey: bannerKey(game)) != nil else {
            return profile.defaultBannerSwitchMinutes
        }
        let value = UserDefaults.standard.integer(forKey: bannerKey(game))
        return (0..<24 * 60).contains(value) ? value : profile.defaultBannerSwitchMinutes
    }

    static func setBannerSwitchMinutes(_ minutes: Int, for game: GameSubCategory) {
        let clamped = min(max(0, minutes), 24 * 60 - 1)
        UserDefaults.standard.set(clamped, forKey: bannerKey(game))
    }

    static func hasCustomBannerSwitch(for game: GameSubCategory) -> Bool {
        UserDefaults.standard.object(forKey: bannerKey(game)) != nil
    }

    static func resetCustomBannerSwitch(for game: GameSubCategory) {
        UserDefaults.standard.removeObject(forKey: bannerKey(game))
    }

    static func timeZone(for game: GameSubCategory) -> TimeZone {
        server(for: game).timeZone
    }

    /// "UTC−5", used in import warnings so a fixed offset is not mistaken for a
    /// DST-aware city zone.
    static func offsetDescription(for game: GameSubCategory) -> String {
        server(for: game).utcOffsetDescription
    }

    /// Gregorian calendar pinned to the game's server time zone. Used for every
    /// date interpretation, so `2026-11-01 03:59` means 03:59 on that server.
    static func calendar(for game: GameSubCategory) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(for: game)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// "2:30 PM" for the daily reset, expressed in the phone's time zone.
    static func resetTimeDescription(for game: GameSubCategory, locale: Locale = .current) -> String? {
        guard profile(for: game) != nil else { return nil }
        return localTime(minutes: resetMinutes(for: game), game: game, locale: locale)
    }

    /// "7:30 PM" for the banner switch, expressed in the phone's time zone.
    static func bannerSwitchDescription(for game: GameSubCategory, locale: Locale = .current) -> String? {
        localTime(minutes: bannerSwitchMinutes(for: game), game: game, locale: locale)
    }

    static func localTime(minutes: Int, game: GameSubCategory, locale: Locale = .current) -> String? {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: dateForLocalPicker(minutes: minutes, game: game))
    }

    /// Instant corresponding to `minutes` on the game's server clock today,
    /// suitable for a `.hourAndMinute` DatePicker that shows the phone's local time.
    /// Genshin America's 04:00 becomes 2:30 PM IST, not 4:00 AM.
    static func dateForLocalPicker(
        minutes: Int,
        game: GameSubCategory,
        reference: Date = .now
    ) -> Date {
        let serverCalendar = calendar(for: game)
        var components = serverCalendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        return serverCalendar.date(from: components) ?? reference
    }

    /// Reads the hour/minute the user picked in local time back into minutes on
    /// the game's server clock, so storing 2:30 PM IST for America persists as 04:00.
    static func minutesFromLocalPicker(date: Date, game: GameSubCategory) -> Int {
        let components = calendar(for: game).dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return min(max(0, minutes), 24 * 60 - 1)
    }

    private static func serverKey(_ game: GameSubCategory) -> String {
        "lifeos.gameServer.\(game.rawValue)"
    }

    private static func resetKey(_ game: GameSubCategory) -> String {
        "lifeos.gameReset.\(game.rawValue)"
    }

    private static func bannerKey(_ game: GameSubCategory) -> String {
        "lifeos.gameBannerSwitch.\(game.rawValue)"
    }
}
