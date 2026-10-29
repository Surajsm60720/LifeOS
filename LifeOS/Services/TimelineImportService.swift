import Foundation
import SwiftData

/// Turns a game-timeline JSON file into ordinary `Entry` rows.
///
/// The app never calls an AI service: the file is produced elsewhere (an LLM
/// reading the version's timeline image) and this service validates, resolves,
/// and upserts it. "Resolve" is the interesting part — a printed date is a
/// calendar day on the game's server, not an instant, so the server time zone
/// and the banner-switch hour decide where a row actually lands.
enum TimelineImportService {
    static let formatIdentifier = "lifeos.timeline"
    static let supportedVersion = 1
    static let maximumItems = 500

    // MARK: - Errors

    enum ImportError: LocalizedError, Equatable {
        case unreadable(String)
        case invalidFormat
        case missingVersion
        case unsupportedVersion(Int)
        case unknownGame(String)
        case noItems
        case onlyFixedEndgame
        case tooManyItems(Int)

        var errorDescription: String? {
            switch self {
            case .unreadable(let detail):
                return "Could not read that file as JSON: \(detail)"
            case .invalidFormat:
                return "This is not a LifeOS timeline file. Expected \"format\": \"lifeos.timeline\"."
            case .missingVersion:
                return "The timeline file has no \"version\" field."
            case .unsupportedVersion(let version):
                return "Timeline version \(version) is not supported by this build of LifeOS."
            case .unknownGame(let name):
                return "\"\(name)\" isn't a game LifeOS imports timelines for. Use Genshin Impact, Honkai Star Rail, or Wuthering Waves."
            case .noItems:
                return "The timeline file has no usable items."
            case .onlyFixedEndgame:
                return "This file only contains Spiral Abyss or Imaginarium Theater rows. LifeOS already tracks those as recurring entries, so there is nothing to import."
            case .tooManyItems(let count):
                return "This file has \(count) items; the limit is \(maximumItems)."
            }
        }
    }

    private enum RowError: LocalizedError {
        case invalidDate
        case endBeforeStart

        var errorDescription: String? {
            switch self {
            case .invalidDate: return "the date could not be read"
            case .endBeforeStart: return "the end comes before the start"
            }
        }
    }

    // MARK: - Results

    /// One row after date resolution, ready to become an `Entry`.
    struct Item: Sendable {
        let key: String
        let kind: TimelineKind
        let title: String
        let notes: String?
        let startDate: Date
        let isAllDay: Bool
        let duration: TimeInterval?
        let eventType: GameEventType
        let confidence: String?
        let featured: [String]
    }

    struct Draft: Sendable {
        let game: GameSubCategory
        let patch: String?
        let source: String
        let items: [Item]
        let warnings: [String]
        let skippedKinds: Int
        let correctedYears: Int
    }

    @MainActor
    struct Plan {
        struct Update {
            let entry: Entry
            let item: Item
        }

        let draft: Draft
        let creates: [Item]
        let updates: [Update]
        let conflicts: [String]
        let warnings: [String]

        var createCount: Int { creates.count }
        var updateCount: Int { updates.count }
        var isEmpty: Bool { creates.isEmpty && updates.isEmpty }

        var resolvedItems: [Item] {
            (creates + updates.map(\.item)).sorted { $0.startDate < $1.startDate }
        }

        var countsByKind: [KindCount] {
            let items = creates + updates.map(\.item)
            return TimelineKind.allCases.compactMap { kind in
                let count = items.filter { $0.kind == kind }.count
                return count > 0 ? KindCount(kind: kind, count: count) : nil
            }
        }
    }

    struct KindCount: Identifiable, Sendable {
        let kind: TimelineKind
        let count: Int
        var id: String { kind.rawValue }
    }

    struct ApplyResult: Sendable {
        let created: Int
        let updated: Int
    }

    struct ImportGroup: Identifiable, Hashable, Sendable {
        let source: String
        let count: Int
        let latest: Date?
        var id: String { source }
    }

    // MARK: - Entry points

    @MainActor
    static func prepare(
        data: Data,
        modelContext: ModelContext,
        now: Date = .now
    ) throws -> Plan {
        let document = try decode(data)
        let draft = try buildDraft(document, now: now)
        let existing = (try? modelContext.fetch(FetchDescriptor<Entry>())) ?? []
        return makePlan(draft: draft, existing: existing)
    }

    @MainActor
    @discardableResult
    static func apply(
        _ plan: Plan,
        modelContext: ModelContext,
        now: Date = .now
    ) throws -> ApplyResult {
        let source = plan.draft.source
        let game = plan.draft.game

        for item in plan.creates {
            let entry = Entry(
                title: item.title,
                category: .game,
                subCategory: game.rawValue,
                startDate: item.startDate,
                isAllDay: item.isAllDay,
                duration: item.duration,
                notes: item.notes,
                isCompletable: false,
                eventTypeRaw: item.eventType.rawValue
            )
            entry.importKey = item.key
            entry.importSource = source
            entry.importedAt = now
            entry.normalizeStartDateIfAllDay()
            modelContext.insert(entry)
        }

        for update in plan.updates {
            let entry = update.entry
            entry.title = update.item.title
            entry.categoryRaw = EntryCategory.game.rawValue
            entry.subCategory = game.rawValue
            entry.startDate = update.item.startDate
            entry.isAllDay = update.item.isAllDay
            entry.duration = update.item.duration
            entry.eventTypeRaw = update.item.eventType.rawValue
            entry.importSource = source
            entry.importedAt = now
            entry.normalizeStartDateIfAllDay()
            // `notes`, completions, locations, and notification rules are left
            // alone: a corrected timeline must not undo the user's own edits.
        }

        if !plan.creates.isEmpty || !plan.updates.isEmpty {
            try modelContext.save()
        }
        return ApplyResult(created: plan.creates.count, updated: plan.updates.count)
    }

    @MainActor
    @discardableResult
    static func removeImport(source: String, modelContext: ModelContext) throws -> Int {
        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        let matches = entries.filter { $0.importSource == source }
        for entry in matches {
            modelContext.delete(entry)
        }
        if !matches.isEmpty {
            try modelContext.save()
        }
        return matches.count
    }

    @MainActor
    static func importGroups(from entries: [Entry]) -> [ImportGroup] {
        var groups: [String: (count: Int, latest: Date?)] = [:]
        for entry in entries {
            guard let source = entry.importSource, !source.isEmpty else { continue }
            var group = groups[source] ?? (0, nil)
            group.count += 1
            if let at = entry.importedAt, at > (group.latest ?? .distantPast) {
                group.latest = at
            }
            groups[source] = group
        }
        return groups
            .map { ImportGroup(source: $0.key, count: $0.value.count, latest: $0.value.latest) }
            .sorted { ($0.latest ?? .distantPast) > ($1.latest ?? .distantPast) }
    }

    // MARK: - Decoding

    static func decode(_ data: Data) throws -> TimelineDocument {
        guard var text = String(data: data, encoding: .utf8) else {
            throw ImportError.unreadable("The file isn't UTF-8 text.")
        }

        // Models wrap JSON in fences or a sentence no matter how the prompt is
        // worded. Recover the object instead of failing the import.
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last {
            text = String(text[first...last])
        }

        guard let json = text.data(using: .utf8) else {
            throw ImportError.unreadable("The file isn't valid text.")
        }

        do {
            return try JSONDecoder().decode(TimelineDocument.self, from: json)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
    }

    // MARK: - Building a draft

    private struct ParsedTimestamp {
        let date: Date
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let hasTime: Bool
        let correctedYear: Bool

        /// `2026-09-30`, used to compare printed calendar days across items.
        var dayKey: String {
            String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    private struct ParsedRow {
        let kind: TimelineKind
        let title: String
        let key: String
        let start: ParsedTimestamp
        let end: ParsedTimestamp?
        let featured: [String]
        let group: String?
        let notes: String?
        let sourceLine: String?
        let confidence: String?
        let phase: Int?
    }

    static func buildDraft(_ document: TimelineDocument, now: Date = .now) throws -> Draft {
        guard (document.format ?? "").trimmingCharacters(in: .whitespaces).lowercased() == formatIdentifier else {
            throw ImportError.invalidFormat
        }
        guard let version = document.version else {
            throw ImportError.missingVersion
        }
        guard version == supportedVersion else {
            throw ImportError.unsupportedVersion(version)
        }
        guard let gameName = document.game else {
            throw ImportError.unknownGame("")
        }
        guard let game = TimelineGameMatcher.match(gameName),
              let profile = GameServerSettings.profile(for: game) else {
            throw ImportError.unknownGame(gameName)
        }
        guard let rawItems = document.items, !rawItems.isEmpty else {
            throw ImportError.noItems
        }
        guard rawItems.count <= maximumItems else {
            throw ImportError.tooManyItems(rawItems.count)
        }

        let calendar = GameServerSettings.calendar(for: game)
        let bannerSwitch = GameServerSettings.bannerSwitchMinutes(for: game)
        let patchLive = profile.patchLiveMinutes
        let patch = trimmed(document.patch)
        let source = [game.rawValue, patch].compactMap { $0 }.joined(separator: " ")

        var warnings: [String] = []
        var skippedKinds = 0
        var skippedFixedEndgame = 0
        var correctedYears = 0

        if let declared = trimmed(document.serverTimeZone),
           let declaredZone = TimeZone(identifier: declared),
           declaredZone.secondsFromGMT(for: now) != GameServerSettings.timeZone(for: game).secondsFromGMT(for: now) {
            warnings.append(
                "The file says \(declared), but \(game.rawValue) dates are read at \(GameServerSettings.offsetDescription(for: game)). Your server setting wins."
            )
        }

        var parsed: [ParsedRow] = []
        var seenKeys = Set<String>()

        for (index, item) in rawItems.enumerated() {
            guard let kind = resolveKind(item.kind) else {
                skippedKinds += 1
                continue
            }

            guard let title = trimmed(item.title) else {
                warnings.append("Row \(index + 1) has no title and was skipped.")
                continue
            }

            // Genshin's two endgame modes are a fixed monthly rotation the user
            // already tracks as recurring entries; importing them would duplicate
            // every cycle.
            if game == .genshinImpact,
               kind == .endgame,
               isFixedGenshinEndgame(title) {
                skippedFixedEndgame += 1
                continue
            }

            guard let startRaw = trimmed(item.start),
                  let start = parseTimestamp(startRaw, calendar: calendar, now: now) else {
                warnings.append("\"\(title)\" has no readable start date and was skipped.")
                continue
            }
            if start.correctedYear {
                correctedYears += 1
            }

            var end: ParsedTimestamp?
            if let endRaw = trimmed(item.end) {
                if let parsedEnd = parseTimestamp(endRaw, calendar: calendar, now: now) {
                    end = parsedEnd
                    if parsedEnd.correctedYear {
                        correctedYears += 1
                    }
                } else {
                    warnings.append("\"\(title)\" has an unreadable end date; imported without a window.")
                }
            }

            let slug = normalizedSlug(item.id) ?? normalizedSlug(title) ?? "row-\(index + 1)"
            let key = "\(game.rawValue)|\(patch ?? "")|\(slug)"
            guard seenKeys.insert(key).inserted else {
                warnings.append("\"\(title)\" repeats an id already used in this file and was skipped.")
                continue
            }

            parsed.append(
                ParsedRow(
                    kind: kind,
                    title: title,
                    key: key,
                    start: start,
                    end: end,
                    featured: (item.featured ?? []).compactMap { trimmed($0) },
                    group: trimmed(item.group),
                    notes: trimmed(item.notes),
                    sourceLine: trimmed(item.sourceLine),
                    confidence: trimmed(item.confidence)?.lowercased(),
                    phase: item.phase
                )
            )
        }

        if skippedKinds > 0 {
            warnings.append("Skipped \(skippedKinds) row\(skippedKinds == 1 ? "" : "s") that weren't events, banners, or endgame.")
        }
        if skippedFixedEndgame > 0 {
            warnings.append(
                "Skipped \(skippedFixedEndgame) Genshin endgame row\(skippedFixedEndgame == 1 ? "" : "s"): Spiral Abyss and Imaginarium Theater are already tracked as recurring entries."
            )
        }
        if correctedYears > 0 {
            warnings.append("Corrected the year on \(correctedYears) date\(correctedYears == 1 ? "" : "s") that looked a year behind.")
        }

        // The first banner phase starts when the patch goes live; later phases
        // start at the banner-switch hour. Resolving this across the whole file
        // keeps parallel banners (character + weapon) on the same boundary.
        let earliestBannerDay = parsed
            .filter { $0.kind == .banner }
            .map(\.start.dayKey)
            .min()

        var items: [Item] = []
        for row in parsed {
            do {
                items.append(
                    try resolve(
                        row,
                        calendar: calendar,
                        bannerSwitchMinutes: bannerSwitch,
                        patchLiveMinutes: patchLive,
                        earliestBannerDay: earliestBannerDay,
                        source: source
                    )
                )
            } catch {
                warnings.append("\"\(row.title)\" was skipped: \(error.localizedDescription)")
            }
        }

        guard !items.isEmpty else {
            if skippedFixedEndgame > 0 {
                throw ImportError.onlyFixedEndgame
            }
            throw ImportError.noItems
        }

        return Draft(
            game: game,
            patch: patch,
            source: source,
            items: items,
            warnings: warnings,
            skippedKinds: skippedKinds,
            correctedYears: correctedYears
        )
    }

    // MARK: - Planning

    @MainActor
    private static func makePlan(draft: Draft, existing: [Entry]) -> Plan {
        var byKey: [String: Entry] = [:]
        for entry in existing {
            if let key = entry.importKey {
                byKey[key] = entry
            }
        }

        // Index hand-made entries so a timeline import can never silently
        // duplicate something the user typed themselves.
        var manual: [String: Entry] = [:]
        for entry in existing where entry.importKey == nil {
            manual[manualKey(title: entry.title, date: entry.startDate)] = entry
        }

        var creates: [Item] = []
        var updates: [Plan.Update] = []
        var conflicts: [String] = []
        var warnings = draft.warnings

        for item in draft.items {
            if let entry = byKey[item.key] {
                updates.append(Plan.Update(entry: entry, item: item))
                continue
            }
            if manual[manualKey(title: item.title, date: item.startDate)] != nil {
                conflicts.append(item.title)
                continue
            }
            creates.append(item)
        }

        if !conflicts.isEmpty {
            warnings.append(
                "\(conflicts.count) row\(conflicts.count == 1 ? "" : "s") match entries you already added by hand and were skipped."
            )
        }

        let lowConfidence = draft.items.filter { $0.confidence == "low" }
        if !lowConfidence.isEmpty {
            let names = lowConfidence.prefix(3).map(\.title).joined(separator: ", ")
            warnings.append(
                "\(lowConfidence.count) row\(lowConfidence.count == 1 ? "" : "s") were marked low-confidence by the parser: \(names)\(lowConfidence.count > 3 ? "…" : "")"
            )
        }

        return Plan(
            draft: draft,
            creates: creates,
            updates: updates,
            conflicts: conflicts,
            warnings: warnings
        )
    }

    // MARK: - Resolution

    private static func resolve(
        _ row: ParsedRow,
        calendar: Calendar,
        bannerSwitchMinutes: Int,
        patchLiveMinutes: Int,
        earliestBannerDay: String?,
        source: String
    ) throws -> Item {
        let notes = composeNotes(for: row, source: source)

        switch row.kind {
        case .banner:
            // Phase 1 begins when the patch goes live; every later phase begins
            // at the banner switch. A date-only end is the switch date itself.
            let isFirstPhase: Bool
            if let phase = row.phase {
                isFirstPhase = phase <= 1
            } else {
                isFirstPhase = row.start.dayKey == earliestBannerDay
            }

            let startMinutes = row.start.hasTime
                ? row.start.hour * 60 + row.start.minute
                : (isFirstPhase ? patchLiveMinutes : bannerSwitchMinutes)

            guard let startDate = instant(row.start, minutes: startMinutes, calendar: calendar) else {
                throw RowError.invalidDate
            }

            guard let end = row.end else {
                return Item(
                    key: row.key,
                    kind: row.kind,
                    title: row.title,
                    notes: notes,
                    startDate: startDate,
                    isAllDay: false,
                    duration: nil,
                    eventType: row.kind.eventType,
                    confidence: row.confidence,
                    featured: row.featured
                )
            }

            let endMinutes = end.hasTime
                ? end.hour * 60 + end.minute
                : bannerSwitchMinutes

            guard let endDate = instant(end, minutes: endMinutes, calendar: calendar) else {
                throw RowError.invalidDate
            }
            guard endDate > startDate else {
                throw RowError.endBeforeStart
            }

            return Item(
                key: row.key,
                kind: row.kind,
                title: row.title,
                notes: notes,
                startDate: startDate,
                isAllDay: false,
                duration: endDate.timeIntervalSince(startDate),
                eventType: row.kind.eventType,
                confidence: row.confidence,
                featured: row.featured
            )

        case .event, .endgame:
            // Explicit times win. Otherwise the row is a whole-day window, which
            // is what the timeline image actually communicates.
            if row.start.hasTime || row.end?.hasTime == true {
                guard let startDate = instant(
                    row.start,
                    minutes: row.start.hour * 60 + row.start.minute,
                    calendar: calendar
                ) else {
                    throw RowError.invalidDate
                }

                guard let end = row.end else {
                    return Item(
                        key: row.key,
                        kind: row.kind,
                        title: row.title,
                        notes: notes,
                        startDate: startDate,
                        isAllDay: false,
                        duration: nil,
                        eventType: row.kind.eventType,
                        confidence: row.confidence,
                        featured: row.featured
                    )
                }

                guard let endDate = instant(
                    end,
                    minutes: end.hour * 60 + end.minute,
                    calendar: calendar
                ) else {
                    throw RowError.invalidDate
                }
                guard endDate > startDate else {
                    throw RowError.endBeforeStart
                }

                return Item(
                    key: row.key,
                    kind: row.kind,
                    title: row.title,
                    notes: notes,
                    startDate: startDate,
                    isAllDay: false,
                    duration: endDate.timeIntervalSince(startDate),
                    eventType: row.kind.eventType,
                    confidence: row.confidence,
                    featured: row.featured
                )
            }

            guard let end = row.end else {
                guard let startDate = localMidnight(row.start) else {
                    throw RowError.invalidDate
                }
                return Item(
                    key: row.key,
                    kind: row.kind,
                    title: row.title,
                    notes: notes,
                    startDate: startDate,
                    isAllDay: true,
                    duration: nil,
                    eventType: row.kind.eventType,
                    confidence: row.confidence,
                    featured: row.featured
                )
            }

            guard let dayCount = inclusiveDayCount(from: row.start, to: end), dayCount >= 1 else {
                throw RowError.endBeforeStart
            }
            guard let startDate = localMidnight(row.start) else {
                throw RowError.invalidDate
            }

            return Item(
                key: row.key,
                kind: row.kind,
                title: row.title,
                notes: notes,
                startDate: startDate,
                isAllDay: true,
                duration: Double(dayCount) * 86_400,
                eventType: row.kind.eventType,
                confidence: row.confidence,
                featured: row.featured
            )
        }
    }

    // MARK: - Date parsing

    /// Parses `YYYY-MM-DD`, `YYYY-MM-DD HH:mm`, and tolerant variants. Everything
    /// is interpreted in the game's server time zone; UTC suffixes and offsets are
    /// discarded because a model should not be doing that conversion.
    private static func parseTimestamp(
        _ raw: String,
        calendar: Calendar,
        now: Date
    ) -> ParsedTimestamp? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "T", with: " ")

        let pieces = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let datePart = pieces.first else { return nil }
        let timePart = pieces.count > 1 ? String(pieces[1]) : nil

        let dateNumbers = datePart
            .components(separatedBy: CharacterSet(charactersIn: "-/").union(.whitespaces))
            .filter { !$0.isEmpty }
            .compactMap { Int($0) }
        guard dateNumbers.count == 3 else { return nil }

        var hour = 0
        var minute = 0
        var hasTime = false

        if let timePart, !timePart.isEmpty {
            var time = timePart
            if let cut = time.firstIndex(where: { $0 == "Z" || $0 == "z" || $0 == "+" || $0 == "-" }) {
                time = String(time[time.startIndex..<cut])
            }
            let parts = time.split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            hour = parts[0]
            minute = parts[1]
            hasTime = true
        }

        let year = dateNumbers[0]
        let month = dateNumbers[1]
        let day = dateNumbers[2]

        guard (1970...2200).contains(year),
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        var components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )

        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard check.year == year,
              check.month == month,
              check.day == day,
              check.hour == hour,
              check.minute == minute else {
            return nil
        }

        // The classic LLM failure: the image says 10/29 and the model picks the
        // previous year. Only roll forward when doing so lands the date near now,
        // so genuinely old timeline files are left alone.
        var resolvedDate = date
        var correctedYear = false
        if year == calendar.component(.year, from: now) - 1 {
            var shifted = components
            shifted.year = year + 1
            if let candidate = calendar.date(from: shifted) {
                let past = now.timeIntervalSince(date)
                let future = candidate.timeIntervalSince(now)
                if past > 180 * 86_400, future >= 0, future <= 180 * 86_400 {
                    components = shifted
                    resolvedDate = candidate
                    correctedYear = true
                }
            }
        }

        return ParsedTimestamp(
            date: resolvedDate,
            year: components.year ?? year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            hasTime: hasTime,
            correctedYear: correctedYear
        )
    }

    // MARK: - Helpers

    private static func isFixedGenshinEndgame(_ title: String) -> Bool {
        let token = title.lowercased()
        return token.contains("spiral abyss") || token.contains("imaginarium")
    }

    private static func resolveKind(_ raw: String?) -> TimelineKind? {
        guard let raw, let trimmed = trimmed(raw) else { return .event }
        return TimelineKind(raw: trimmed)
    }

    /// Midnight on the printed calendar day, in the phone's calendar. Building it
    /// from components rather than converting the server instant is deliberate:
    /// `Asia/Shanghai` midnight is the previous evening in IST, and an all-day
    /// entry must stay on the day the timeline printed.
    private static func localMidnight(_ timestamp: ParsedTimestamp) -> Date? {
        Calendar.current.date(
            from: DateComponents(year: timestamp.year, month: timestamp.month, day: timestamp.day)
        )
    }

    private static func instant(
        _ timestamp: ParsedTimestamp,
        minutes: Int,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            from: DateComponents(
                year: timestamp.year,
                month: timestamp.month,
                day: timestamp.day,
                hour: minutes / 60,
                minute: minutes % 60
            )
        )
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func inclusiveDayCount(from start: ParsedTimestamp, to end: ParsedTimestamp) -> Int? {
        guard let first = utcCalendar.date(
            from: DateComponents(year: start.year, month: start.month, day: start.day)
        ),
        let last = utcCalendar.date(
            from: DateComponents(year: end.year, month: end.month, day: end.day)
        ) else { return nil }

        return utcCalendar.dateComponents([.day], from: first, to: last).day.map { $0 + 1 }
    }

    private static func composeNotes(for row: ParsedRow, source: String) -> String? {
        var lines: [String] = []
        if let group = row.group {
            lines.append("[\(group)]")
        }
        if !row.featured.isEmpty {
            lines.append("Featured: \(row.featured.joined(separator: ", "))")
        }
        if let notes = row.notes {
            lines.append(notes)
        }
        if let sourceLine = row.sourceLine {
            lines.append("Timeline: \(sourceLine)")
        }
        lines.append("Imported from \(source)")
        return lines.joined(separator: "\n")
    }

    private static func manualKey(title: String, date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let day = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(day)"
    }

    private static func normalizedSlug(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let slug = raw
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !slug.isEmpty else { return nil }
        return String(slug.prefix(80))
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
