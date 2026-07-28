import SwiftUI

struct MonthCalendarView: View {
    @Binding var date: Date
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    var embedded: Bool = false
    var onSelectDay: (Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selectedOccurrence: CalendarEntryOccurrence?
    @State private var pendingDelete: CalendarEntryOccurrence?
    @State private var notCompletableMessage: String?

    private var calendar: Calendar { .current }

    private var monthInterval: DateInterval {
        DateFormatting.monthInterval(containing: date)
    }

    private var monthOccurrences: [CalendarEntryOccurrence] {
        entryStore.occurrences(for: entries, in: monthInterval)
    }

    private var occurrencesByDay: [Date: [CalendarEntryOccurrence]] {
        CalendarGridSupport.groupByDay(monthOccurrences, calendar: calendar)
    }

    private var peakDailyCount: Int {
        max(1, CalendarGridSupport.peakDailyCount(in: occurrencesByDay))
    }

    private var gridDays: [Date?] {
        CalendarGridSupport.monthGridCells(for: date, calendar: calendar)
    }

    private var selectedDayOccurrences: [CalendarEntryOccurrence] {
        let day = calendar.startOfDay(for: date)
        return occurrencesByDay[day] ?? []
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                ScrollView { content }
            }
        }
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            monthSurface
            selectedDayPanel
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, embedded ? 0 : 28)
    }

    private var monthSurface: some View {
        VStack(spacing: 12) {
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                }
            }
        }
        .padding(14)
        .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
        .id(calendar.component(.year, from: date) * 100 + calendar.component(.month, from: date))
    }

    private var weekdayHeader: some View {
        let ordered = CalendarGridSupport.orderedWeekdaySymbols(calendar: calendar)
        return HStack(spacing: 4) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(LifeOSTheme.softText.opacity(0.85))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let isSelected = calendar.isDate(day, inSameDayAs: date)
        let isToday = calendar.isDateInToday(day)
        let dayItems = occurrencesByDay[dayStart] ?? []
        let count = dayItems.count
        let completed = dayItems.filter { $0.entry.isCompletable && $0.entry.isCompleted(on: $0.occurrenceDate) }.count
        let completable = dayItems.filter(\.entry.isCompletable).count
        let heat = CalendarGridSupport.heatFill(count: count, peak: peakDailyCount)
        let categoryColors = CalendarGridSupport.categoryColors(for: dayItems)

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                date = day
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if isToday && !isSelected {
                        Circle()
                            .strokeBorder(LifeOSTheme.accent.opacity(0.7), lineWidth: 1.5)
                            .frame(width: 28, height: 28)
                    }

                    Text(DateFormatting.dayNumber.string(from: day))
                        .font(.system(.callout, design: .rounded, weight: isSelected || isToday ? .bold : .medium))
                        .foregroundStyle(isSelected ? LifeOSTheme.canvas : .white.opacity(count > 0 ? 1 : 0.72))
                        .frame(width: 28, height: 28)
                        .background {
                            if isSelected {
                                Circle().fill(LifeOSTheme.accent)
                            }
                        }
                }

                densityBar(colors: categoryColors, count: count)

                if completable > 0 {
                    Capsule()
                        .fill(LifeOSTheme.softText.opacity(0.35))
                        .frame(width: 18, height: 2)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LifeOSTheme.accent.opacity(0.9))
                                .frame(width: 18 * CGFloat(completed) / CGFloat(completable), height: 2)
                        }
                } else {
                    Color.clear.frame(height: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? LifeOSTheme.accent.opacity(0.14) : heat)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? LifeOSTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                onSelectDay(day)
            }
        )
        .accessibilityLabel(
            Text("\(DateFormatting.dayNumber.string(from: day)), \(count) entries\(completable > 0 ? ", \(completed) of \(completable) complete" : "")")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func densityBar(colors: [Color], count: Int) -> some View {
        if count == 0 {
            Color.clear.frame(height: 4)
        } else if colors.isEmpty {
            Capsule()
                .fill(LifeOSTheme.accent.opacity(0.55))
                .frame(width: 14, height: 4)
        } else {
            HStack(spacing: 2) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Capsule()
                        .fill(color)
                        .frame(width: colors.count == 1 ? 14 : 6, height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private var selectedDayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(DateFormatting.recapLine.string(from: date))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(selectedDayOccurrences.isEmpty
                         ? "Nothing scheduled"
                         : "\(selectedDayOccurrences.count) on this day")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(LifeOSTheme.softText)
                }
                Spacer()
                Button {
                    onSelectDay(date)
                } label: {
                    Text("Open day")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(LifeOSTheme.canvas)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(LifeOSTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if selectedDayOccurrences.isEmpty {
                Text("Tap another day in the grid, or long-press to jump straight into Day view.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText)
                    .padding(.vertical, 6)
            } else {
                List {
                    ForEach(selectedDayOccurrences) { occurrence in
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
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(minHeight: CGFloat(selectedDayOccurrences.count) * 84)
                .padding(.horizontal, -4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
    }
}
