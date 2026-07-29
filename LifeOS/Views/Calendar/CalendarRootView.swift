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
    /// Supplied by `ContentView` rather than queried again here. `TabView` keeps every
    /// tab root alive, so a private `@Query` per tab meant one mutation triggered
    /// several independent full-table fetches.
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    @StateObject private var filters = CalendarFilterState()

    @AppStorage(CalendarViewMode.defaultStorageKey) private var defaultModeRaw: String = CalendarViewMode.day.rawValue
    @State private var mode: CalendarViewMode = .day
    @State private var anchorDate = Date()
    @State private var selectedOccurrence: CalendarEntryOccurrence?
    @State private var showFilters = false
    @State private var didApplyStoredDefault = false
    @State private var subtitleCount = 0

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

            switch mode {
            case .day:
                DayCalendarView(date: anchorDate, entries: filteredEntries, entryStore: entryStore) {
                    calendarListHeader
                }
            case .week:
                WeekCalendarView(date: anchorDate, entries: filteredEntries, entryStore: entryStore) {
                    calendarListHeader
                }
            case .month, .year:
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        calendarListHeader
                            .padding(.horizontal, 20)

                        calendarBody
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(LifeOSTheme.canvas.ignoresSafeArea())
        .sheet(item: $selectedOccurrence) { occurrence in
            EntryDetailView(entry: occurrence.entry, occurrenceDate: occurrence.occurrenceDate)
        }
        .onAppear {
            applyStoredDefaultIfNeeded()
            recomputeSubtitleCount()
        }
        .onChange(of: defaultModeRaw) { _, newValue in
            if let preferred = CalendarViewMode(rawValue: newValue), preferred != mode {
                mode = preferred
            }
        }
        .onChange(of: mode) { _, _ in recomputeSubtitleCount() }
        .onChange(of: anchorDate) { _, _ in recomputeSubtitleCount() }
        .onChange(of: entries) { _, _ in recomputeSubtitleCount() }
        .onChange(of: entryStore.dataVersion) { _, _ in recomputeSubtitleCount() }
        .onChange(of: filters.signature) { _, _ in recomputeSubtitleCount() }
    }

    @ViewBuilder
    private var calendarListHeader: some View {
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

            if showFilters {
                CalendarFilterBar(filters: filters)
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
        case .day, .week:
            EmptyView()
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
                    chromeButton(
                        systemName: showFilters || filters.isActive
                            ? "magnifyingglass.circle.fill"
                            : "magnifyingglass.circle",
                        accessibilityLabel: "Search and filter"
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) { showFilters.toggle() }
                    }
                    chromeButton(systemName: "chevron.left", accessibilityLabel: "Previous") { shift(-1) }
                    chromeButton(systemName: "chevron.right", accessibilityLabel: "Next") { shift(1) }
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
            return (subtitleCount == 0 ? "Clear day" : "\(subtitleCount) on the books") + suffix
        case .week:
            return "\(subtitleCount) across the week" + suffix
        case .month:
            return "\(subtitleCount) this month" + suffix
        case .year:
            return "\(subtitleCount) across the year" + suffix
        }
    }

    /// Recomputed only when the inputs change. Reading this from `body` as a computed
    /// property meant a full expansion of the library on every render, on top of the
    /// identical one the visible mode view was already doing.
    private func recomputeSubtitleCount() {
        let interval: DateInterval
        switch mode {
        case .day: interval = DateInterval(start: DateFormatting.startOfDay(anchorDate), duration: 86_400)
        case .week: interval = DateFormatting.weekInterval(containing: anchorDate)
        case .month: interval = DateFormatting.monthInterval(containing: anchorDate)
        case .year: interval = DateFormatting.yearInterval(containing: anchorDate)
        }
        subtitleCount = entryStore.occurrenceCount(for: filteredEntries, in: interval)
    }

    private func chromeButton(
        systemName: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(LifeOSTheme.elevated, in: Circle())
                .overlay(Circle().stroke(LifeOSTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemName)
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
