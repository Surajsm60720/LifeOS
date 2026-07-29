import SwiftUI

struct CalendarFilterBar: View {
    @ObservedObject var filters: CalendarFilterState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Search & Filter", systemImage: "magnifyingglass")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                if filters.isActive {
                    Button("Clear all") { filters.clear() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LifeOSTheme.accent)
                }
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LifeOSTheme.softText)
                TextField("Search titles, notes, places…", text: $filters.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Filter by category")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(LifeOSTheme.softText)

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
        .padding(14)
        .background(LifeOSTheme.elevated.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
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
