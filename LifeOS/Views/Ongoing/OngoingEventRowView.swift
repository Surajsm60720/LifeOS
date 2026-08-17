import SwiftUI

struct OngoingEventRowView: View {
    let window: EventWindow
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(rowAccent)
                        .frame(width: 4)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(window.entry.title)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Text(subtitle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(LifeOSTheme.softText)

                        Text(DateFormatting.formatDateRange(start: window.startDate, end: window.endDate))
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer(minLength: 8)

                    Text(statusBadge)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(LifeOSTheme.canvas)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(badgeColor, in: Capsule())
                }

                if window.status != .recentlyEnded {
                    ProgressView(value: window.progress)
                        .tint(LifeOSTheme.accent)
                }
            }
            .padding(14)
            .background(LifeOSTheme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(LifeOSTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var rowAccent: Color {
        if window.entry.category == .game {
            return GameIdentity.accent(for: window.entry.gameSubCategory)
        }
        return window.entry.displayColor
    }

    private var subtitle: String {
        var parts = [window.entry.category.displayName]
        if let sub = window.entry.subCategory {
            parts.append(sub)
        }
        if let eventType = window.entry.eventType {
            parts.append(eventType.displayName)
        }
        if let periodCaption = window.periodCaption {
            parts.append(periodCaption)
        }
        return parts.joined(separator: " · ")
    }

    private var statusBadge: String {
        if window.isPeriodComplete {
            return "Done"
        }
        switch window.status {
        case .active:
            if window.daysRemaining == 0 { return "Last day" }
            if window.daysRemaining == 1 { return "1 day left" }
            return "\(window.daysRemaining) days left"
        case .upcoming:
            if window.daysRemaining == 0 { return "Starts today" }
            if window.daysRemaining == 1 { return "Starts tomorrow" }
            return "Starts in \(window.daysRemaining)d"
        case .recentlyEnded:
            return "Ended"
        }
    }

    private var badgeColor: Color {
        if window.isPeriodComplete {
            return Color.green.opacity(0.85)
        }
        switch window.status {
        case .active:
            return window.daysRemaining <= 3 ? Color.orange.opacity(0.9) : LifeOSTheme.accent
        case .upcoming:
            return LifeOSTheme.accent.opacity(0.75)
        case .recentlyEnded:
            return LifeOSTheme.softText.opacity(0.5)
        }
    }
}
