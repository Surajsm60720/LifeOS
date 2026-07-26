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
    @State private var trackExpense: Bool
    @State private var splitNamesText: String
    @State private var lineAmountTexts: [PersistentIdentifier: String]
    @State private var balanceAmountTexts: [PersistentIdentifier: String]
    @State private var showDeleteConfirmation = false
    @State private var showingAddNotification = false
    @State private var editingNotification: NotificationRule?
    @State private var locationSearchIndex: Int?
    @State private var playedWithText: String
    @StateObject private var entryStore = EntryStore()

    init(mode: EntryFormMode) {
        self.mode = mode
        switch mode {
        case .create(let category):
            let newEntry = Entry.makeDefault(category: category)
            _entry = State(initialValue: newEntry)
            _hasRecurrence = State(initialValue: false)
            _trackExpense = State(initialValue: false)
            _splitNamesText = State(initialValue: "")
            _lineAmountTexts = State(initialValue: [:])
            _balanceAmountTexts = State(initialValue: [:])
            _playedWithText = State(initialValue: "")
        case .edit(let existing):
            _entry = State(initialValue: existing)
            _hasRecurrence = State(initialValue: existing.recurrence != nil)
            _trackExpense = State(initialValue: existing.trackExpense || !existing.expenseLines.isEmpty)
            _splitNamesText = State(initialValue: existing.expenseBalances.map(\.personName).joined(separator: "\n"))
            var lineTexts: [PersistentIdentifier: String] = [:]
            for line in existing.expenseLines {
                lineTexts[line.persistentModelID] = Self.formatAmount(line.amount)
            }
            var balanceTexts: [PersistentIdentifier: String] = [:]
            for balance in existing.expenseBalances {
                balanceTexts[balance.persistentModelID] = Self.formatAmount(balance.amount)
            }
            _lineAmountTexts = State(initialValue: lineTexts)
            _balanceAmountTexts = State(initialValue: balanceTexts)
            _playedWithText = State(initialValue: existing.playedWith.joined(separator: "\n"))
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
                if entry.category == .irl {
                    expenseSection
                }
                if entry.supportsEventType {
                    eventTypeSection
                }
                if entry.supportsSessionLog {
                    sessionLogSection
                }
                if entry.supportsProgress {
                    progressSection
                }
                if entry.supportsRecurrence || (entry.category == .irl && !trackExpense) {
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
            .sheet(isPresented: Binding(
                get: { locationSearchIndex != nil },
                set: { if !$0 { locationSearchIndex = nil } }
            )) {
                PlaceSearchSheet { name, lat, lon in
                    guard let index = locationSearchIndex, entry.locations.indices.contains(index) else { return }
                    entry.locations[index].name = name
                    entry.locations[index].latitude = lat
                    entry.locations[index].longitude = lon
                    locationSearchIndex = nil
                }
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
                        if newValue.supportsEventType {
                            entry.clearSessionLog()
                            playedWithText = ""
                        } else {
                            entry.clearEventType()
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
        Section {
            if entry.locations.isEmpty {
                Text("No locations yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.locations.enumerated()), id: \.element.persistentModelID) { index, place in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Place name", text: Binding(
                            get: { place.name },
                            set: { place.name = $0 }
                        ))
                        HStack {
                            Button("Search Place") {
                                locationSearchIndex = index
                            }
                            Spacer()
                            if place.hasCoordinates {
                                Text("Pinned")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let place = entry.locations[index]
                        modelContext.delete(place)
                    }
                    entry.locations.remove(atOffsets: offsets)
                }
            }

            Button("Add Location") {
                let place = LocationEntry(name: "")
                place.entry = entry
                entry.locations.append(place)
            }
        } header: {
            Text("Locations")
        } footer: {
            Text("Multi-stop hangouts can list several places in order.")
        }
    }

    private var expenseSection: some View {
        Section {
            Toggle("Track Expense", isOn: $trackExpense)
                .disabled(hasRecurrence)
                .onChange(of: trackExpense) { _, enabled in
                    if enabled {
                        hasRecurrence = false
                        entry.recurrence = nil
                        entry.trackExpense = true
                        if entry.expenseLines.isEmpty {
                            addExpenseLine()
                        }
                    } else {
                        entry.clearExpense(modelContext: modelContext)
                        lineAmountTexts = [:]
                        balanceAmountTexts = [:]
                        splitNamesText = ""
                    }
                }

            if trackExpense, !hasRecurrence {
                ForEach(Array(entry.expenseLines.enumerated()), id: \.element.persistentModelID) { index, line in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("What was it spent on?", text: Binding(
                            get: { line.title },
                            set: { line.title = $0 }
                        ))
                        TextField("Amount", text: lineAmountBinding(for: line))
                            .keyboardType(.decimalPad)
                    }
                }
                .onDelete(perform: deleteExpenseLines)

                Button("Add Expense Line") {
                    addExpenseLine()
                }

                LabeledContent("Total") {
                    Text(Self.formatAmount(entry.expenseTotal))
                        .fontWeight(.semibold)
                }

                ForEach(Array(entry.expenseBalances.enumerated()), id: \.element.persistentModelID) { _, balance in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Who owes you?", text: Binding(
                            get: { balance.personName },
                            set: { balance.personName = $0 }
                        ))
                        TextField("Amount", text: balanceAmountBinding(for: balance))
                            .keyboardType(.decimalPad)
                    }
                }
                .onDelete(perform: deleteExpenseBalances)

                Button("Add Person Who Owes You") {
                    addExpenseBalance()
                }

                TextField("Names for equal split (one per line)", text: $splitNamesText, axis: .vertical)
                    .lineLimit(2...5)

                Button("Split Total Equally") {
                    syncLineAmountsIntoModels()
                    let names = splitNamesText
                        .split(whereSeparator: { $0 == "\n" || $0 == "," })
                        .map(String.init)
                    entry.applyEqualSplit(among: names, modelContext: modelContext)
                    balanceAmountTexts = [:]
                    for balance in entry.expenseBalances {
                        balanceAmountTexts[balance.persistentModelID] = Self.formatAmount(balance.amount)
                    }
                }
                .disabled(entry.expenseTotal == 0 || splitNamesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Expense")
        } footer: {
            Text(hasRecurrence
                 ? "Expense tracking is for one-off hangouts. Turn off recurrence to track spend."
                 : "Add freestyle line items to build the total. Optionally record who should pay you back, or split the total equally.")
        }
    }

    private var eventTypeSection: some View {
        Section("Event Type") {
            Picker("Type", selection: Binding(
                get: { entry.eventType ?? .dailies },
                set: { entry.eventType = $0 }
            )) {
                ForEach(GameEventType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
        }
    }

    private var sessionLogSection: some View {
        Section("Session Log") {
            TextField("Planned activity", text: Binding(
                get: { entry.plannedActivity ?? "" },
                set: { entry.plannedActivity = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(2...4)

            TextField("Played with (one name per line)", text: $playedWithText, axis: .vertical)
                .lineLimit(2...6)
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
                Toggle("Session Target", isOn: Binding(
                    get: { progress.targetUnitsPerSession != nil },
                    set: { enabled in progress.targetUnitsPerSession = enabled ? 1 : nil }
                ))
                if progress.targetUnitsPerSession != nil {
                    Stepper(
                        "Target: \(progress.targetUnitsPerSession ?? 1) / session",
                        value: Binding(
                            get: { progress.targetUnitsPerSession ?? 1 },
                            set: { progress.targetUnitsPerSession = $0 }
                        ),
                        in: 1...500
                    )
                }
                TextField("Unit Label", text: Bindable(progress).unitLabel)
            }
        }
    }

    private var recurrenceSection: some View {
        Section(entry.category == .entertainment ? "Personal Habit (Display Only)" : "Recurrence") {
            Toggle("Repeats", isOn: $hasRecurrence)
                .disabled(trackExpense && entry.category == .irl)
                .onChange(of: hasRecurrence) { _, enabled in
                    if enabled {
                        trackExpense = false
                        entry.clearExpense(modelContext: modelContext)
                        lineAmountTexts = [:]
                        balanceAmountTexts = [:]
                        splitNamesText = ""
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
            entry.clearEventType()
            entry.clearSessionLog()
            playedWithText = ""
            entry.isCompletable = false
        case .game:
            entry.gameSubCategory = .genshinImpact
            entry.progress = nil
            entry.clearLocations(modelContext: modelContext)
            entry.clearExpense(modelContext: modelContext)
            trackExpense = false
            lineAmountTexts = [:]
            balanceAmountTexts = [:]
            splitNamesText = ""
            entry.clearSessionLog()
            playedWithText = ""
            entry.isCompletable = true
        case .entertainment:
            entry.entertainmentSubCategory = .anime
            entry.progress = EntryProgress(unitLabel: EntertainmentSubCategory.anime.defaultUnitLabel)
            entry.clearLocations(modelContext: modelContext)
            entry.clearExpense(modelContext: modelContext)
            trackExpense = false
            lineAmountTexts = [:]
            balanceAmountTexts = [:]
            splitNamesText = ""
            entry.clearEventType()
            entry.clearSessionLog()
            playedWithText = ""
            entry.isCompletable = false
            entry.notificationRules.removeAll()
        }
    }

    private func addExpenseLine() {
        let line = ExpenseLine(title: "", amount: 0)
        line.entry = entry
        entry.expenseLines.append(line)
        lineAmountTexts[line.persistentModelID] = ""
    }

    private func addExpenseBalance() {
        let balance = ExpenseBalance(personName: "", amount: 0)
        balance.entry = entry
        entry.expenseBalances.append(balance)
        balanceAmountTexts[balance.persistentModelID] = ""
    }

    private func deleteExpenseLines(at offsets: IndexSet) {
        for index in offsets {
            let line = entry.expenseLines[index]
            lineAmountTexts.removeValue(forKey: line.persistentModelID)
            modelContext.delete(line)
        }
        entry.expenseLines.remove(atOffsets: offsets)
    }

    private func deleteExpenseBalances(at offsets: IndexSet) {
        for index in offsets {
            let balance = entry.expenseBalances[index]
            balanceAmountTexts.removeValue(forKey: balance.persistentModelID)
            modelContext.delete(balance)
        }
        entry.expenseBalances.remove(atOffsets: offsets)
    }

    private func lineAmountBinding(for line: ExpenseLine) -> Binding<String> {
        Binding(
            get: { lineAmountTexts[line.persistentModelID] ?? Self.formatAmount(line.amount) },
            set: { newValue in
                lineAmountTexts[line.persistentModelID] = newValue
                line.amount = Self.parseAmount(newValue) ?? 0
            }
        )
    }

    private func balanceAmountBinding(for balance: ExpenseBalance) -> Binding<String> {
        Binding(
            get: { balanceAmountTexts[balance.persistentModelID] ?? Self.formatAmount(balance.amount) },
            set: { newValue in
                balanceAmountTexts[balance.persistentModelID] = newValue
                balance.amount = Self.parseAmount(newValue) ?? 0
            }
        )
    }

    private func syncLineAmountsIntoModels() {
        for line in entry.expenseLines {
            if let text = lineAmountTexts[line.persistentModelID] {
                line.amount = Self.parseAmount(text) ?? 0
            }
        }
    }

    private func pruneEmptyExpenseLines() {
        let empties = entry.expenseLines.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount == 0
        }
        for line in empties {
            lineAmountTexts.removeValue(forKey: line.persistentModelID)
            modelContext.delete(line)
            if let index = entry.expenseLines.firstIndex(where: { $0.persistentModelID == line.persistentModelID }) {
                entry.expenseLines.remove(at: index)
            }
        }
    }

    private func pruneEmptyExpenseBalances() {
        let empties = entry.expenseBalances.filter {
            $0.personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount == 0
        }
        for balance in empties {
            balanceAmountTexts.removeValue(forKey: balance.persistentModelID)
            modelContext.delete(balance)
            if let index = entry.expenseBalances.firstIndex(where: { $0.persistentModelID == balance.persistentModelID }) {
                entry.expenseBalances.remove(at: index)
            }
        }
    }

    private func pruneEmptyLocations() {
        let empties = entry.locations.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for place in empties {
            modelContext.delete(place)
            if let index = entry.locations.firstIndex(where: { $0.persistentModelID == place.persistentModelID }) {
                entry.locations.remove(at: index)
            }
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

        if trackExpense, entry.category == .irl, !hasRecurrence {
            entry.trackExpense = true
            syncLineAmountsIntoModels()
            for balance in entry.expenseBalances {
                if let text = balanceAmountTexts[balance.persistentModelID] {
                    balance.amount = Self.parseAmount(text) ?? 0
                }
                balance.entry = entry
            }
            for line in entry.expenseLines {
                line.entry = entry
            }
            pruneEmptyExpenseLines()
            pruneEmptyExpenseBalances()
            entry.expenseAmount = nil
            entry.expenseCategory = nil
        } else {
            entry.clearExpense(modelContext: modelContext)
            trackExpense = false
        }

        entry.playedWith = playedWithText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !entry.supportsEventType {
            entry.clearEventType()
        } else if entry.eventType == nil {
            entry.eventType = .dailies
        }

        if !entry.supportsSessionLog {
            entry.clearSessionLog()
        }

        if !entry.supportsLocation {
            entry.clearLocations(modelContext: modelContext)
        } else {
            for place in entry.locations {
                place.entry = entry
            }
            pruneEmptyLocations()
        }

        if hasRecurrence, entry.recurrence != nil {
            entry.recurrence?.entry = entry
            entry.clearExpense(modelContext: modelContext)
            trackExpense = false
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

    private static func formatAmount(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }

    private static func parseAmount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }
}
