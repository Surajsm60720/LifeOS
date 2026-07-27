import Foundation

#if canImport(AppIntents)
import AppIntents
#endif

enum LiveActivityScope: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

#if canImport(AppIntents)
extension LiveActivityScope: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar Scope"

    static let caseDisplayRepresentations: [LiveActivityScope: DisplayRepresentation] = [
        .day: DisplayRepresentation(title: "Day", image: .init(systemName: "calendar")),
        .week: DisplayRepresentation(title: "Week", image: .init(systemName: "calendar.badge.clock")),
        .month: DisplayRepresentation(title: "Month", image: .init(systemName: "calendar.month")),
        .year: DisplayRepresentation(title: "Year", image: .init(systemName: "calendar.circle")),
    ]
}
#endif

