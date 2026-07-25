import SwiftUI
import SwiftData

struct EntryLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.startDate, order: .reverse) private var entries: [Entry]
    @StateObject private var entryStore = EntryStore()
    @State private var selected: Entry?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "tray",
                        description: Text("Create entries from Calendar or Templates.")
                    )
                } else {
                    ForEach(entries) { entry in
                        Button {
                            selected = entry
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(entry.displayColor)
                                    .frame(width: 4, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .foregroundStyle(.primary)
                                    Text(entry.category.displayName + (entry.subCategory.map { " · \($0)" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                entryStore.delete(entry: entry, modelContext: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            entryStore.delete(entry: entries[index], modelContext: modelContext)
                        }
                    }
                }
            }
            .navigationTitle("All Entries")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .disabled(entries.isEmpty)
                }
            }
            .sheet(item: $selected) { entry in
                EntryDetailView(entry: entry, occurrenceDate: entry.startDate)
            }
        }
    }
}
