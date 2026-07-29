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
    /// Supplied by `ContentView` so all tabs share a single `@Query`.
    let entries: [Entry]
    var appLock: AppLockManager

    @Environment(\.modelContext) private var modelContext

    @AppStorage(CalendarViewMode.defaultStorageKey) private var defaultModeRaw: String = CalendarViewMode.day.rawValue
    @AppStorage(LiveActivityManager.enabledStorageKey) private var liveActivityEnabled: Bool = false
    @State private var showingExport = false
    @State private var showingBackup = false
    @State private var showingTemplates = false
    @State private var showingLibrary = false
    @State private var confirmClearAll = false
    @State private var todayCompletableCount = 0
    @StateObject private var entryStore = EntryStore()

    @State private var selectedIconChoice: AppIconChoice = .primary
    @State private var didLoadCurrentIcon = false

    private var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    /// Reads straight from `AppLockManager` so there is no mirrored state to fall out
    /// of sync. Writes route through `setEnabled`, which authenticates in both
    /// directions; if the user cancels, the toggle simply springs back.
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { appLock.isEnabled },
            set: { appLock.setEnabled($0) { _ in } }
        )
    }

    private var defaultModeBinding: Binding<CalendarViewMode> {
        Binding(
            get: { CalendarViewMode(rawValue: defaultModeRaw) ?? .day },
            set: { defaultModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            if LifeOSSharedStore.isUsingRecoveryStore {
                Section {
                    Label("Database could not be opened", systemImage: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.orange)

                    if let reason = LifeOSSharedStore.storeFailureReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingBackup = true
                    } label: {
                        Label("Restore From Backup", systemImage: "externaldrive")
                            .font(.body.weight(.semibold))
                    }
                } header: {
                    Text("Recovery Mode")
                } footer: {
                    Text("LifeOS is running on a temporary in-memory database, so changes will not be saved. Restore a backup to recover your data.")
                }
            }

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
            } header: {
                Text("Dynamic Island")
            } footer: {
                Text("When enabled, LifeOS shows today's remaining to-dos directly on the Dynamic Island and Lock Screen (system limits how long it stays visible).")
            }

            Section {
                Toggle("\(appLock.biometryName) Unlock", isOn: appLockBinding)
                    .disabled(!appLock.canAuthenticate)
            } header: {
                Text("Security")
            } footer: {
                Text(appLock.canAuthenticate
                     ? "When enabled, LifeOS asks for \(appLock.biometryName) (or your device passcode) each time you open it. Turning this off also requires authentication."
                     : "Set a device passcode in iOS Settings to use App Lock.")
            }

            Section {
                Button {
                    showingExport = true
                } label: {
                    Label("Generate Recap", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingBackup = true
                } label: {
                    Label("Backup & Restore", systemImage: "externaldrive")
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
                Text("Recap builds Markdown for LLM summaries. Backup exports JSON you can restore after a wipe or reinstall (Replace or Merge). Templates create starter entries.")
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
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(LifeOSTheme.accent)
        .scrollContentBackground(.hidden)
        .background(LifeOSTheme.canvas)
        .sheet(isPresented: $showingExport) {
            RecapExportView(entries: entries)
        }
        .sheet(isPresented: $showingBackup) {
            BackupRestoreView(entries: entries)
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
        .onChange(of: entries) { _, _ in
            recomputeTodayCompletableCount()
        }
        .onChange(of: entryStore.dataVersion) { _, _ in
            recomputeTodayCompletableCount()
        }
        .onAppear {
            recomputeTodayCompletableCount()

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
                Task { @MainActor in
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
    }

    /// Recomputed on data change rather than on every render, and reusing the
    /// existing store. As a computed property this re-expanded the whole library
    /// each time SwiftUI evaluated `body`.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func recomputeTodayCompletableCount() {
        let interval = DateInterval(start: DateFormatting.startOfDay(.now), duration: 86_400)
        todayCompletableCount = entryStore.occurrences(for: entries, in: interval)
            .filter { $0.entry.isCompletable && !$0.entry.isCompleted(on: $0.occurrenceDate) }
            .count
    }
}
