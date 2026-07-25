import SwiftUI

struct DayCalendarView: View {
    let date: Date
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    var embedded: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var selectedOccurrence: CalendarEntryOccurrence?

    private var occurrences: [CalendarEntryOccurrence] {
        let interval = DateInterval(start: DateFormatting.startOfDay(date), duration: 86_400)
        return entryStore.occurrences(for: entries, in: interval)
    }

    var body: some View {
        Group {
            if embedded {
                contentStack
            } else {
                ScrollView { contentStack }
            }
        }
        .sheet(item: $selectedOccurrence) { occurrence in
            EntryDetailView(entry: occurrence.entry, occurrenceDate: occurrence.occurrenceDate)
        }
    }

    private var contentStack: some View {
        LazyVStack(spacing: 10) {
            if occurrences.isEmpty {
                emptyState
                    .padding(.top, embedded ? 12 : 48)
            } else {
                ForEach(occurrences) { occurrence in
                    row(for: occurrence)
                        .padding(.horizontal, 20)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.bottom, embedded ? 0 : 24)
    }

    private func row(for occurrence: CalendarEntryOccurrence) -> some View {
        EntryRowView(
            occurrence: occurrence,
            isCompleted: occurrence.entry.isCompleted(on: occurrence.occurrenceDate),
            onToggleComplete: occurrence.entry.isCompletable ? {
                entryStore.toggleCompletion(
                    for: occurrence.entry,
                    on: occurrence.occurrenceDate,
                    modelContext: modelContext
                )
            } : nil,
            onIncrementProgress: occurrence.entry.supportsProgress ? {
                entryStore.incrementProgress(for: occurrence.entry, modelContext: modelContext)
            } : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedOccurrence = occurrence
        }
        .entryDeleteMenu(title: occurrence.entry.title) {
            entryStore.delete(entry: occurrence.entry, modelContext: modelContext)
        }
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
