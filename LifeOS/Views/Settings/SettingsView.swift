import SwiftUI
import SwiftData
import UIKit

private enum AppIconChoice: String, CaseIterable, Identifiable {
    case primary
    case geometric
    case minimal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .primary: return "Default"
        case .geometric: return "Geometric"
        case .minimal: return "Minimal"
        }
    }

    /// The `UIApplication.setAlternateIconName` argument (nil means default icon).
    /// Names must match the alternate-icon keys generated from the App Icon asset sets.
    var alternateIconName: String? {
        switch self {
        case .primary: return nil
        case .geometric: return "AppIconGeometric"
        case .minimal: return "AppIconMinimal"
        }
    }

    static func from(alternateIconName: String?) -> AppIconChoice {
        switch alternateIconName {
        case nil: return .primary
        case "AppIconGeometric": return .geometric
        case "AppIconMinimal": return .minimal
        default: return .primary
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.startDate) private var entries: [Entry]

    @AppStorage(CalendarViewMode.defaultStorageKey) private var defaultModeRaw: String = CalendarViewMode.day.rawValue
    @AppStorage(LiveActivityManager.enabledStorageKey) private var liveActivityEnabled: Bool = false
    @AppStorage(LiveActivityManager.defaultScopeStorageKey) private var liveActivityScopeRaw: String = LiveActivityScope.day.rawValue
    @State private var showingExport = false
    @State private var showingTemplates = false
    @State private var showingLibrary = false
    @State private var confirmClearAll = false
    @StateObject private var entryStore = EntryStore()

    @State private var selectedIconChoice: AppIconChoice = .primary
    @State private var didLoadCurrentIcon = false

    private var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    private var defaultModeBinding: Binding<CalendarViewMode> {
        Binding(
            get: { CalendarViewMode(rawValue: defaultModeRaw) ?? .day },
            set: { defaultModeRaw = $0.rawValue }
        )
    }

    private var liveActivityScopeBinding: Binding<LiveActivityScope> {
        Binding(
            get: { LiveActivityScope(rawValue: liveActivityScopeRaw) ?? .day },
            set: { liveActivityScopeRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section {
                Picker("App Icon", selection: $selectedIconChoice) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .disabled(!supportsAlternateIcons)
            } header: {
                Text("App Icon")
            } footer: {
                Text("Home Screen updates right away. On iOS 18, Notification Center may keep the previous glyph until a device restart — that is an iOS cache limitation, not something LifeOS can force.")
            }

            Section {
                Picker("Default View", selection: defaultModeBinding) {
                    ForEach(CalendarViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("LifeOS opens the Calendar tab in this view when you launch the app.")
            }

            Section {
                Toggle("Live Activity (Dynamic Island)", isOn: $liveActivityEnabled)

                Picker("Default Scope", selection: liveActivityScopeBinding) {
                    ForEach(LiveActivityScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .disabled(!liveActivityEnabled)
            } header: {
                Text("Dynamic Island")
            } footer: {
                Text("When enabled, LifeOS shows remaining to-dos for Day/Week/Month/Year directly on the Dynamic Island (system limits how long it stays visible).")
            }

            Section {
                Button {
                    showingExport = true
                } label: {
                    Label("Generate Recap", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingTemplates = true
                } label: {
                    Label("Entry Templates", systemImage: "doc.on.doc")
                }

                Button {
                    showingLibrary = true
                } label: {
                    Label("All Entries", systemImage: "list.bullet")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Export builds Markdown for LLM recaps. Templates create starter entries. Manage individual deletes in All Entries.")
            }

            Section("Library") {
                LabeledContent("Entries", value: "\(entries.count)")
                LabeledContent(
                    "Completable today",
                    value: "\(todayCompletableCount)"
                )
            }

            Section {
                Button("Delete All Data", role: .destructive) {
                    confirmClearAll = true
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Permanently removes every entry, completion, and notification rule on this device. This cannot be undone.")
            }

            Section("About") {
                LabeledContent("App", value: "LifeOS")
                LabeledContent("Version", value: "0.4")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LifeOSTheme.canvas)
        .sheet(isPresented: $showingExport) {
            RecapExportView(entries: entries)
        }
        .sheet(isPresented: $showingTemplates) {
            EntryTemplatesView()
        }
        .sheet(isPresented: $showingLibrary) {
            EntryLibraryView()
        }
        .confirmationDialog(
            "Delete all LifeOS data?",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                entryStore.deleteAll(modelContext: modelContext)
                Task {
                    await NotificationPlanner.refreshPendingNotifications(entries: [], force: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(entries.count) entries will be removed. You can add your own data afterward.")
        }
        .onAppear {
            guard !didLoadCurrentIcon else { return }
            selectedIconChoice = AppIconChoice.from(alternateIconName: UIApplication.shared.alternateIconName)
            didLoadCurrentIcon = true

            Task { await LiveActivityManager.syncActiveActivity(modelContext: modelContext) }
        }
        .onChange(of: selectedIconChoice) { _, newValue in
            guard didLoadCurrentIcon, supportsAlternateIcons else { return }

            UIApplication.shared.setAlternateIconName(newValue.alternateIconName) { error in
                if let error {
                    print("Alternate icon change failed: \(error)")
                    return
                }
                Task {
                    // Drop already-delivered banners that may still show the previous glyph
                    // (iOS 18.1+ often caches notification icons separately from Home Screen).
                    await NotificationPlanner.clearDeliveredNotifications()
                    await NotificationPlanner.rescheduleManagedNotificationsForIconUpdate(entries: entries)
                }
            }
        }
        .onChange(of: liveActivityEnabled) { _, _ in
            Task { await LiveActivityManager.syncActiveActivity(modelContext: modelContext) }
        }
        .onChange(of: liveActivityScopeRaw) { _, _ in
            let scope = LiveActivityScope(rawValue: liveActivityScopeRaw) ?? .day
            Task { await LiveActivityManager.syncActiveActivity(modelContext: modelContext, scopeOverride: scope) }
        }
    }

    private var todayCompletableCount: Int {
        let store = EntryStore()
        let interval = DateInterval(start: DateFormatting.startOfDay(.now), duration: 86_400)
        return store.occurrences(for: entries, in: interval)
            .filter { $0.entry.isCompletable && !$0.entry.isCompleted(on: $0.occurrenceDate) }
            .count
    }
}
