import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Entry.startDate) private var entries: [Entry]

    @StateObject private var entryStore = EntryStore()
    @State private var showingCreateSheet = false
    @State private var selectedTab = 0

    /// Tracks the alternate-icon selection used when we last rescheduled notifications.
    @AppStorage("lastNotificationIconFingerprint") private var lastNotificationIconFingerprint: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CalendarRootView(entryStore: entryStore)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Haptics.medium()
                                showingCreateSheet = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add Entry")
                        }
                    }
                    .toolbarBackground(LifeOSTheme.canvas, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            .tag(0)

            NavigationStack {
                NotificationsHubView()
                    .toolbarBackground(LifeOSTheme.canvas, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .tabItem {
                Label("Notifications", systemImage: "bell")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
                    .toolbarBackground(LifeOSTheme.canvas, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(2)
        }
        .tint(LifeOSTheme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingCreateSheet) {
            EntryFormView(mode: .create(category: .irl))
                .tint(LifeOSTheme.accent)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshNotifications()
                Task { await LiveActivityManager.syncActiveActivity(modelContext: modelContext) }
            }
        }
        .task {
            LifeOSDataMigration.runLaunchMigrations(modelContext: modelContext, entryStore: entryStore)
            refreshNotifications()
            await LiveActivityManager.syncActiveActivity(modelContext: modelContext)
        }
    }

    private func refreshNotifications() {
        Task {
            let fingerprint = currentNotificationIconFingerprint()
            if fingerprint != lastNotificationIconFingerprint {
                lastNotificationIconFingerprint = fingerprint
                await NotificationPlanner.rescheduleManagedNotificationsForIconUpdate(entries: entries)
                return
            }
            await NotificationPlanner.refreshPendingNotifications(entries: entries)
        }
    }

    /// Notification banners use the currently selected app icon.
    /// Keying off the alternate-icon name is enough to detect Settings icon switches.
    private func currentNotificationIconFingerprint() -> String {
        UIApplication.shared.alternateIconName ?? "primary"
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
