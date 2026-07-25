import SwiftUI

struct MonthCalendarView: View {
    @Binding var date: Date
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    var embedded: Bool = false
    var onSelectDay: (Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selectedOccurrence: CalendarEntryOccurrence?

    private var calendar: Calendar { .current }

    private var monthInterval: DateInterval {
        DateFormatting.monthInterval(containing: date)
    }

    private var monthOccurrences: [CalendarEntryOccurrence] {
        entryStore.occurrences(for: entries, in: monthInterval)
    }

    private var occurrencesByDay: [Date: [CalendarEntryOccurrence]] {
        Dictionary(grouping: monthOccurrences) { occurrence in
            calendar.startOfDay(for: occurrence.occurrenceDate)
        }
    }

    private var gridDays: [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 1...daysInMonth {
            var components = calendar.dateComponents([.year, .month], from: date)
            components.day = day
            cells.append(calendar.date(from: components))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var selectedDayOccurrences: [CalendarEntryOccurrence] {
        let day = calendar.startOfDay(for: date)
        return occurrencesByDay[day] ?? []
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

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
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            weekdayHeader
            monthGrid
            selectedDayList
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, embedded ? 0 : 28)
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        let ordered = Array(symbols[calendar.firstWeekday - 1..<symbols.count] + symbols[0..<calendar.firstWeekday - 1])
        return HStack(spacing: 6) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(LifeOSTheme.softText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 48)
                }
            }
        }
        .padding(12)
        .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let isSelected = calendar.isDate(day, inSameDayAs: date)
        let isToday = calendar.isDateInToday(day)
        let dayItems = occurrencesByDay[dayStart] ?? []

        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                date = day
            }
        } label: {
            VStack(spacing: 5) {
                Text(DateFormatting.dayNumber.string(from: day))
                    .font(.system(.callout, design: .rounded, weight: isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? LifeOSTheme.canvas : .white)

                HStack(spacing: 3) {
                    ForEach(0..<min(dayItems.count, 3), id: \.self) { index in
                        Circle()
                            .fill(dotColor(for: dayItems[index].entry))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? LifeOSTheme.accent : (isToday ? LifeOSTheme.accent.opacity(0.18) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                onSelectDay(day)
            }
        )
        .accessibilityLabel(Text("\(DateFormatting.dayNumber.string(from: day)), \(dayItems.count) entries"))
    }

    private func dotColor(for entry: Entry) -> Color {
        if entry.category == .game {
            return GameIdentity.accent(for: entry.gameSubCategory)
        }
        return entry.displayColor
    }

    private var selectedDayList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DateFormatting.recapLine.string(from: date))
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Open day") {
                    onSelectDay(date)
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(LifeOSTheme.accent)
            }

            if selectedDayOccurrences.isEmpty {
                Text("No entries on this day.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText)
                    .padding(.vertical, 8)
            } else {
                ForEach(selectedDayOccurrences) { occurrence in
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
