import SwiftUI
import SwiftData

enum EntryFormMode {
    case create(category: EntryCategory)
    case edit(Entry)
}

struct EntryFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [Entry]

    let mode: EntryFormMode

    @State private var entry: Entry
    @State private var hasRecurrence: Bool
    @State private var showDeleteConfirmation = false
    @State private var showingAddNotification = false
    @State private var editingNotification: NotificationRule?
    @StateObject private var entryStore = EntryStore()

    init(mode: EntryFormMode) {
        self.mode = mode
        switch mode {
        case .create(let category):
            let newEntry = Entry.makeDefault(category: category)
            _entry = State(initialValue: newEntry)
            _hasRecurrence = State(initialValue: false)
        case .edit(let existing):
            _entry = State(initialValue: existing)
            _hasRecurrence = State(initialValue: existing.recurrence != nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                categorySection
                if entry.supportsLocation {
                    locationSection
                }
                if entry.supportsProgress {
                    progressSection
                }
                if entry.supportsRecurrence {
                    recurrenceSection
                }
                if entry.supportsNotifications {
                    notificationSection
                }
                notesSection

                if case .edit = mode {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    entryStore.delete(entry: entry, modelContext: modelContext)
                    dismiss()
                }
            }
            .sheet(isPresented: $showingAddNotification) {
                NotificationRuleFormView(mode: .create, preferredEntryID: entry.id)
            }
            .sheet(item: $editingNotification) { rule in
                NotificationRuleFormView(mode: .edit(rule))
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var basicSection: some View {
        Section("Basics") {
            TextField("Title", text: $entry.title)

            Picker("Category", selection: $entry.category) {
                ForEach(EntryCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .onChange(of: entry.category) { _, newCategory in
                applyCategoryDefaults(newCategory)
            }

            DatePicker("Start", selection: $entry.startDate)

            Toggle("Has Duration", isOn: Binding(
                get: { entry.duration != nil },
                set: { enabled in entry.duration = enabled ? 3600 : nil }
            ))

            if entry.duration != nil {
                Stepper(
                    "Duration: \(Int(entry.duration ?? 0) / 60) min",
                    value: Binding(
                        get: { Int(entry.duration ?? 3600) },
                        set: { entry.duration = TimeInterval($0) }
                    ),
                    in: 900...86_400,
                    step: 900
                )
            }

            Toggle("Track Completion", isOn: $entry.isCompletable)
        }
    }

    private var categorySection: some View {
        Section("Category Details") {
            switch entry.category {
            case .irl:
                EmptyView()
            case .game:
                Picker("Game", selection: Binding(
                    get: { entry.gameSubCategory ?? .genshinImpact },
                    set: { newValue in
                        entry.gameSubCategory = newValue
                        entry.isCompletable = newValue.defaultCompletable
                        if !newValue.supportsRecurrence {
                            hasRecurrence = false
                            entry.recurrence = nil
                            entry.notificationRules.removeAll()
                        }
                    }
                )) {
                    ForEach(GameSubCategory.allCases) { game in
                        Text(game.rawValue).tag(game)
                    }
                }
            case .entertainment:
                Picker("Type", selection: Binding(
                    get: { entry.entertainmentSubCategory ?? .anime },
                    set: { newValue in
                        entry.entertainmentSubCategory = newValue
                        if entry.progress == nil {
                            entry.progress = EntryProgress(unitLabel: newValue.defaultUnitLabel)
                        } else {
                            entry.progress?.unitLabel = newValue.defaultUnitLabel
                        }
                    }
                )) {
                    ForEach(EntertainmentSubCategory.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            TextField("Location", text: Binding(
                get: { entry.location ?? "" },
                set: { entry.location = $0.isEmpty ? nil : $0 }
            ))
        }
    }

    private var progressSection: some View {
        Section("Progress") {
            if entry.progress == nil {
                Button("Add Progress Tracking") {
                    entry.progress = EntryProgress(unitLabel: entry.entertainmentSubCategory?.defaultUnitLabel ?? "episode")
                }
            } else if let progress = entry.progress {
                Stepper("Current: \(progress.currentUnit)", value: Bindable(progress).currentUnit, in: 0...10_000)
                Toggle("Known Total", isOn: Binding(
                    get: { progress.totalUnits != nil },
                    set: { enabled in progress.totalUnits = enabled ? 12 : nil }
                ))
                if progress.totalUnits != nil {
                    Stepper("Total: \(progress.totalUnits ?? 0)", value: Binding(
                        get: { progress.totalUnits ?? 12 },
                        set: { progress.totalUnits = $0 }
                    ), in: 1...10_000)
                }
                TextField("Unit Label", text: Bindable(progress).unitLabel)
            }
        }
    }

    private var recurrenceSection: some View {
        Section(entry.category == .entertainment ? "Personal Habit (Display Only)" : "Recurrence") {
            Toggle("Repeats", isOn: $hasRecurrence)
                .onChange(of: hasRecurrence) { _, enabled in
                    if enabled {
                        if entry.recurrence == nil {
                            entry.recurrence = RecurrenceRule(frequency: .daily)
                            entry.recurrence?.entry = entry
                        }
                    } else {
                        entry.recurrence = nil
                    }
                }

            if hasRecurrence, let rule = entry.recurrence {
                RecurrenceEditorView(rule: rule)
            }
        }
    }

    private var notificationSection: some View {
        Section {
            if entry.notificationRules.isEmpty {
                Text("No notification rules yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.notificationRules) { rule in
                    Button {
                        editingNotification = rule
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rule.triggerKind.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(rule.isActive ? "On" : "Off")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(rule.triggerSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(rule.messageTemplate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let rule = entry.notificationRules[index]
                        modelContext.delete(rule)
                    }
                    entry.notificationRules.remove(atOffsets: indexSet)
                }
            }

            Button("Add Notification Rule") {
                if isEditing {
                    showingAddNotification = true
                } else {
                    addNotificationRuleInline()
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Full create/edit lives in the Notifications tab. Rules added here before first save stay on this entry.")
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: Binding(
                get: { entry.notes ?? "" },
                set: { entry.notes = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(3...8)
        }
    }

    private func applyCategoryDefaults(_ category: EntryCategory) {
        switch category {
        case .irl:
            entry.subCategory = nil
            entry.progress = nil
            entry.isCompletable = false
        case .game:
            entry.gameSubCategory = .genshinImpact
            entry.progress = nil
            entry.isCompletable = true
        case .entertainment:
            entry.entertainmentSubCategory = .anime
            entry.progress = EntryProgress(unitLabel: EntertainmentSubCategory.anime.defaultUnitLabel)
            entry.isCompletable = false
            entry.notificationRules.removeAll()
        }
    }

    private func addNotificationRuleInline() {
        Task {
            _ = await NotificationPlanner.shared.requestAuthorizationIfNeeded()
        }
        let rule = NotificationRule(
            triggerKind: .ifNotCompletedBy,
            triggerDate: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now),
            messageTemplate: "Still open: {title}"
        )
        rule.entry = entry
        entry.notificationRules.append(rule)
        editingNotification = rule
    }

    private func save() {
        if entry.modelContext == nil {
            modelContext.insert(entry)
        }

        if hasRecurrence, entry.recurrence != nil {
            entry.recurrence?.entry = entry
        }

        for rule in entry.notificationRules {
            rule.entry = entry
        }

        if let progress = entry.progress {
            progress.entry = entry
        }

        try? modelContext.save()
        entryStore.save(entry: entry, modelContext: modelContext, allEntries: allEntries)
        dismiss()
    }
}
