import SwiftUI
import SwiftData

struct OngoingEventsView: View {
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore

    @Environment(\.modelContext) private var modelContext
    @StateObject private var filters = CalendarFilterState()
    @State private var showFilters = false
    @State private var showRecentlyEnded = false
    @State private var selectedOccurrence: CalendarEntryOccurrence?
    @State private var grouped = EventWindowPolicy.GroupedWindows(active: [], upcoming: [], recentlyEnded: [])

    private var filteredEntries: [Entry] {
        filters.filter(entries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if showFilters {
                    CalendarFilterBar(filters: filters)
                        .padding(.horizontal, 20)
                }

                if grouped.totalVisible == 0 && grouped.recentlyEnded.isEmpty {
                    emptyState
                } else {
                    windowSections
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(LifeOSTheme.canvas.ignoresSafeArea())
        .onAppear { recompute() }
        .onChange(of: entries) { _, _ in recompute() }
        .onChange(of: entryStore.dataVersion) { _, _ in recompute() }
        .onChange(of: filters.signature) { _, _ in recompute() }
        .sheet(item: $selectedOccurrence) { occurrence in
            EntryDetailView(entry: occurrence.entry, occurrenceDate: occurrence.occurrenceDate)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ongoing Events")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) { showFilters.toggle() }
            } label: {
                Image(systemName: showFilters || filters.isActive ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .background(LifeOSTheme.elevated, in: Circle())
                    .overlay(Circle().stroke(LifeOSTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search and filter")
        }
        .padding(.horizontal, 20)
    }

    private var subtitle: String {
        var parts: [String] = []
        if grouped.activeCount > 0 {
            parts.append("\(grouped.activeCount) active")
        }
        if grouped.upcomingCount > 0 {
            parts.append("\(grouped.upcomingCount) starting soon")
        }
        if parts.isEmpty {
            return filters.isActive ? "No windows match filters" : "Events longer than a day appear here"
        }
        if filters.isActive { parts.append("filtered") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var windowSections: some View {
        if !grouped.active.isEmpty {
            section(title: "ACTIVE NOW", windows: grouped.active)
        }

        if !grouped.upcoming.isEmpty {
            section(title: "STARTING SOON", windows: grouped.upcoming)
        }

        if !grouped.recentlyEnded.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showRecentlyEnded.toggle() }
                } label: {
                    HStack {
                        Text("RECENTLY ENDED")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(LifeOSTheme.softText)
                            .tracking(1.2)
                        Spacer()
                        Image(systemName: showRecentlyEnded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LifeOSTheme.softText)
                    }
                }
                .buttonStyle(.plain)

                if showRecentlyEnded {
                    ForEach(grouped.recentlyEnded) { window in
                        OngoingEventRowView(window: window) {
                            open(window)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func section(title: String, windows: [EventWindow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(LifeOSTheme.accent)
                .tracking(1.2)
                .padding(.horizontal, 20)

            ForEach(windows) { window in
                OngoingEventRowView(window: window) {
                    open(window)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No ongoing events")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
            Text("Create an entry with a duration over 24 hours. It will show its full date range here while the calendar keeps only the start date.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(LifeOSTheme.softText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func recompute() {
        grouped = EventWindowEngine.groupedWindows(from: filteredEntries)
    }

    private func open(_ window: EventWindow) {
        selectedOccurrence = CalendarEntryOccurrence(
            entry: window.entry,
            occurrenceDate: window.entry.startDate
        )
    }
}
