import SwiftUI
import SwiftData

struct PityCountersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PityTracker.sortOrder) private var trackers: [PityTracker]

    @State private var undoByID: [UUID: PitySnapshot] = [:]
    @State private var showingEditor = false
    @State private var editingTracker: PityTracker?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if trackers.isEmpty {
                        emptyState
                    } else {
                        ForEach(GameSubCategory.gachaGames) { game in
                            let items = trackers.filter { $0.game == game }
                            if !items.isEmpty {
                                gameSection(game, items)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(LifeOSTheme.canvas)
            .navigationTitle("Pity Counters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add Banner", systemImage: "plus") {
                            showingEditor = true
                        }
                        Button("Restore Missing Presets", systemImage: "arrow.clockwise") {
                            PityCatalog.seedMissing(modelContext: modelContext)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Pity options")
                }
            }
            .sheet(isPresented: $showingEditor) {
                PityBannerEditorView(mode: .create)
            }
            .sheet(item: $editingTracker) { tracker in
                PityBannerEditorView(mode: .edit(tracker))
            }
            .onAppear {
                PityCatalog.seedIfEmpty(modelContext: modelContext)
            }
        }
        .tint(LifeOSTheme.accent)
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No banners yet")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
            Text("Restore the official Genshin, Star Rail, and WuWa banners, or add your own type.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(LifeOSTheme.softText)
            Button("Restore Presets") {
                PityCatalog.seedMissing(modelContext: modelContext)
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
    }

    private func gameSection(_ game: GameSubCategory, _ items: [PityTracker]) -> some View {
        let ordered = items.sorted { $0.sortOrder < $1.sortOrder }
        return VStack(alignment: .leading, spacing: 10) {
            Text(game.rawValue.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(GameIdentity.accent(for: game))

            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, tracker in
                PityTrackerCard(
                    tracker: tracker,
                    canUndo: undoByID[tracker.id] != nil,
                    canMoveUp: index > 0,
                    canMoveDown: index < ordered.count - 1,
                    onApply: { apply(tracker, $0) },
                    onUndo: { undo(tracker) },
                    onEdit: { editingTracker = tracker },
                    onDelete: { delete(tracker) },
                    onMoveUp: { move(tracker, in: ordered, by: -1) },
                    onMoveDown: { move(tracker, in: ordered, by: 1) },
                    onRecordDrop: { recordDrop(on: tracker, name: $0, pity: $1, featured: $2) }
                )
            }
        }
    }

    private func apply(_ tracker: PityTracker, _ next: PitySnapshot) {
        undoByID[tracker.id] = tracker.snapshot
        tracker.apply(next)
        try? modelContext.save()
    }

    private func undo(_ tracker: PityTracker) {
        guard let previous = undoByID.removeValue(forKey: tracker.id) else { return }
        tracker.apply(previous)
        try? modelContext.save()
    }

    private func delete(_ tracker: PityTracker) {
        undoByID[tracker.id] = nil
        modelContext.delete(tracker)
        try? modelContext.save()
    }

    private func move(_ tracker: PityTracker, in ordered: [PityTracker], by offset: Int) {
        guard let index = ordered.firstIndex(where: { $0.id == tracker.id }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        let currentOrder = tracker.sortOrder
        tracker.sortOrder = ordered[target].sortOrder
        ordered[target].sortOrder = currentOrder
        tracker.updatedAt = .now
        ordered[target].updatedAt = .now
        try? modelContext.save()
    }

    private func recordDrop(on tracker: PityTracker, name: String?, pity: Int, featured: Bool) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tracker.lastDropName = trimmed.isEmpty ? nil : trimmed
        tracker.lastDropPity = pity
        tracker.lastDropAt = .now
        tracker.lastDropWasFeatured = featured
        tracker.updatedAt = .now
        try? modelContext.save()
    }
}
