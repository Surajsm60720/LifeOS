import SwiftUI
import SwiftData

struct TodayInboxView: View {
    let entries: [Entry]
    @ObservedObject var entryStore: EntryStore
    var onOpenOccurrence: (CalendarEntryOccurrence) -> Void
    var onJumpToToday: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var upcomingReminders: [String] = []

    private var todayOpen: [CalendarEntryOccurrence] {
        let interval = DateInterval(start: DateFormatting.startOfDay(.now), duration: 86_400)
        return entryStore.occurrences(for: entries, in: interval)
            .filter { $0.entry.isCompletable && !$0.entry.isCompleted(on: $0.occurrenceDate) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(LifeOSTheme.accent)
                        .tracking(1.2)
                    Text(summaryLine)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button("Open day", action: onJumpToToday)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LifeOSTheme.accent)
            }

            if todayOpen.isEmpty {
                Text("All clear — nothing completable left today.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(LifeOSTheme.softText)
            } else {
                ForEach(todayOpen.prefix(4)) { occurrence in
                    HStack(spacing: 10) {
                        Button {
                            entryStore.toggleCompletion(
                                for: occurrence.entry,
                                on: occurrence.occurrenceDate,
                                modelContext: modelContext
                            )
                        } label: {
                            Image(systemName: "circle")
                                .foregroundStyle(LifeOSTheme.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onOpenOccurrence(occurrence)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(occurrence.entry.displayColor)
                                    .frame(width: 8, height: 8)
                                Text(occurrence.entry.title)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .entryDeleteMenu(title: occurrence.entry.title) {
                        entryStore.delete(entry: occurrence.entry, modelContext: modelContext)
                    }
                }

                if todayOpen.count > 4 {
                    Text("+\(todayOpen.count - 4) more")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(LifeOSTheme.softText)
                }
            }

            if !upcomingReminders.isEmpty {
                Divider().overlay(LifeOSTheme.stroke)
                Text("Up next")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(LifeOSTheme.softText)
                ForEach(upcomingReminders.prefix(2), id: \.self) { line in
                    Text(line)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(LifeOSTheme.softText)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LifeOSTheme.stroke, lineWidth: 1)
        )
        .task {
            upcomingReminders = await NotificationPlanner.shared.pendingManagedSummaries()
        }
    }

    private var summaryLine: String {
        let n = todayOpen.count
        if n == 0 { return "Inbox clear" }
        if n == 1 { return "1 item still open" }
        return "\(n) items still open"
    }
}
