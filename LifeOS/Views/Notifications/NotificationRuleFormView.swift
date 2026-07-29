import SwiftUI
import SwiftData

enum NotificationRuleFormMode {
    case create
    case edit(NotificationRule)
}

struct NotificationRuleFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.startDate) private var entries: [Entry]

    let mode: NotificationRuleFormMode
    var preferredEntryID: UUID? = nil
    /// Unsaved entry from New Entry form — included as an eligible target without inserting a default rule early.
    var draftEntry: Entry? = nil

    @State private var selectedEntryID: UUID?
    @State private var triggerKind: NotificationTriggerKind = .ifNotCompletedBy
    @State private var triggerDate: Date = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
    @State private var triggerOffsetMinutes: Int = 0
    @State private var messageTemplate: String = "Still open: {title}"
    @State private var isActive: Bool = true

    private var eligibleEntries: [Entry] {
        var list = entries.filter(\.supportsNotifications)
        if let draftEntry, draftEntry.supportsNotifications,
           !list.contains(where: { $0.id == draftEntry.id }) {
            list.append(draftEntry)
        }
        return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var selectedEntry: Entry? {
        eligibleEntries.first { $0.id == selectedEntryID }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        selectedEntry != nil && !messageTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if eligibleEntries.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Eligible Entries",
                            systemImage: "bell.slash",
                            description: Text("Notification rules must attach to an existing IRL event or a Genshin Impact / HSR / Wuthering Waves game entry. Entertainment and Other games cannot have notifications.")
                        )
                    }
                } else {
                    Section {
                        Picker("Entry", selection: $selectedEntryID) {
                            Text("Select an entry").tag(Optional<UUID>.none)
                            ForEach(eligibleEntries, id: \.id) { entry in
                                Text(entryPickerLabel(for: entry)).tag(Optional(entry.id))
                            }
                        }
                        .disabled(isEditing)
                    } header: {
                        Text("Linked Entry")
                    } footer: {
                        Text(isEditing
                             ? "Rules stay attached to the entry they were created for."
                             : "Only IRL and priority-game entries can receive notifications. You can use a preset or build a fully custom trigger.")
                    }

                    if !isEditing {
                        Section("Presets") {
                            ForEach(NotificationPreset.allCases) { preset in
                                Button(preset.title) {
                                    applyPreset(preset)
                                }
                            }
                        }
                    }

                    Section {
                        Picker("Trigger", selection: $triggerKind) {
                            ForEach(NotificationTriggerKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }

                        Text(triggerKind.helpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        switch triggerKind {
                        case .fixedTime, .ifNotCompletedBy:
                            DatePicker("Time", selection: $triggerDate, displayedComponents: [.hourAndMinute])
                        case .relativeToStart:
                            Stepper(offsetLabel, value: $triggerOffsetMinutes, in: -24 * 60...24 * 60, step: 5)
                        }
                    } header: {
                        Text("When")
                    }

                    Section {
                        TextField("Message", text: $messageTemplate, axis: .vertical)
                            .lineLimit(2...5)

                        Text("Placeholders: {title}, {category}")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let entry = selectedEntry {
                            LabeledContent("Preview") {
                                Text(previewMessage(for: entry))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    } header: {
                        Text("Message")
                    }

                    Section {
                        Toggle("Active", isOn: $isActive)
                    } footer: {
                        Text(footerText)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Notification" : "New Notification")
            .navigationBarTitleDisplayMode(.inline)
            .tint(LifeOSTheme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.light()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.success()
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                hydrateFromMode()
                Task {
                    _ = await NotificationPlanner.shared.requestAuthorizationIfNeeded()
                }
            }
            .onChange(of: eligibleEntries.map(\.id)) { _, ids in
                if selectedEntryID == nil, let first = ids.first {
                    selectedEntryID = first
                }
            }
        }
    }

    private var offsetLabel: String {
        if triggerOffsetMinutes == 0 { return "Offset: at start" }
        if triggerOffsetMinutes > 0 { return "Offset: \(triggerOffsetMinutes) min after start" }
        return "Offset: \(-triggerOffsetMinutes) min before start"
    }

    private var footerText: String {
        var parts = ["Inactive rules stay saved but will not schedule local notifications."]
        if triggerKind == .ifNotCompletedBy {
            parts.append("“If Not Completed By” only fires when the linked entry has completion tracking enabled.")
        }
        return parts.joined(separator: " ")
    }

    private func entryPickerLabel(for entry: Entry) -> String {
        var parts = [entry.title]
        parts.append(entry.category.displayName)
        if let sub = entry.subCategory {
            parts.append(sub)
        }
        return parts.joined(separator: " · ")
    }

    private func previewMessage(for entry: Entry) -> String {
        messageTemplate
            .replacingOccurrences(of: "{title}", with: entry.title)
            .replacingOccurrences(of: "{category}", with: entry.category.displayName)
    }

    private func hydrateFromMode() {
        switch mode {
        case .create:
            selectedEntryID = preferredEntryID ?? eligibleEntries.first?.id
            // Default to a few minutes ahead so a quick test can actually fire today.
            triggerDate = Date().addingTimeInterval(3 * 60)
            triggerKind = .fixedTime
            messageTemplate = "Reminder: {title}"
        case .edit(let rule):
            selectedEntryID = rule.entry?.id
            triggerKind = rule.triggerKind
            triggerDate = rule.triggerDate
                ?? Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now)
                ?? .now
            triggerOffsetMinutes = Int((rule.triggerInterval ?? 0) / 60)
            messageTemplate = rule.messageTemplate
            isActive = rule.isActive
        }
    }

    private func applyPreset(_ preset: NotificationPreset) {
        triggerKind = preset.triggerKind
        messageTemplate = preset.messageTemplate
        if let date = preset.triggerDate() {
            triggerDate = date
        }
        if let minutes = preset.triggerOffsetMinutes {
            triggerOffsetMinutes = minutes
        }
        isActive = true
    }

    private func save() {
        guard let entry = selectedEntry else { return }

        let rule: NotificationRule
        switch mode {
        case .create:
            rule = NotificationRule(
                triggerKind: triggerKind,
                messageTemplate: messageTemplate,
                isActive: isActive
            )
            rule.entry = entry
            entry.notificationRules.append(rule)
            // Only insert into the store when the entry is already persisted.
            // Draft entries (New Entry form) keep the rule in-memory until the entry is saved.
            if entry.modelContext != nil {
                modelContext.insert(rule)
            }
        case .edit(let existing):
            rule = existing
            rule.triggerKind = triggerKind
            rule.messageTemplate = messageTemplate
            rule.isActive = isActive
        }

        switch triggerKind {
        case .fixedTime, .ifNotCompletedBy:
            rule.triggerDate = triggerDate
            rule.triggerInterval = nil
        case .relativeToStart:
            rule.triggerInterval = TimeInterval(triggerOffsetMinutes * 60)
            rule.triggerDate = nil
        }

        if entry.modelContext != nil {
            try? modelContext.save()
            Task {
                await NotificationPlanner.refreshPendingNotifications(entries: entries, force: true)
            }
        }

        dismiss()
    }
}
