import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Entry.startDate) private var entries: [Entry]

    @StateObject private var entryStore = EntryStore()
    @State private var showingCreateSheet = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CalendarRootView(entryStore: entryStore)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshNotifications()
            }
        }
        .task {
            prepareFreshStoreIfNeeded()
            refreshNotifications()
        }
    }

    /// One-time wipe of sample/demo data so you can enter your own.
    /// Seeding is disabled going forward.
    private func prepareFreshStoreIfNeeded() {
        let wipeKey = "lifeos.didWipeSampleData.v1"
        if !UserDefaults.standard.bool(forKey: wipeKey) {
            entryStore.deleteAll(modelContext: modelContext)
            UserDefaults.standard.set(true, forKey: wipeKey)
            // Prevent any legacy seed path from running again.
            UserDefaults.standard.set(true, forKey: "lifeos.hasSeededSampleData")
            Task {
                await NotificationPlanner.refreshPendingNotifications(entries: [], force: true)
            }
        }
    }

    private func refreshNotifications() {
        Task {
            await NotificationPlanner.refreshPendingNotifications(entries: entries)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
