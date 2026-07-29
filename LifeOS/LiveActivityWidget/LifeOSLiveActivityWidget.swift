import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LifeOSLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeOSLiveActivityWidget()
    }
}

struct LifeOSLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LifeOSLiveActivityAttributes.self) { context in
            LockScreenContent(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("LifeOS", systemImage: "checklist")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Today")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedSummary(count: context.state.itemCount)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "checklist")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(context.state.itemCount)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
            } compactTrailing: {
                Text("Today")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            } minimal: {
                Text("\(context.state.itemCount)")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .keylineTint(LifeOSTheme.accent)
        }
    }
}

// MARK: - Shared pieces

/// The Dynamic Island's expanded (long-press) presentation has a hard, system-imposed
/// height budget (~160pt total, including the top leading/trailing row) that Apple does
/// not expose an API to override. A per-item list there is exactly what caused the
/// clipped/garbled rendering originally reported, since the row count needed to show a
/// whole day never reliably fits that budget. So the Dynamic Island shows a single,
/// large, single-line count instead — nothing that can wrap, clip, or crowd the margins.
///
/// The Lock Screen / Always-On presentation has much more vertical room, so it keeps a
/// short, real list: up to `lockScreenMaxRows` items, then a single "+N more" line.
private enum LiveActivityLayout {
    static let lockScreenMaxRows = 3
}

private struct ExpandedSummary: View {
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LifeOSTheme.accent.opacity(0.18))

                Text("\(count)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "You're all caught up" : "Remaining today")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text(summaryLine)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var summaryLine: String {
        guard count > 0 else { return "No unfinished events" }
        return count == 1 ? "1 event left" : "\(count) events left"
    }
}

private struct LockScreenContent: View {
    let state: LifeOSLiveActivityAttributes.ContentState

    private var visibleItems: [LiveActivityItem] {
        Array(state.items.prefix(LiveActivityLayout.lockScreenMaxRows))
    }

    private var overflowCount: Int {
        max(0, state.itemCount - visibleItems.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .semibold))

                Text("Today")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))

                Spacer(minLength: 8)

                Text(state.itemCount == 1 ? "1 event" : "\(state.itemCount) events")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)

            if visibleItems.isEmpty {
                Text("Nothing left for today")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(visibleItems) { item in
                        LiveActivityRow(item: item)
                    }
                }

                if overflowCount > 0 {
                    Text(overflowCount == 1 ? "+1 more event" : "+\(overflowCount) more events")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    }
}

private struct LiveActivityRow: View {
    let item: LiveActivityItem

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: item.colorHex))
                .frame(width: 7, height: 7)

            Text(item.title)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
}
