import SwiftUI

struct DayCalendarView<Leading: View>: View {
    let date: Date
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    @ViewBuilder var leading: () -> Leading

    @Environment(\.modelContext) private var modelContext
    @State private var selectedOccurrence: CalendarEntryOccurrence?
    @State private var pendingDelete: CalendarEntryOccurrence?
    @State private var notCompletableMessage: String?

    init(
        date: Date,
        entries: [Entry],
        entryStore: EntryStore,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() }
    ) {
        self.date = date
        self.entries = entries
        self.entryStore = entryStore
        self.leading = leading
    }

    private var occurrences: [CalendarEntryOccurrence] {
        let interval = DateInterval(start: DateFormatting.startOfDay(date), duration: 86_400)
        return entryStore.occurrences(for: entries, in: interval)
    }

    var body: some View {
        List {
            Section {
                leading()
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if occurrences.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(occurrences) { occurrence in
                        row(for: occurrence)
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .sheet(item: $selectedOccurrence) { occurrence in
            EntryDetailView(entry: occurrence.entry, occurrenceDate: occurrence.occurrenceDate)
        }
        .confirmationDialog(
            pendingDelete.map { "Delete “\($0.entry.title)”?" } ?? "Delete entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                if let pendingDelete {
                    entryStore.delete(entry: pendingDelete.entry, modelContext: modelContext)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This removes the entry, its recurrence, completions, and notification rules.")
        }
        .alert(
            "Can’t mark complete",
            isPresented: Binding(
                get: { notCompletableMessage != nil },
                set: { if !$0 { notCompletableMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                notCompletableMessage = nil
            }
        } message: {
            Text(notCompletableMessage ?? "")
        }
    }

    private func row(for occurrence: CalendarEntryOccurrence) -> some View {
        CalendarOccurrenceSwipeRow(
            occurrence: occurrence,
            isCompleted: occurrence.entry.isCompleted(on: occurrence.occurrenceDate),
            onOpen: { selectedOccurrence = occurrence },
            onToggleComplete: {
                entryStore.toggleCompletion(
                    for: occurrence.entry,
                    on: occurrence.occurrenceDate,
                    modelContext: modelContext
                )
            },
            onNotCompletable: {
                notCompletableMessage =
                    "“\(occurrence.entry.title)” isn’t marked completable, so it can’t be completed."
            },
            onRequestDelete: { pendingDelete = occurrence },
            onIncrementProgress: occurrence.entry.supportsProgress ? {
                entryStore.incrementProgress(for: occurrence.entry, modelContext: modelContext)
            } : nil
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing today")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
            Text("Add an entry or jump to another day.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(LifeOSTheme.softText)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
