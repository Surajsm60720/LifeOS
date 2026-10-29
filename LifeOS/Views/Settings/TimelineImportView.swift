import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Imports a version timeline that an LLM produced from the developers'
/// livestream image. Everything is local: the file is parsed, resolved against
/// the chosen server, previewed, and upserted as ordinary entries.
struct TimelineImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Entry.startDate) private var entries: [Entry]

    @State private var servers: [GameSubCategory: GameServer] = [:]
    @State private var resetMinutes: [GameSubCategory: Int] = [:]
    @State private var bannerMinutes: [GameSubCategory: Int] = [:]
    @State private var showingPicker = false
    @State private var showingShare = false
    @State private var shareItems: [Any] = []
    @State private var plan: TimelineImportService.Plan?
    @State private var pendingRemoval: TimelineImportService.ImportGroup?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                importSection

                if let plan {
                    previewSection(plan)
                }

                if !groups.isEmpty {
                    recentSection
                }

                if statusMessage != nil || errorMessage != nil {
                    messageSection
                }
            }
            .navigationTitle("Game Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(LifeOSTheme.accent)
            .preferredColorScheme(.dark)
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFile(result)
            }
            .sheet(isPresented: $showingShare) {
                ShareSheet(items: shareItems)
            }
            .confirmationDialog(
                "Remove this timeline import?",
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) { removePendingImport() }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            } message: {
                if let pendingRemoval {
                    Text("All \(pendingRemoval.count) entries imported from \(pendingRemoval.source) will be deleted, including any edits you made to them.")
                }
            }
            .onAppear(perform: loadSettings)
        }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section {
            ForEach(GameSubCategory.gachaGames) { game in
                Picker(game.rawValue, selection: serverBinding(for: game)) {
                    ForEach(GameServerSettings.profile(for: game)?.servers ?? [], id: \.self) { server in
                        Text(server.displayName).tag(server)
                    }
                }

                DatePicker(
                    "Daily reset",
                    selection: resetTimeBinding(for: game),
                    displayedComponents: .hourAndMinute
                )

                DatePicker(
                    "Banner switch",
                    selection: bannerTimeBinding(for: game),
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Servers")
        } footer: {
            Text("Pickers show your local clock. Genshin America resets at 04:00 server time, which is 2:30 PM IST — change either value if your game differs. Banner switch drives phase timing on import; daily reset is kept for reference and future use. Whole-day events still keep the printed calendar day.")
        }
    }

    private var importSection: some View {
        Section {
            Button {
                showingPicker = true
            } label: {
                Label("Choose Timeline JSON…", systemImage: "doc.badge.plus")
            }

            Button {
                shareSchema()
            } label: {
                Label("Share Schema & Prompt", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Give the shared prompt plus the livestream timeline image to an LLM, save its reply as a .json file, then import it here. Nothing leaves your device — LifeOS only reads the file.")
        }
    }

    private func previewSection(_ plan: TimelineImportService.Plan) -> some View {
        Section {
            LabeledContent("Game", value: plan.draft.game.rawValue)

            if let patch = plan.draft.patch {
                LabeledContent("Version", value: patch)
            }

            ForEach(plan.countsByKind) { entry in
                LabeledContent(entry.kind.displayName, value: "\(entry.count)")
            }

            if let range = resolvedRange(plan) {
                LabeledContent("Window", value: range)
            }

            LabeledContent("New", value: "\(plan.createCount)")

            if plan.updateCount > 0 {
                LabeledContent("Updated", value: "\(plan.updateCount)")
            }

            ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            DisclosureGroup {
                ForEach(plan.resolvedItems, id: \.key) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline)
                        Text(itemDateText(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Text("Preview \(plan.resolvedItems.count) entries")
            }

            Button {
                runImport(plan)
            } label: {
                Label(importButtonTitle(plan), systemImage: "tray.and.arrow.down.fill")
            }
            .disabled(plan.isEmpty)

            Button("Discard", role: .destructive) {
                self.plan = nil
            }
        } header: {
            Text("Ready to Import")
        } footer: {
            Text("Importing a corrected file updates the rows it created before and leaves your edits, completions, and reminders alone.")
        }
    }

    private var recentSection: some View {
        Section {
            ForEach(groups) { group in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.source)
                        Text(groupDetail(group))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        pendingRemoval = group
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Imported Timelines")
        } footer: {
            Text("Removing an import deletes only the entries it created.")
        }
    }

    private var messageSection: some View {
        Section {
            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }

            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                plan = try TimelineImportService.prepare(data: data, modelContext: modelContext)
                errorMessage = nil
                statusMessage = nil
            } catch {
                plan = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runImport(_ plan: TimelineImportService.Plan) {
        do {
            let result = try TimelineImportService.apply(plan, modelContext: modelContext)
            var parts: [String] = []
            if result.created > 0 { parts.append("\(result.created) added") }
            if result.updated > 0 { parts.append("\(result.updated) updated") }
            statusMessage = parts.isEmpty ? "Nothing to import." : parts.joined(separator: ", ") + "."
            errorMessage = nil
            self.plan = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removePendingImport() {
        guard let group = pendingRemoval else { return }
        do {
            let count = try TimelineImportService.removeImport(source: group.source, modelContext: modelContext)
            statusMessage = "Removed \(count) imported entr\(count == 1 ? "y" : "ies")."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingRemoval = nil
    }

    private func shareSchema() {
        let bundled = Bundle.main
            .url(forResource: "GAME_TIMELINE_SCHEMA", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

        shareItems = [bundled ?? Self.fallbackPrompt]
        showingShare = true
    }

    // MARK: - Settings plumbing

    private func loadSettings() {
        for game in GameSubCategory.gachaGames {
            servers[game] = GameServerSettings.server(for: game)
            resetMinutes[game] = GameServerSettings.resetMinutes(for: game)
            bannerMinutes[game] = GameServerSettings.bannerSwitchMinutes(for: game)
        }
    }

    private func serverBinding(for game: GameSubCategory) -> Binding<GameServer> {
        Binding(
            get: { servers[game] ?? GameServerSettings.server(for: game) },
            set: { server in
                servers[game] = server
                GameServerSettings.setServer(server, for: game)
                // Re-read clocks so the local pickers reflect the new offset.
                resetMinutes[game] = GameServerSettings.resetMinutes(for: game)
                bannerMinutes[game] = GameServerSettings.bannerSwitchMinutes(for: game)
            }
        )
    }

    private func resetTimeBinding(for game: GameSubCategory) -> Binding<Date> {
        Binding(
            get: {
                GameServerSettings.dateForLocalPicker(
                    minutes: resetMinutes(for: game),
                    game: game
                )
            },
            set: { date in
                let minutes = GameServerSettings.minutesFromLocalPicker(date: date, game: game)
                resetMinutes[game] = minutes
                GameServerSettings.setResetMinutes(minutes, for: game)
            }
        )
    }

    private func bannerTimeBinding(for game: GameSubCategory) -> Binding<Date> {
        Binding(
            get: {
                GameServerSettings.dateForLocalPicker(
                    minutes: bannerMinutes(for: game),
                    game: game
                )
            },
            set: { date in
                let minutes = GameServerSettings.minutesFromLocalPicker(date: date, game: game)
                bannerMinutes[game] = minutes
                GameServerSettings.setBannerSwitchMinutes(minutes, for: game)
            }
        )
    }

    private func bannerMinutes(for game: GameSubCategory) -> Int {
        bannerMinutes[game] ?? GameServerSettings.bannerSwitchMinutes(for: game)
    }

    private func resetMinutes(for game: GameSubCategory) -> Int {
        resetMinutes[game] ?? GameServerSettings.resetMinutes(for: game)
    }

    // MARK: - Presentation helpers

    private var groups: [TimelineImportService.ImportGroup] {
        TimelineImportService.importGroups(from: entries)
    }

    private func groupDetail(_ group: TimelineImportService.ImportGroup) -> String {
        let count = "\(group.count) entr\(group.count == 1 ? "y" : "ies")"
        guard let latest = group.latest else { return count }
        return "\(count) · \(BackupFormatting.full(latest))"
    }

    private func importButtonTitle(_ plan: TimelineImportService.Plan) -> String {
        let total = plan.createCount + plan.updateCount
        return "Import \(total) entr\(total == 1 ? "y" : "ies")"
    }

    private func resolvedRange(_ plan: TimelineImportService.Plan) -> String? {
        let items = plan.resolvedItems
        guard let first = items.first, let last = items.last else { return nil }
        let start = DateFormatting.recapLine.string(from: first.startDate)
        let end = DateFormatting.recapLine.string(from: itemEndDate(last) ?? last.startDate)
        return "\(start) – \(end)"
    }

    private func itemEndDate(_ item: TimelineImportService.Item) -> Date? {
        guard let duration = item.duration else { return nil }
        if item.isAllDay {
            let days = max(1, Int((duration / 86_400).rounded()))
            return Calendar.current.date(byAdding: .day, value: days - 1, to: item.startDate)
        }
        return item.startDate.addingTimeInterval(duration)
    }

    private func itemDateText(_ item: TimelineImportService.Item) -> String {
        if item.isAllDay {
            let start = DateFormatting.recapLine.string(from: item.startDate)
            guard let end = itemEndDate(item),
                  !Calendar.current.isDate(end, inSameDayAs: item.startDate) else {
                return start
            }
            return "\(start) – \(DateFormatting.recapLine.string(from: end))"
        }

        let start = "\(DateFormatting.recapLine.string(from: item.startDate)) \(DateFormatting.timeOfDay.string(from: item.startDate))"
        guard let end = itemEndDate(item) else { return start }
        return "\(start) – \(DateFormatting.recapLine.string(from: end)) \(DateFormatting.timeOfDay.string(from: end))"
    }

    /// Used when the markdown resource isn't in the bundle, so the button still
    /// produces something an LLM can follow.
    private static let fallbackPrompt = """
    Convert the attached game version timeline image into a LifeOS timeline JSON file.

    Output only one JSON object, no prose and no markdown fences:

    {
      "format": "lifeos.timeline",
      "version": 1,
      "game": "Genshin Impact" | "Honkai Star Rail" | "Wuthering Waves",
      "patch": "6.1",
      "items": [
        {
          "id": "genshin-6.1-astral-accord",
          "kind": "event" | "banner" | "endgame",
          "title": "Astral Accord",
          "start": "2026-10-29",
          "end": "2026-11-11",
          "featured": [],
          "notes": "",
          "sourceLine": "",
          "confidence": "high"
        }
      ]
    }

    Rules:
    - Copy dates exactly as printed. Never infer or round them.
    - Dates are YYYY-MM-DD. Only include a time as "YYYY-MM-DD HH:mm" when the image shows one.
    - Times are server-local wall clock. Never write Z or a UTC offset.
    - A date-only end is inclusive: the item is playable through that day.
    - One item per banner phase. Character and weapon banners are separate items.
    - Emit events, banners, and endgame modes only. Skip maintenance, livestream, pre-install, battle pass, and shop promos.
    - Genshin Impact HARD RULE: never emit Spiral Abyss or Imaginarium Theater, even if the image shows them. They are fixed monthly rotations LifeOS already tracks as recurring entries. A Genshin file must contain only event and banner items — zero endgame rows. Still emit endgame for Honkai Star Rail and Wuthering Waves.
    - If a row is unclear, still emit it with "confidence": "low".
    - Keep ids stable across re-parses: lowercase game-patch-title, no dates.
    """
}
