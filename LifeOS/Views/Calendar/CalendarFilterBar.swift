import SwiftUI

struct CalendarFilterBar: View {
    @ObservedObject var filters: CalendarFilterState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LifeOSTheme.softText)
                TextField("Search titles, notes…", text: $filters.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if filters.isActive {
                    Button("Clear") { filters.clear() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LifeOSTheme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", selected: filters.categoryFilter == nil && filters.gameFilter == nil && filters.entertainmentFilter == nil) {
                        filters.categoryFilter = nil
                        filters.gameFilter = nil
                        filters.entertainmentFilter = nil
                    }
                    ForEach(EntryCategory.allCases) { category in
                        filterChip(category.displayName, selected: filters.categoryFilter == category && filters.gameFilter == nil && filters.entertainmentFilter == nil) {
                            filters.categoryFilter = category
                            filters.gameFilter = nil
                            filters.entertainmentFilter = nil
                        }
                    }
                    ForEach(GameSubCategory.allCases.filter { $0 != .other }) { game in
                        filterChip(game.rawValue, selected: filters.gameFilter == game) {
                            filters.categoryFilter = .game
                            filters.gameFilter = game
                            filters.entertainmentFilter = nil
                        }
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(selected ? LifeOSTheme.canvas : LifeOSTheme.softText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(selected ? LifeOSTheme.accent : LifeOSTheme.elevated)
                )
                .overlay(
                    Capsule().stroke(LifeOSTheme.stroke, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}
