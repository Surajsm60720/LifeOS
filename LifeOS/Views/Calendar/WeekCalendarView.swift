import SwiftUI

struct WeekCalendarView: View {
    let date: Date
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    var embedded: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var selectedOccurrence: CalendarEntryOccurrence?

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
        LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(days, id: \.self) { day in
                daySection(day)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.bottom, embedded ? 0 : 24)
    }

    private func daySection(_ day: Date) -> some View {
        let dayOccurrences = entryStore.occurrences(
            for: entries,
            in: DateInterval(start: DateFormatting.startOfDay(day), duration: 86_400)
        )
        let isToday = Calendar.current.isDateInToday(day)

        return VStack(alignment: .leading, spacing: 10) {
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

            if dayOccurrences.isEmpty {
                Text("Open")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText.opacity(0.7))
                    .padding(.leading, 2)
            } else {
                ForEach(dayOccurrences) { occurrence in
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
            }
        }
    }
}
