import SwiftUI

struct WeekCalendarView<Leading: View>: View {
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

    private var weekInterval: DateInterval {
        DateFormatting.weekInterval(containing: date)
    }

    private var days: [Date] {
        var result: [Date] = []
        var cursor = weekInterval.start
        while cursor < weekInterval.end {
            result.append(cursor)
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Expand the whole week once and bucket by day, the way Month and Year already
    /// do. Expanding per day re-scanned the entire entry list seven times per render.
    private var occurrencesByDay: [Date: [CalendarEntryOccurrence]] {
        CalendarGridSupport.groupByDay(
            entryStore.occurrences(for: entries, in: weekInterval)
        )
    }

    var body: some View {
        List {
            Section {
                leading()
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            let grouped = occurrencesByDay
            ForEach(days, id: \.self) { day in
                daySection(day, occurrences: grouped[DateFormatting.startOfDay(day)] ?? [])
            }

            Section {
                EmptyView()
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

    @ViewBuilder
    private func daySection(_ day: Date, occurrences dayOccurrences: [CalendarEntryOccurrence]) -> some View {
        let isToday = Calendar.current.isDateInToday(day)

        Section {
            if dayOccurrences.isEmpty {
                Text("Open")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText.opacity(0.7))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(dayOccurrences) { occurrence in
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
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(DateFormatting.weekdayShort.string(from: day).uppercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(isToday ? LifeOSTheme.accent : LifeOSTheme.softText)
                    .tracking(0.8)

                Text(DateFormatting.dayNumber.string(from: day))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                if isToday {
                    Text("Today")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(LifeOSTheme.canvas)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LifeOSTheme.accent, in: Capsule())
                }

                Spacer()

                Text("\(dayOccurrences.count)")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(LifeOSTheme.softText)
            }
            .textCase(nil)
            .padding(.top, 4)
        }
    }
}
