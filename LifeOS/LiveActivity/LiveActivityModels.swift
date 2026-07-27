import Foundation

struct LiveActivityItem: Codable, Identifiable, Hashable {
    var id: String { title }

    let title: String
    let colorHex: String
}

