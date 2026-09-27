import SwiftUI
import SwiftData

struct PityBannerEditorView: View {
    enum Mode {
        case create
        case edit(PityTracker)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var game: GameSubCategory = .genshinImpact
    @State private var hardPity = 90
    @State private var usesSoftPity = true
    @State private var softPity = 74
    @State private var guaranteeKind: PityGuaranteeKind = .fiftyFifty
    @State private var guaranteeLabel = ""
    @State private var usesFatePath = false
    @State private var fatePointCap = 2

    var body: some View {
        NavigationStack {
            Form {
                Section("Banner") {
                    TextField("Name", text: $name)
                    Picker("Game", selection: $game) {
                        ForEach(GameSubCategory.gachaGames) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                }

                Section("Pity") {
                    Stepper("Hard pity: \(hardPity)", value: $hardPity, in: 10...200)
                    Toggle("Soft pity", isOn: $usesSoftPity)
                    if usesSoftPity {
                        Stepper("Soft pity: \(softPity)", value: $softPity, in: 1...hardPity)
                    }
                }

                Section {
                    Picker("Rule", selection: $guaranteeKind) {
                        ForEach(PityGuaranteeKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    if guaranteeKind == .custom {
                        TextField("Label (e.g. 70/30)", text: $guaranteeLabel)
                    }
                    Toggle("Epitomized Path / fate points", isOn: $usesFatePath)
                    if usesFatePath {
                        Stepper("Path cap: \(fatePointCap)", value: $fatePointCap, in: 1...5)
                    }
                } header: {
                    Text("Guarantee")
                } footer: {
                    Text(guaranteeFooter)
                }
            }
            .navigationTitle(isEditing ? "Edit Banner" : "Add Banner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .tint(LifeOSTheme.accent)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var guaranteeFooter: String {
        if usesFatePath {
            return "Fate / path is Genshin’s Epitomized Path on the weapon banner: after this many off-path 5★s, the next one is the weapon you picked."
        }
        switch guaranteeKind {
        case .none:
            return "Standard pool — any 5★ resets pity. No featured coin flip."
        case .alwaysGuaranteed:
            return "Every 5★ is the featured item. Got 5★ just zeros the counter."
        case .custom:
            return "Behaves like a coin flip (win stays on the split, loss goes to guaranteed). The label is what you see on the card."
        default:
            return "A loss on this split moves you to guaranteed. The next featured 5★ puts you back on the split."
        }
    }

    private func load() {
        guard case .edit(let tracker) = mode else { return }
        name = tracker.name
        game = tracker.game
        hardPity = tracker.hardPity
        usesSoftPity = tracker.softPity != nil
        softPity = tracker.softPity ?? max(1, tracker.hardPity - 16)
        guaranteeKind = tracker.guaranteeKind
        guaranteeLabel = tracker.guaranteeLabel ?? ""
        usesFatePath = tracker.fatePointCap > 0
        fatePointCap = max(tracker.fatePointCap, 2)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolvedSoft = usesSoftPity ? min(softPity, hardPity) : nil
        let resolvedCap = usesFatePath ? fatePointCap : 0
        let resolvedLabel = guaranteeKind == .custom
            ? guaranteeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        switch mode {
        case .create:
            let existing = (try? modelContext.fetch(FetchDescriptor<PityTracker>())) ?? []
            let nextOrder = (existing.filter { $0.game == game }.map(\.sortOrder).max() ?? -1) + 1
            let tracker = PityTracker(
                game: game,
                name: trimmed,
                sortOrder: nextOrder,
                hardPity: hardPity,
                softPity: resolvedSoft,
                guaranteeKind: guaranteeKind,
                fatePointCap: resolvedCap,
                guaranteeLabel: resolvedLabel?.isEmpty == false ? resolvedLabel : nil
            )
            modelContext.insert(tracker)
        case .edit(let tracker):
            tracker.name = trimmed
            tracker.game = game
            tracker.hardPity = hardPity
            tracker.softPity = resolvedSoft
            tracker.guaranteeKind = guaranteeKind
            tracker.guaranteeLabel = resolvedLabel?.isEmpty == false ? resolvedLabel : nil
            tracker.fatePointCap = resolvedCap
            tracker.fatePoints = min(tracker.fatePoints, resolvedCap)
            tracker.updatedAt = .now
        }

        try? modelContext.save()
        dismiss()
    }
}
