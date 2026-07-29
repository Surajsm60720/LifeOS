import Foundation

struct LiveActivityItem: Codable, Identifiable, Hashable {
    /// Distinct even when two occurrences share a title, so `ForEach` never
    /// collapses/overlaps rows with duplicate identities.
    var id = UUID()

    let title: String
    let colorHex: String
}

