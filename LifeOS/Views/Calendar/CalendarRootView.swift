import SwiftUI
import SwiftData

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    static let defaultStorageKey = "calendarDefaultMode"
}

struct CalendarRootView: View {
    @Query(sort: \Entry.startDate) private var entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    @StateObject private var filters = CalendarFilterState()

    @AppStorage(CalendarViewMode.defaultStorageKey) private var defaultModeRaw: String = CalendarViewMode.day.rawValue
    @State private var mode: CalendarViewMode = .day
    @State private var anchorDate = Date()
    @State private var selectedOccurrence: CalendarEntryOccurrence?
    @State private var showFilters = false
    @State private var didApplyStoredDefault = false

    private var filteredEntries: [Entry] {
        filters.filter(entries)
    }

    private var headerTitle: String {
        switch mode {
        case .day:
            return DateFormatting.recapLine.string(from: anchorDate)
        case .week:
            let interval = DateFormatting.weekInterval(containing: anchorDate)
            let start = DateFormatting.dayNumber.string(from: interval.start)
            let end = DateFormatting.recapLine.string(
                from: Calendar.current.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
            )
            return "Week of \(start) – \(end)"
        case .month, .year:
            return DateFormatting.monthYear.string(from: anchorDate)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            calendarChrome

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TodayInboxView(
                        entries: filteredEntries,
                        entryStore: entryStore,
                        onOpenOccurrence: { selectedOccurrence = $0 },
                        onJumpToToday: {
                            withAnimation(.easeOut(duration: 0.25)) {
                                anchorDate = .now
                                mode = .day
                            }
                        }
                    )
                    .padding(.horizontal, 20)

                    if showFilters {
                        CalendarFilterBar(filters: filters)
                            .padding(.horizontal, 20)
                    }

                    calendarBody
                }
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .background(LifeOSTheme.canvas.ignoresSafeArea())
        .sheet(item: $selectedOccurrence) { occurrence in
            EntryDetailView(entry: occurrence.entry, occurrenceDate: occurrence.occurrenceDate)
        }
        .onAppear {
            applyStoredDefaultIfNeeded()
        }
        .onChange(of: defaultModeRaw) { _, newValue in
            // Honor Settings changes while Calendar is already open.
            if let preferred = CalendarViewMode(rawValue: newValue), preferred != mode {
                mode = preferred
            }
        }
    }

    private func applyStoredDefaultIfNeeded() {
        guard !didApplyStoredDefault else { return }
        didApplyStoredDefault = true
        if let preferred = CalendarViewMode(rawValue: defaultModeRaw) {
            mode = preferred
        } else {
            mode = .day
        }
    }

    @ViewBuilder
    private var calendarBody: some View {
        switch mode {
        case .day:
            DayCalendarView(date: anchorDate, entries: filteredEntries, entryStore: entryStore, embedded: true)
        case .week:
            WeekCalendarView(date: anchorDate, entries: filteredEntries, entryStore: entryStore, embedded: true)
        case .month:
            MonthCalendarView(
                date: $anchorDate,
                entries: filteredEntries,
                entryStore: entryStore,
                embedded: true,
                onSelectDay: { day in
                    withAnimation(.easeOut(duration: 0.25)) {
                        anchorDate = day
                        mode = .day
                    }
                }
            )
        case .year:
            YearCalendarView(
                date: anchorDate,
                entries: filteredEntries,
                entryStore: entryStore,
                onSelectMonth: { monthDate in
                    withAnimation(.easeOut(duration: 0.25)) {
                        anchorDate = monthDate
                        mode = .month
                    }
                }
            )
        }
    }

    private var calendarChrome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode == .year
                         ? String(Calendar.current.component(.year, from: anchorDate))
                         : headerTitle)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(LifeOSTheme.softText)
                }

                Spacer()

                HStack(spacing: 8) {
                    chromeButton(systemName: showFilters || filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                        withAnimation(.easeOut(duration: 0.2)) { showFilters.toggle() }
                    }
                    chromeButton(systemName: "chevron.left") { shift(-1) }
                    chromeButton(systemName: "chevron.right") { shift(1) }
                }
            }

            Picker("View", selection: $mode) {
                ForEach(CalendarViewMode.allCases) { viewMode in
                    Text(viewMode.title).tag(viewMode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        let suffix = filters.isActive ? " · filtered" : ""
        switch mode {
        case .day:
            let interval = DateInterval(start: DateFormatting.startOfDay(anchorDate), duration: 86_400)
            let count = entryStore.occurrences(for: filteredEntries, in: interval).count
            return (count == 0 ? "Clear day" : "\(count) on the books") + suffix
        case .week:
            let count = entryStore.occurrences(for: filteredEntries, in: DateFormatting.weekInterval(containing: anchorDate)).count
            return "\(count) across the week" + suffix
        case .month:
            let count = entryStore.occurrences(for: filteredEntries, in: DateFormatting.monthInterval(containing: anchorDate)).count
            return "\(count) this month" + suffix
        case .year:
            return "\(filteredEntries.count) entries tracked" + suffix
        }
    }

    private func chromeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(LifeOSTheme.elevated, in: Circle())
                .overlay(Circle().stroke(LifeOSTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func shift(_ direction: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            switch mode {
            case .day:
                anchorDate = Calendar.current.date(byAdding: .day, value: direction, to: anchorDate) ?? anchorDate
            case .week:
                anchorDate = Calendar.current.date(byAdding: .weekOfYear, value: direction, to: anchorDate) ?? anchorDate
            case .month:
                anchorDate = Calendar.current.date(byAdding: .month, value: direction, to: anchorDate) ?? anchorDate
            case .year:
                anchorDate = Calendar.current.date(byAdding: .year, value: direction, to: anchorDate) ?? anchorDate
            }
        }
    }
}
