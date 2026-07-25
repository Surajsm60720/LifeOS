import Foundation
import SwiftUI
import Combine

@MainActor
final class CalendarFilterState: ObservableObject {
    @Published var searchText: String = ""
    @Published var categoryFilter: EntryCategory? = nil
    @Published var gameFilter: GameSubCategory? = nil
    @Published var entertainmentFilter: EntertainmentSubCategory? = nil

    var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || categoryFilter != nil
            || gameFilter != nil
            || entertainmentFilter != nil
    }

    func clear() {
        searchText = ""
        categoryFilter = nil
        gameFilter = nil
        entertainmentFilter = nil
    }

    func matches(_ entry: Entry) -> Bool {
        if let categoryFilter, entry.category != categoryFilter {
            return false
        }
        if let gameFilter {
            guard entry.category == .game, entry.gameSubCategory == gameFilter else { return false }
        }
        if let entertainmentFilter {
            guard entry.category == .entertainment, entry.entertainmentSubCategory == entertainmentFilter else {
                return false
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = [entry.title, entry.notes ?? "", entry.subCategory ?? "", entry.location ?? ""]
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(query.lowercased())
    }

    func filter(_ entries: [Entry]) -> [Entry] {
        entries.filter(matches)
    }
}
