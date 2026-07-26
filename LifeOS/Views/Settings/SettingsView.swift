import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.startDate) private var entries: [Entry]

    @State private var showingExport = false
    @State private var showingTemplates = false
    @State private var showingLibrary = false
    @State private var confirmClearAll = false
    @StateObject private var entryStore = EntryStore()

    var body: some View {
        List {
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
                LabeledContent("Version", value: "0.2")
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
    }

    private var todayCompletableCount: Int {
        let store = EntryStore()
        let interval = DateInterval(start: DateFormatting.startOfDay(.now), duration: 86_400)
        return store.occurrences(for: entries, in: interval)
            .filter { $0.entry.isCompletable && !$0.entry.isCompleted(on: $0.occurrenceDate) }
            .count
    }
}
