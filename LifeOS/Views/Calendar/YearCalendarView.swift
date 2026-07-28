import SwiftUI

struct YearCalendarView: View {
    let date: Date
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    var onSelectMonth: (Date) -> Void

    private var calendar: Calendar { .current }

    private var yearOccurrences: [CalendarEntryOccurrence] {
        entryStore.occurrences(for: entries, in: DateFormatting.yearInterval(containing: date))
    }

    private var occurrencesByMonth: [Int: [CalendarEntryOccurrence]] {
        CalendarGridSupport.groupByMonth(yearOccurrences, calendar: calendar)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    /// Fixed mini-cell size keeps every month card the same height (7×6).
    private let cellSize: CGFloat = 16
    private let cellSpacing: CGFloat = 2

    private let legendBands: [(level: Int, label: String)] = [
        (0, "None"),
        (1, "1–2"),
        (2, "3"),
        (3, "4"),
        (4, "5"),
        (5, "6+")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            yearLegend

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...12, id: \.self) { month in
                    miniMonthCard(month)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .padding(.bottom, 8)
        .id(calendar.component(.year, from: date))
    }

    private var yearLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity by day")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(LifeOSTheme.softText)

            HStack(spacing: 8) {
                ForEach(legendBands, id: \.level) { band in
                    legendSwatch(level: band.level, label: band.label)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
    }

    private func legendSwatch(level: Int, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CalendarGridSupport.yearDayFill(count: CalendarGridSupport.representativeCount(forHeatLevel: level)))
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(LifeOSTheme.softText)
        }
    }

    private func miniMonthCard(_ month: Int) -> some View {
        let monthDate = CalendarGridSupport.dateForMonth(month, inYearOf: date, calendar: calendar)
        let monthItems = occurrencesByMonth[month] ?? []
        let byDay = CalendarGridSupport.groupByDay(monthItems, calendar: calendar)
        let isCurrent = calendar.isDate(monthDate, equalTo: Date(), toGranularity: .month)
        let isFocused = calendar.isDate(monthDate, equalTo: date, toGranularity: .month)
        let title = CalendarGridSupport.monthTitle(monthDate, calendar: calendar)
        let cells = CalendarGridSupport.monthGridCells(for: monthDate, calendar: calendar, fixedWeeks: true)
        let weekdaySymbols = CalendarGridSupport.orderedWeekdaySymbols(calendar: calendar)
        let activeDays = byDay.filter { !$0.value.isEmpty }.count

        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                onSelectMonth(monthDate)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 4)
                    Text("\(monthItems.count)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(monthItems.isEmpty ? LifeOSTheme.softText : LifeOSTheme.accent)
                        .contentTransition(.numericText())
                }

                Text(monthItems.isEmpty ? "Quiet month" : "\(activeDays)d active")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText.opacity(0.85))

                VStack(spacing: cellSpacing) {
                    HStack(spacing: cellSpacing) {
                        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                            Text(String(symbol.prefix(1)))
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(LifeOSTheme.softText.opacity(0.55))
                                .frame(width: cellSize, height: 10)
                        }
                    }

                    ForEach(0..<6, id: \.self) { week in
                        HStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { weekday in
                                let index = week * 7 + weekday
                                miniDayCell(
                                    day: cells.indices.contains(index) ? cells[index] : nil,
                                    byDay: byDay
                                )
                            }
                        }
                    }
                }
                .frame(width: cellSize * 7 + cellSpacing * 6, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
            .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isCurrent
                            ? LifeOSTheme.accent.opacity(0.65)
                            : (isFocused ? LifeOSTheme.accent.opacity(0.28) : LifeOSTheme.stroke),
                        lineWidth: isCurrent ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text("\(title), \(monthItems.count) entries across \(activeDays) days")
        )
        .accessibilityHint(Text("Opens month view"))
    }

    @ViewBuilder
    private func miniDayCell(
        day: Date?,
        byDay: [Date: [CalendarEntryOccurrence]]
    ) -> some View {
        if let day {
            let dayStart = calendar.startOfDay(for: day)
            let count = byDay[dayStart]?.count ?? 0
            let level = CalendarGridSupport.heatLevel(count: count)
            let isToday = calendar.isDateInToday(day)
            let dayLabel = DateFormatting.dayNumber.string(from: day)
            let fill = CalendarGridSupport.yearDayFill(count: count)

            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill)

                if level >= 5 {
                    Text(count > 9 ? "9+" : "\(count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(LifeOSTheme.canvas.opacity(0.95))
                } else if level > 0 {
                    Text(dayLabel)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(level >= 4 ? LifeOSTheme.canvas.opacity(0.9) : .white.opacity(0.95))
                } else {
                    Text(dayLabel)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(LifeOSTheme.softText.opacity(0.55))
                }
            }
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(LifeOSTheme.accent, lineWidth: 1.25)
                }
            }
            .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.clear)
                .frame(width: cellSize, height: cellSize)
                .accessibilityHidden(true)
        }
    }
}
