import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entries: [Entry]

    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var showingImporter = false
    @State private var pendingDocument: BackupService.Document?
    @State private var confirmReplace = false
    @State private var confirmMerge = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @StateObject private var entryStore = EntryStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Backup is a JSON snapshot of every entry, expense, location, recurrence, notification rule, progress, and completion. Use it to recover after a wipe or reinstall. Markdown recaps stay separate for LLM summaries.")
                }

                if let pendingDocument {
                    Section {
                        LabeledContent("Entries", value: "\(pendingDocument.entries.count)")
                        LabeledContent(
                            "Exported",
                            value: DateFormatting.recapLine.string(from: pendingDocument.exportedAt)
                        )

                        Button("Replace All Data", role: .destructive) {
                            confirmReplace = true
                        }

                        Button("Merge Into Existing") {
                            confirmMerge = true
                        }
                    } header: {
                        Text("Imported File")
                    } footer: {
                        Text("Replace wipes everything on this device first. Merge keeps current entries and adds or updates by entry ID.")
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Backup & Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .confirmationDialog(
                "Replace all LifeOS data?",
                isPresented: $confirmReplace,
                titleVisibility: .visible
            ) {
                Button("Replace Everything", role: .destructive) {
                    performReplace()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(entries.count) current entries will be deleted, then the backup will be loaded.")
            }
            .confirmationDialog(
                "Merge backup into existing data?",
                isPresented: $confirmMerge,
                titleVisibility: .visible
            ) {
                Button("Merge") {
                    performMerge()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Matching entry IDs are updated. New IDs are added. Completions and notification rules are merged without wiping the rest of your library.")
            }
        }
    }

    private func exportBackup() {
        do {
            let url = try BackupService.writeTemporaryFile(entries: entries)
            exportURL = url
            showingShareSheet = true
            errorMessage = nil
            statusMessage = "Backup ready to share."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            statusMessage = nil
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                pendingDocument = try BackupService.decode(data)
                errorMessage = nil
                statusMessage = "Backup loaded. Choose Replace or Merge."
            } catch {
                pendingDocument = nil
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
        }
    }

    private func performReplace() {
        guard let document = pendingDocument else { return }
        do {
            let summary = try BackupService.replace(
                document: document,
                modelContext: modelContext,
                entryStore: entryStore
            )
            refreshNotifications()
            statusMessage = "Replace complete. \(summary.descriptionText)"
            errorMessage = nil
            pendingDocument = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performMerge() {
        guard let document = pendingDocument else { return }
        do {
            let summary = try BackupService.merge(document: document, modelContext: modelContext)
            refreshNotifications()
            statusMessage = "Merge complete. \(summary.descriptionText)"
            errorMessage = nil
            pendingDocument = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshNotifications() {
        let descriptor = FetchDescriptor<Entry>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        Task {
            await NotificationPlanner.refreshPendingNotifications(entries: all, force: true)
            await LiveActivityManager.syncActiveActivity(modelContext: modelContext)
        }
    }
}
