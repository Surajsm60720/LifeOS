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
                    ExpandedCountBadge(count: context.state.remainingCount)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.scope.title)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBody(state: context.state)
                }
            } compactLeading: {
                Text("\(context.state.remainingCount)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
            } compactTrailing: {
                Text(context.state.scope.title)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            } minimal: {
                Text("\(context.state.remainingCount)")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
            }
        }
    }
}

// MARK: - Shared pieces

private struct ExpandedCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 12, weight: .semibold))
            Text("\(count)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
    }
}

private struct ExpandedBody: View {
    let state: LifeOSLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScopePicker(active: state.scope)

            if state.items.isEmpty {
                Text(emptyLine)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(state.items.prefix(8)) { item in
                            LiveActivityRow(item: item)
                        }

                        if overflowCount > 0 {
                            Text(moreLine)
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(.top, 2)
    }

    private var overflowCount: Int {
        max(0, state.remainingCount - state.items.count)
    }

    private var emptyLine: String {
        "Nothing open for this \(state.scope.title.lowercased())."
    }

    private var moreLine: String {
        let noun = state.scope.title.lowercased()
        if overflowCount == 1 {
            return "...1 more for this \(noun) — open LifeOS"
        }
        return "...\(overflowCount) more for this \(noun) — open LifeOS"
    }
}

private struct LockScreenContent: View {
    let state: LifeOSLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(state.remainingCount) open")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer(minLength: 8)
                Text(state.scope.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ScopePicker(active: state.scope)

            if state.items.isEmpty {
                Text("Nothing open for this \(state.scope.title.lowercased()).")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(state.items.prefix(8)) { item in
                            LiveActivityRow(item: item)
                        }

                        if overflowCount > 0 {
                            Text(moreLine)
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(14)
        .activityBackgroundTint(Color.black.opacity(0.85))
    }

    private var overflowCount: Int {
        max(0, state.remainingCount - state.items.count)
    }

    private var moreLine: String {
        let noun = state.scope.title.lowercased()
        if overflowCount == 1 {
            return "...1 more for this \(noun) — open LifeOS"
        }
        return "...\(overflowCount) more for this \(noun) — open LifeOS"
    }
}

private struct ScopePicker: View {
    let active: LiveActivityScope

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LiveActivityScope.allCases) { scope in
                ScopeButton(scope: scope, active: active)
            }
        }
    }
}

private struct ScopeButton: View {
    let scope: LiveActivityScope
    let active: LiveActivityScope

    private var isActive: Bool { scope == active }

    var body: some View {
        Button(intent: SetLiveActivityScopeIntent(scope: scope)) {
            Text(scope.title)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? Color.white : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
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
                .font(.system(.caption, design: .rounded, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}
