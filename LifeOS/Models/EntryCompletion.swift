import Foundation
import SwiftData

@Model
final class EntryCompletion {
    var occurrenceStart: Date
    var completedAt: Date

    @Relationship(inverse: \Entry.completions)
    var entry: Entry?

    init(occurrenceStart: Date, completedAt: Date = .now) {
        self.occurrenceStart = occurrenceStart
        self.completedAt = completedAt
    }
}
