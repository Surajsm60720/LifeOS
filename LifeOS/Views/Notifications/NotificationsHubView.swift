import SwiftUI
import SwiftData
import UIKit

struct NotificationsHubView: View {
    /// Supplied by `ContentView` so all tabs share a single `@Query`.
    let entries: [Entry]

    @Environment(\.modelContext) private var modelContext

    @State private var showingCreateSheet = false
    @State private var editingRule: NotificationRule?
    @State private var authorizationDenied = false
    @State private var pendingCount = 0
    @State private var remainingCount = 0
    @State private var firingTodayCount = 0
    @State private var pendingSummaries: [String] = []
    @State private var testStatus: String?

    private var rules: [(entry: Entry, rule: NotificationRule)] {
        entries
            .filter(\.supportsNotifications)
            .flatMap { entry in
                entry.notificationRules.map { (entry: entry, rule: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.rule.isActive != rhs.rule.isActive {
                    return lhs.rule.isActive && !rhs.rule.isActive
                }
                return lhs.entry.title.localizedCaseInsensitiveCompare(rhs.entry.title) == .orderedAscending
            }
    }

    private var eligibleEntryCount: Int {
        entries.filter(\.supportsNotifications).count
    }

    var body: some View {
        List {
            statusSection

            if rules.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Notifications Yet",
                        systemImage: "bell",
                        description: Text(emptyDescription)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)

                    Button {
                        Haptics.medium()
                        showingCreateSheet = true
                    } label: {
                        Text(eligibleEntryCount == 0 ? "Create Notification Rule" : "Add Notification Rule")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Section {
                    ForEach(rules, id: \.rule.persistentModelID) { item in
                        Button {
                            editingRule = item.rule
                        } label: {
                            NotificationRuleRow(entry: item.entry, rule: item.rule)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(rule: item.rule, from: item.entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleActive(item.rule)
                            } label: {
                                Label(
                                    item.rule.isActive ? "Disable" : "Enable",
                                    systemImage: item.rule.isActive ? "bell.slash" : "bell"
                                )
                            }
                            .tint(item.rule.isActive ? LifeOSTheme.softText : LifeOSTheme.accent)
                        }
                    }
                } header: {
                    Text("Rules")
                }
            }
        }
        .tint(LifeOSTheme.accent)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.medium()
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Notification")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            NotificationRuleFormView(mode: .create)
                .tint(LifeOSTheme.accent)
        }
        .sheet(item: $editingRule) { rule in
            NotificationRuleFormView(mode: .edit(rule))
                .tint(LifeOSTheme.accent)
        }
        .task {
            await refreshStatus()
        }
        .refreshable {
            await refreshStatus()
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            LabeledContent("System Permission") {
                Text(authorizationDenied ? "Denied" : "Allowed")
                    .foregroundStyle(authorizationDenied ? .red : .secondary)
            }
            LabeledContent("Active Rules") {
                Text("\(rules.filter(\.rule.isActive).count)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Scheduled") {
                Text("\(pendingCount)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Remaining") {
                Text("\(remainingCount)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Firing Today") {
                Text("\(firingTodayCount)")
                    .foregroundStyle(.secondary)
            }

            Button("Send Test in 5s") {
                Task {
                    let ok = await NotificationPlanner.shared.scheduleTestNotification(after: 5)
                    testStatus = ok
                        ? "Test scheduled. Home Screen icon is current; if the banner glyph still looks old, restart the device once (known iOS 18 Notification Center cache issue)."
                        : "Could not schedule test. Check permission."
                    await refreshStatus()
                }
            }

            if let testStatus {
                Text(testStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if authorizationDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Status")
        } footer: {
            Text("iOS allows \(NotificationPlanner.maxPendingNotifications) pending local notifications per app. LifeOS fills soonest-first over the next 7 days. Pull to refresh. If Scheduled stays at 0, the fire time may already be past or the entry doesn’t occur in the next 7 days.")
        }

        if !pendingSummaries.isEmpty {
            Section("Up Next") {
                ForEach(pendingSummaries.prefix(8), id: \.self) { summary in
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyDescription: String {
        if eligibleEntryCount == 0 {
            return "Add an IRL or priority-game entry first (Calendar +), then return here to attach a reminder. Entertainment and Other games cannot have notifications."
        }
        return "Tap + to create a custom reminder rule for any eligible entry."
    }

    private func toggleActive(_ rule: NotificationRule) {
        rule.isActive.toggle()
        try? modelContext.save()
        Task { await refreshStatus() }
    }

    private func delete(rule: NotificationRule, from entry: Entry) {
        entry.notificationRules.removeAll { $0.persistentModelID == rule.persistentModelID }
        modelContext.delete(rule)
        try? modelContext.save()
        Task { await refreshStatus() }
    }

    @MainActor
    private func refreshStatus() async {
        let granted = await NotificationPlanner.shared.requestAuthorizationIfNeeded()
        authorizationDenied = !granted

        await NotificationPlanner.refreshPendingNotifications(entries: entries, force: true)
        let budget = await NotificationPlanner.shared.pendingBudget()
        pendingCount = budget.scheduled
        remainingCount = budget.remaining
        firingTodayCount = budget.firingToday
        pendingSummaries = await NotificationPlanner.shared.pendingManagedSummaries()
    }
}

private struct NotificationRuleRow: View {
    let entry: Entry
    let rule: NotificationRule

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(rule.isActive ? entry.displayColor : Color.secondary.opacity(0.35))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(rule.isActive ? "On" : "Off")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(rule.isActive ? LifeOSTheme.accent : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            (rule.isActive ? LifeOSTheme.accent : Color.secondary).opacity(0.18),
                            in: Capsule()
                        )
                }

                Text(rule.triggerSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                ForEach(Array(rule.detailLines(for: entry).dropFirst().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(rule.renderedMessage(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)

                Text(entry.category.displayName + (entry.subCategory.map { " · \($0)" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
