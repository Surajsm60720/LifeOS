import Foundation

enum EntryCategory: String, Codable, CaseIterable, Identifiable {
    case irl
    case game
    case entertainment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .irl: "IRL"
        case .game: "Games"
        case .entertainment: "Entertainment"
        }
    }
}

enum GameSubCategory: String, Codable, CaseIterable, Identifiable {
    case genshinImpact = "Genshin Impact"
    case honkaiStarRail = "Honkai Star Rail"
    case wutheringWaves = "Wuthering Waves"
    case other = "Other"

    var id: String { rawValue }

    var supportsRecurrence: Bool {
        self != .other
    }

    var supportsNotifications: Bool {
        self != .other
    }

    var defaultCompletable: Bool {
        self != .other
    }
}

enum EntertainmentSubCategory: String, Codable, CaseIterable, Identifiable {
    case anime = "Anime"
    case manga = "Manga"
    case manhwa = "Manhwa"
    case book = "Book"
    case show = "Show"

    var id: String { rawValue }

    var defaultUnitLabel: String {
        switch self {
        case .anime, .show: "episode"
        case .manga, .manhwa: "chapter"
        case .book: "page"
        }
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case everyNMonths

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .everyNMonths: "Every N Months"
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

enum NotificationTriggerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixedTime
    case relativeToStart
    case ifNotCompletedBy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixedTime: "Fixed Time"
        case .relativeToStart: "Relative to Start"
        case .ifNotCompletedBy: "If Not Completed By"
        }
    }

    var helpText: String {
        switch self {
        case .fixedTime:
            "Fires at a set clock time on each occurrence day."
        case .relativeToStart:
            "Fires a number of minutes before or after the entry start time."
        case .ifNotCompletedBy:
            "Fires at the chosen time only if that day's occurrence is still incomplete."
        }
    }
}
