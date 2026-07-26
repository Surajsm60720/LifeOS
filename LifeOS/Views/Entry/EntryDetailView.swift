import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: Entry
    let occurrenceDate: Date

    @State private var showingEditSheet = false
    @State private var showDeleteConfirm = false
    @StateObject private var entryStore = EntryStore()

    private var isCompleted: Bool {
        entry.isCompleted(on: occurrenceDate)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ZStack(alignment: .leading) {
                        if entry.category == .game {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(GameIdentity.gradient(for: entry.gameSubCategory))
                                .frame(height: 72)
                        }

                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(entry.category == .game
                                      ? GameIdentity.accent(for: entry.gameSubCategory)
                                      : entry.displayColor)
                                .frame(width: 6, height: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.title2.weight(.semibold))
                                Text(subtitleLine)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, entry.category == .game ? 12 : 0)
                        .padding(.horizontal, entry.category == .game ? 8 : 0)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("When") {
                    LabeledContent("Date", value: DateFormatting.recapLine.string(from: occurrenceDate))
                    if let duration = entry.duration {
                        LabeledContent("Duration", value: "\(Int(duration / 60)) minutes")
                    }
                }

                if entry.supportsLocation, !entry.locations.isEmpty {
                    Section("Locations") {
                        ForEach(entry.locations, id: \.persistentModelID) { place in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                if place.hasCoordinates {
                                    Text("\(place.latitude ?? 0), \(place.longitude ?? 0)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if let summary = entry.locationSummary {
                    Section("Locations") {
                        Text(summary)
                    }
                }

                if entry.trackExpense || !entry.expenseLines.isEmpty {
                    Section("Expenses") {
                        ForEach(entry.expenseLines, id: \.persistentModelID) { line in
                            LabeledContent(
                                line.title.isEmpty ? "Item" : line.title,
                                value: "\(line.amount)"
                            )
                        }
                        LabeledContent("Total", value: "\(entry.expenseTotal)")
                            .fontWeight(.semibold)
                    }
                }

                if !entry.expenseBalances.isEmpty {
                    Section("Settlements") {
                        ForEach(entry.expenseBalances, id: \.persistentModelID) { balance in
                            Text("\(balance.personName.isEmpty ? "Someone" : balance.personName) owes you \(balance.amount)")
                        }
                        LabeledContent("Owed to you", value: "\(entry.expenseOwedToYou)")
                            .fontWeight(.semibold)
                    }
                }

                if let eventType = entry.eventType {
                    Section("Event Type") {
                        LabeledContent("Type", value: eventType.displayName)
                    }
                }

                if entry.supportsSessionLog {
                    Section("Session") {
                        if let planned = entry.plannedActivity, !planned.isEmpty {
                            LabeledContent("Planned", value: planned)
                        }
                        if !entry.playedWith.isEmpty {
                            LabeledContent("Played with", value: entry.playedWith.joined(separator: ", "))
                        }
                    }
                }

                if entry.supportsProgress {
                    Section("Progress") {
                        if let progress = entry.progress {
                            if let total = progress.totalUnits, total > 0 {
                                ProgressView(value: Double(progress.currentUnit), total: Double(total)) {
                                    Text("\(progress.currentUnit) / \(total) \(progress.unitLabel)")
                                }
                            } else {
                                LabeledContent("Current", value: "\(progress.currentUnit) \(progress.unitLabel)")
                            }
                            if let target = progress.targetUnitsPerSession {
                                LabeledContent("Session target", value: "\(target) \(progress.unitLabel)")
                            }
                        } else {
                            Text("No progress yet")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            entryStore.incrementProgress(for: entry, modelContext: modelContext)
                        } label: {
                            Label(
                                "Add 1 \(entry.progress?.unitLabel ?? entry.entertainmentSubCategory?.defaultUnitLabel ?? "unit")",
                                systemImage: "plus.circle"
                            )
                        }
                    }
                }

                if entry.isCompletable {
                    Section("Completion") {
                        Toggle(isOn: Binding(
                            get: { isCompleted },
                            set: { _ in
                                entryStore.toggleCompletion(
                                    for: entry,
                                    on: occurrenceDate,
                                    modelContext: modelContext
                                )
                            }
                        )) {
                            Text(isCompleted ? "Completed" : "Mark Complete")
                        }
                    }
                }

                if let notes = entry.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                    }
                }

                if !entry.notificationRules.isEmpty {
                    Section("Notifications") {
                        ForEach(entry.notificationRules) { rule in
                            VStack(alignment: .leading) {
                                Text(rule.triggerKind.displayName)
                                Text(rule.messageTemplate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Duplicate Entry") {
                        _ = entryStore.duplicate(entry: entry, modelContext: modelContext)
                        dismiss()
                    }
                }

                Section {
                    Button("Delete Entry", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("Entry")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showingEditSheet = true }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                EntryFormView(mode: .edit(entry))
            }
            .confirmationDialog(
                "Delete “\(entry.title)”?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Entry", role: .destructive) {
                    entryStore.delete(entry: entry, modelContext: modelContext)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the entry, its recurrence, completions, and notification rules.")
            }
        }
    }

    private var subtitleLine: String {
        var parts = [entry.category.displayName]
        if let sub = entry.subCategory {
            parts.append(sub)
        }
        if let eventType = entry.eventType {
            parts.append(eventType.displayName)
        }
        return parts.joined(separator: " · ")
    }
}
