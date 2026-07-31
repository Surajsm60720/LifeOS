import SwiftUI

struct OngoingEventsTeaserView: View {
    let entries: [Entry]
    var onOpenOngoing: () -> Void

    @State private var grouped = EventWindowPolicy.GroupedWindows(active: [], upcoming: [], recentlyEnded: [])

    var body: some View {
        if grouped.totalVisible > 0 {
            Button(action: onOpenOngoing) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ONGOING")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .foregroundStyle(LifeOSTheme.accent)
                                .tracking(1.2)
                            Text(teaserLine)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LifeOSTheme.accent)
                    }

                    if let nextEnding = grouped.active.first {
                        Text("\(nextEnding.entry.title) · \(endingLabel(for: nextEnding))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(LifeOSTheme.softText)
                            .lineLimit(1)
                    }
                }
                .padding(14)
                .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(LifeOSTheme.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onAppear { recompute() }
            .onChange(of: entries) { _, _ in recompute() }
        }
    }

    private var teaserLine: String {
        var parts: [String] = []
        if grouped.activeCount > 0 {
            parts.append("\(grouped.activeCount) active")
        }
        if grouped.upcomingCount > 0 {
            parts.append("\(grouped.upcomingCount) starting soon")
        }
        return parts.joined(separator: " · ")
    }

    private func endingLabel(for window: EventWindow) -> String {
        if window.daysRemaining == 0 { return "ends today" }
        if window.daysRemaining == 1 { return "ends tomorrow" }
        return "ends in \(window.daysRemaining) days"
    }

    private func recompute() {
        grouped = EventWindowEngine.groupedWindows(from: entries)
    }
}
