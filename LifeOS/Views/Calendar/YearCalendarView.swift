import SwiftUI

struct YearCalendarView: View {
    let date: Date
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    var onSelectMonth: (Date) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(1...12, id: \.self) { month in
                monthCard(month)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .padding(.bottom, 8)
    }

    private func monthCard(_ month: Int) -> some View {
        let monthDate = dateForMonth(month)
        let count = entryStore.occurrences(
            for: entries,
            in: DateFormatting.monthInterval(containing: monthDate)
        ).count
        let title = monthName(month)
        let isCurrent = Calendar.current.isDate(monthDate, equalTo: Date(), toGranularity: .month)

        return Button {
            onSelectMonth(monthDate)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(count)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(count > 0 ? LifeOSTheme.accent : LifeOSTheme.softText)

                Text(count == 1 ? "entry" : "entries")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCurrent ? LifeOSTheme.accent.opacity(0.55) : LifeOSTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: dateForMonth(month))
    }

    private func dateForMonth(_ month: Int) -> Date {
        var components = DateComponents()
        components.month = month
        components.day = 1
        components.year = Calendar.current.component(.year, from: date)
        return Calendar.current.date(from: components) ?? date
    }
}
