import Foundation
import SwiftData

@Model
final class EntryProgress {
    var currentUnit: Int
    var totalUnits: Int?
    var unitLabel: String

    @Relationship(inverse: \Entry.progress)
    var entry: Entry?

    init(currentUnit: Int = 0, totalUnits: Int? = nil, unitLabel: String = "episode") {
        self.currentUnit = currentUnit
        self.totalUnits = totalUnits
        self.unitLabel = unitLabel
    }
}
