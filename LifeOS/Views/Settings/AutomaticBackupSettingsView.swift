import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AutomaticBackupSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AutomaticBackup.enabledKey) private var isEnabled: Bool = false
    @AppStorage(AutomaticBackup.weekdayKey) private var weekday: Int = AutomaticBackup.defaultWeekday
    @AppStorage(AutomaticBackup.hourKey) private var hour: Int = AutomaticBackup.defaultHour
    @AppStorage(AutomaticBackup.minuteKey) private var minute: Int = AutomaticBackup.defaultMinute
    @AppStorage(AutomaticBackup.monthlyEnabledKey) private var monthlyEnabled: Bool = false
    @AppStorage(AutomaticBackup.yearlyEnabledKey) private var yearlyEnabled: Bool = false

    @State private var showingFolderPicker = false
    @State private var folderName: String?
    @State private var folderPath: String?
    @State private var folderConfigured = false
    @State private var lastSuccess: Date?
    @State private var lastError: String?
    @State private var monthlyLabel: String?
    @State private var monthlyAt: Date?
    @State private var monthlyError: String?
    @State private var yearlyLabel: String?
    @State private var yearlyAt: Date?
    @State private var yearlyError: String?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var anyScheduleEnabled: Bool {
        isEnabled || monthlyEnabled || yearlyEnabled
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: AutomaticBackup.hour,
                    minute: AutomaticBackup.minute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = components.hour ?? AutomaticBackup.defaultHour
                minute = components.minute ?? AutomaticBackup.defaultMinute
                backupSettingsChanged()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                folderSection
                scheduleSection
                statusSection
                manualSection
            }
            .navigationTitle("Automatic Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(LifeOSTheme.accent)
            .preferredColorScheme(.dark)
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result)
            }
            .onChange(of: isEnabled) { _, _ in
                backupSettingsChanged()
            }
            .onChange(of: weekday) { _, _ in
                backupSettingsChanged()
            }
            .onChange(of: monthlyEnabled) { _, enabled in
                backupSettingsChanged()
                if enabled { writeLatestArchive(.month) }
            }
            .onChange(of: yearlyEnabled) { _, enabled in
                backupSettingsChanged()
                if enabled { writeLatestArchive(.year) }
            }
            .onAppear(perform: refresh)
        }
    }

    // MARK: - Sections

    private var folderSection: some View {
        Section {
            LabeledContent("Folder") {
                Text(folderName ?? "Not set")
                    .foregroundStyle(folderConfigured ? LifeOSTheme.softText : Color.orange)
            }

            if let folderPath {
                Text(folderPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Button(folderConfigured ? "Change Folder" : "Choose Folder…") {
                showingFolderPicker = true
            }

            if folderConfigured {
                Button("Remove Folder", role: .destructive) {
                    BackupDestination.clear()
                    isEnabled = false
                    monthlyEnabled = false
                    yearlyEnabled = false
                    AutomaticBackup.clearErrors()
                    statusMessage = nil
                    errorMessage = nil
                    refresh()
                    AutoBackupScheduler.scheduleNext()
                }
            }
        } header: {
            Text("Destination")
        } footer: {
            Text("Pick a folder in Files — for example a dedicated folder in iCloud Drive. Everything LifeOS writes stays there even if the app is deleted. The folder is outside the app container, so it is never wiped with the app's own data.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Toggle("Weekly Backup", isOn: $isEnabled)
                .disabled(!folderConfigured)

            if isEnabled {
                Picker("Day", selection: $weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(AutomaticBackup.weekdayName(for: day)).tag(day)
                    }
                }
            }

            Toggle("Monthly Archive", isOn: $monthlyEnabled)
                .disabled(!folderConfigured)

            Toggle("Yearly Archive", isOn: $yearlyEnabled)
                .disabled(!folderConfigured)

            if anyScheduleEnabled {
                DatePicker(
                    "Time",
                    selection: timeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Schedule")
        } footer: {
            if folderConfigured {
                Text(scheduleFooter)
            } else {
                Text("Choose a destination folder first.")
            }
        }
    }

    private var scheduleFooter: String {
        var parts: [String] = []
        if isEnabled {
            parts.append("Weekly backups are complete snapshots — the newest \(AutomaticBackup.weeklyRetentionCount) are kept.")
        }
        if monthlyEnabled {
            parts.append("Monthly archives cover the whole month and the newest \(AutomaticBackup.monthlyRetentionCount) are kept.")
        }
        if yearlyEnabled {
            parts.append("Yearly archives cover 1 Jan – 31 Dec and the newest \(AutomaticBackup.yearlyRetentionCount) are kept.")
        }
        if parts.isEmpty { return "Turn on at least one schedule." }
        return parts.joined(separator: " ") + " Archives are summaries for LLM recaps, not importable backups. Work runs after the slot passes and you next open the app."
    }

    private var statusSection: some View {
        Section {
            if isEnabled {
                LabeledContent("Weekly", value: AutomaticBackup.scheduleSummary())
                LabeledContent(
                    "Last weekly backup",
                    value: lastSuccess.map { BackupFormatting.full($0) } ?? "Never"
                )
                if let next = AutomaticBackup.nextDueDate() {
                    LabeledContent(
                        "Next weekly backup",
                        value: next <= .now ? "Due now" : BackupFormatting.relativeToNow(next)
                    )
                }
            }

            if monthlyEnabled || monthlyLabel != nil {
                LabeledContent(
                    "Last monthly archive",
                    value: monthlyLabel.map {
                        ArchiveService.displayName(forLabel: $0, kind: .month)
                    } ?? "Never"
                )
                if let monthlyAt {
                    LabeledContent("Archived", value: BackupFormatting.full(monthlyAt))
                }
            }

            if yearlyEnabled || yearlyLabel != nil {
                LabeledContent(
                    "Last yearly archive",
                    value: yearlyLabel ?? "Never"
                )
                if let yearlyAt {
                    LabeledContent("Archived", value: BackupFormatting.full(yearlyAt))
                }
            }

            ForEach(Array(failureMessages.enumerated()), id: \.offset) { _, message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Status")
        } footer: {
            Text("iOS decides exactly when background work runs, so treat the slot as a target rather than a guarantee. Opening LifeOS always catches up if a slot was missed.")
        }
    }

    private var manualSection: some View {
        Section {
            Button {
                runBackupNow()
            } label: {
                Label("Back Up Now", systemImage: "externaldrive.badge.checkmark")
            }
            .disabled(!folderConfigured)

            Button {
                writeLatestArchive(.month)
            } label: {
                Label("Archive Last Month", systemImage: "calendar.badge.clock")
            }
            .disabled(!folderConfigured)

            Button {
                writeLatestArchive(.year)
            } label: {
                Label("Archive Last Year", systemImage: "calendar")
            }
            .disabled(!folderConfigured)
        } footer: {
            if let statusMessage {
                Text(statusMessage)
            } else {
                Text("This snapshot has its own file name, so pressing it never rotates away a weekly backup. Archives can be written again for the last completed period at any time.")
            }
        }
    }

    // MARK: - Actions

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }

            if BackupDestination.isInsideAppSandbox(url) {
                errorMessage = "That folder is inside LifeOS's own storage, so it would be deleted with the app. Pick a folder in iCloud Drive or On My iPhone instead."
                return
            }

            do {
                try BackupDestination.store(url: url)
                errorMessage = nil
                statusMessage = "Folder connected."
                refresh()
                AutoBackupScheduler.scheduleNext()
            } catch {
                errorMessage = "Could not use that folder: \(error.localizedDescription)"
            }
        }
    }

    private func runBackupNow() {
        do {
            let record = try AutomaticBackup.backupNow(modelContext: modelContext)
            statusMessage = "Saved \(record.entryCount) entries and \(record.pityCount) pity counters (\(BackupFormatting.bytes(record.byteCount)))."
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    private func writeLatestArchive(_ kind: ArchiveService.Kind) {
        guard folderConfigured else { return }
        do {
            let period = ArchiveService.lastCompletedPeriod(kind)
            let record = try AutomaticBackup.archiveNow(
                kind,
                modelContext: modelContext,
                period: period
            )
            let label = ArchiveService.displayName(forLabel: period.label, kind: kind)
            statusMessage = "Wrote \(label) — \(record.entryCount) event\(record.entryCount == 1 ? "" : "s") (\(BackupFormatting.bytes(record.byteCount)))."
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    private func backupSettingsChanged() {
        AutomaticBackup.settingsDidChange()
        AutoBackupScheduler.scheduleNext()
    }

    private func refresh() {
        folderConfigured = BackupDestination.isConfigured
        folderName = BackupDestination.displayName
        folderPath = BackupDestination.displayPath
        lastSuccess = AutomaticBackup.lastSuccessAt
        lastError = AutomaticBackup.lastErrorMessage
        monthlyLabel = AutomaticBackup.lastArchiveLabel(.month)
        monthlyAt = AutomaticBackup.lastArchiveAt(.month)
        monthlyError = AutomaticBackup.lastArchiveErrorMessage(.month)
        yearlyLabel = AutomaticBackup.lastArchiveLabel(.year)
        yearlyAt = AutomaticBackup.lastArchiveAt(.year)
        yearlyError = AutomaticBackup.lastArchiveErrorMessage(.year)
    }

    private var failureMessages: [String] {
        [lastError, monthlyError, yearlyError].compactMap { $0 }
    }
}

enum BackupFormatting {
    static func full(_ date: Date) -> String {
        "\(DateFormatting.recapLine.string(from: date)) at \(DateFormatting.timeOfDay.string(from: date))"
    }

    static func relativeToNow(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today at \(DateFormatting.timeOfDay.string(from: date))"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow at \(DateFormatting.timeOfDay.string(from: date))"
        }
        return full(date)
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
