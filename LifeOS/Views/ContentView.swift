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
    @State private var appLock = AppLockManager()

    /// Tracks the alternate-icon selection used when we last rescheduled notifications.
    @AppStorage("lastNotificationIconFingerprint") private var lastNotificationIconFingerprint: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CalendarRootView(
                    entries: entries,
                    entryStore: entryStore,
                    onOpenOngoing: { selectedTab = 1 }
                )
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
                OngoingEventsView(entries: entries, entryStore: entryStore)
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
                Label("Ongoing", systemImage: "hourglass")
            }
            .tag(1)

            NavigationStack {
                NotificationsHubView(entries: entries)
                    .toolbarBackground(LifeOSTheme.canvas, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .tabItem {
                Label("Notifications", systemImage: "bell")
            }
            .tag(2)

            NavigationStack {
                SettingsView(entries: entries, appLock: appLock)
                    .toolbarBackground(LifeOSTheme.canvas, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(3)
        }
        .tint(LifeOSTheme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingCreateSheet) {
            EntryFormView(mode: .create(category: .irl))
                .tint(LifeOSTheme.accent)
        }
        // Presented as a full-screen cover rather than an in-tree overlay so it also
        // covers any sheet (entry detail, backup, recap) that was open when we locked.
        .fullScreenCover(isPresented: lockPresentation) {
            AppLockScreen(appLock: appLock)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Skip data work while locked so nothing reaches the Lock Screen or
                // Dynamic Island before the owner authenticates.
                guard !appLock.isLocked else { return }
                refreshNotifications()
                Task { await LiveActivityManager.syncActiveActivity(modelContext: modelContext) }
            case .background:
                // Only on `.background`. `.inactive` also fires for the Face ID sheet,
                // Control Center, and the app switcher, which would re-lock mid-unlock.
                appLock.lockIfEnabled()
            default:
                break
            }
        }
        .onChange(of: appLock.isLocked) { _, locked in
            // Catch up on the work that was deferred while the lock screen was up.
            guard !locked else { return }
            refreshNotifications()
            Task { await LiveActivityManager.syncActiveActivity(modelContext: modelContext) }
        }
        .task {
            LifeOSDataMigration.runLaunchMigrations(modelContext: modelContext, entryStore: entryStore)
            guard !appLock.isLocked else { return }
            refreshNotifications()
            await LiveActivityManager.syncActiveActivity(modelContext: modelContext)
        }
    }

    /// Read-only binding: the cover is dismissed by successful authentication, never by a swipe.
    private var lockPresentation: Binding<Bool> {
        Binding(get: { appLock.isLocked }, set: { _ in })
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
