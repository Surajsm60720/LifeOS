import Foundation
import SwiftData

@Model
final class LocationEntry {
    var name: String
    var latitude: Double?
    var longitude: Double?

    @Relationship(inverse: \Entry.locations)
    var entry: Entry?

    init(name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }
}
