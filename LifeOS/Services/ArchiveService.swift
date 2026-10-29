import Foundation

/// Period-scoped JSON extracts written alongside (but separately from) backups.
///
/// These files are **not** backups: they contain a flat, denormalized list of what
/// happened inside one month or one year, shaped so an LLM can read it cold and
/// summarize "how did my month go". Restoring one would delete everything outside
/// the window, so the document uses its own `format` identifier and
/// `BackupService.decode` rejects it.
///
/// Recurring entries are materialized per occurrence, so a daily that ran all month
/// shows up as ~30 dated rows instead of one template row with a rule attached.
enum ArchiveService {
    static let formatIdentifier = "lifeos.recap"
    static let currentVersion = 1

    enum Kind: String, Codable, CaseIterable, Sendable {
        case month
        case year

        var fileComponent: String {
            switch self {
            case .month: return "Month"
            case .year: return "Year"
            }
        }

        var calendarComponent: Calendar.Component {
            switch self {
            case .month: return .month
            case .year: return .year
            }
        }
    }

    enum ArchiveError: LocalizedError {
        case invalidFormat
        case unsupportedVersion(Int)
        case decodeFailed(String)
        case encodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "This file is not a LifeOS archive."
            case .unsupportedVersion(let version):
                return "This archive (version \(version)) was made by a newer version of LifeOS."
            case .decodeFailed(let detail):
                return "Could not read archive: \(detail)"
            case .encodeFailed(let detail):
                return "Could not write archive: \(detail)"
            }
        }
    }

    // MARK: - Period math

    struct Period: Equatable, Sendable {
        /// Inclusive first instant, e.g. 2026-09-01 00:00.
        let start: Date
        /// Exclusive end, e.g. 2026-10-01 00:00.
        let end: Date
        /// `2026-09` for months, `2026` for years.
        let label: String
    }

    static func period(_ kind: Kind, containing date: Date, calendar: Calendar = .current) -> Period {
        switch kind {
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .month, value: 1, to: start)
                ?? start.addingTimeInterval(31 * 86_400)
            return Period(start: start, end: end, label: monthLabel(start, calendar: calendar))
        case .year:
            let year = calendar.component(.year, from: date)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
                ?? calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .year, value: 1, to: start)
                ?? start.addingTimeInterval(366 * 86_400)
            return Period(start: start, end: end, label: yearLabel(start, calendar: calendar))
        }
    }

    /// The most recent fully finished month/year as of `now`.
    static func lastCompletedPeriod(_ kind: Kind, now: Date = .now, calendar: Calendar = .current) -> Period {
        let current = period(kind, containing: now, calendar: calendar)
        let anchor = calendar.date(byAdding: .second, value: -1, to: current.start) ?? current.start
        return period(kind, containing: anchor, calendar: calendar)
    }

    /// Periods still owed after `lastLabel`, oldest first, capped at `limit`.
    /// A nil label means "first time this was enabled" — only the last completed
    /// period is written, so a fresh install does not spew years of empty files.
    static func periodsToArchive(
        _ kind: Kind,
        after lastLabel: String?,
        now: Date = .now,
        limit: Int,
        calendar: Calendar = .current
    ) -> [Period] {
        let last = lastCompletedPeriod(kind, now: now, calendar: calendar)
        guard let lastLabel else { return [last] }
        if lastLabel == last.label { return [] }

        // An unreadable label is recovered by writing the latest period once, so a
        // corrupted preference can never leave the schedule stuck "due" forever.
        guard let storedStart = startDate(forLabel: lastLabel, kind: kind, calendar: calendar) else {
            return [last]
        }
        if storedStart >= last.start { return [] }

        var periods: [Period] = []
        var cursor = storedStart
        var guardCount = 0
        while cursor < last.start, guardCount < 240 {
            guardCount += 1
            guard let next = calendar.date(byAdding: kind.calendarComponent, value: 1, to: cursor),
                  next > cursor else { break }
            cursor = next
            periods.append(period(kind, containing: cursor, calendar: calendar))
        }
        return Array(periods.suffix(max(1, limit)))
    }

    static func startDate(forLabel label: String, kind: Kind, calendar: Calendar = .current) -> Date? {
        let parts = label.split(separator: "-").compactMap { Int($0) }
        switch kind {
        case .month:
            guard parts.count == 2 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
        case .year:
            guard parts.count == 1 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: 1, day: 1))
        }
    }

    static func fileName(kind: Kind, period: Period) -> String {
        "LifeOS-\(kind.fileComponent)-\(period.label).json"
    }

    /// `2026-09` → `September 2026`, `2026` → `2026`.
    static func displayName(forLabel label: String, kind: Kind, calendar: Calendar = .current) -> String {
        guard kind == .month,
              let date = startDate(forLabel: label, kind: kind, calendar: calendar) else {
            return label
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Document

    struct Document: Codable, Equatable, Sendable {
        var format: String
        var version: Int
        var kind: String
        /// `2026-09` or `2026`.
        var label: String
        /// Inclusive, `yyyy-MM-dd`.
        var periodStart: String
        /// Inclusive, `yyyy-MM-dd`.
        var periodEnd: String
        var generatedAt: Date
        /// Set when the occurrence ceiling was hit and rows were dropped.
        var truncated: Bool?
        var totals: Totals
        var entries: [Row]
    }

    struct Totals: Codable, Equatable, Sendable {
        var events: Int
        var completed: Int
        var byCategory: [String: Int]
        var byGame: [String: Int]
        var expenseTotal: Decimal
        var owedToYou: Decimal
    }

    struct Row: Codable, Equatable, Sendable {
        /// Local calendar day, `yyyy-MM-dd`, so month boundaries match the user's.
        var date: String
        var title: String
        var category: String
        var subCategory: String?
        var eventType: String?
        /// Omitted for things that cannot be completed.
        var completed: Bool?
        var durationMinutes: Int?
        var notes: String?
        var locations: [String]?
        var expenseTotal: Decimal?
        var expenseLines: [ExpenseLineItem]?
        var owedToYou: Decimal?
        var balances: [BalanceItem]?
        /// Attached once per entry, on its first occurrence in the window.
        var progress: Progress?
        var plannedActivity: String?
        var playedWith: [String]?
    }

    struct ExpenseLineItem: Codable, Equatable, Sendable {
        var name: String
        var amount: Decimal
    }

    struct BalanceItem: Codable, Equatable, Sendable {
        var person: String
        var amount: Decimal
    }

    struct Progress: Codable, Equatable, Sendable {
        var current: Int
        var total: Int?
        var unit: String
        var targetPerSession: Int?
    }

    // MARK: - Building

    static func makeDocument(
        entries: [Entry],
        kind: Kind,
        period: Period,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Document {
        let interval = DateInterval(start: period.start, end: period.end)
        let occurrences = RecurrenceEngine.shared.expandEntries(entries, in: interval, calendar: calendar)

        var rows: [Row] = []
        rows.reserveCapacity(occurrences.count)

        var expenseSeen = Set<UUID>()
        var progressSeen = Set<UUID>()

        var completedCount = 0
        var byCategory: [String: Int] = [:]
        var byGame: [String: Int] = [:]
        var expenseTotal: Decimal = 0
        var owedToYou: Decimal = 0

        for occurrence in occurrences {
            let entry = occurrence.entry
            let completed = entry.isCompletable
                ? entry.isCompleted(on: occurrence.occurrenceDate, calendar: calendar)
                : nil
            if completed == true { completedCount += 1 }

            let categoryName = entry.category.displayName
            byCategory[categoryName, default: 0] += 1
            if entry.category == .game, let game = entry.gameSubCategory {
                byGame[game.rawValue, default: 0] += 1
            }

            var row = Row(
                date: dayLabel(occurrence.occurrenceDate, calendar: calendar),
                title: entry.title,
                category: categoryName,
                subCategory: subCategoryName(for: entry),
                eventType: entry.eventType?.displayName,
                completed: completed,
                durationMinutes: durationMinutes(for: entry),
                notes: trimmed(entry.notes)
            )

            let locations = locationNames(for: entry)
            row.locations = locations.isEmpty ? nil : locations

            if entry.hasExpense, expenseSeen.insert(entry.id).inserted {
                let total = entry.expenseTotal
                expenseTotal += total
                row.expenseTotal = total

                let lines = entry.expenseLines
                    .filter { !$0.title.isEmpty || $0.amount != 0 }
                    .map { ExpenseLineItem(name: $0.title.isEmpty ? "item" : $0.title, amount: $0.amount) }
                row.expenseLines = lines.isEmpty ? nil : lines

                let owed = entry.expenseOwedToYou
                if owed > 0 {
                    owedToYou += owed
                    row.owedToYou = owed
                    let balances = entry.expenseBalances
                        .filter { !$0.personName.isEmpty }
                        .map { BalanceItem(person: $0.personName, amount: $0.amount) }
                    row.balances = balances.isEmpty ? nil : balances
                }
            }

            if let progress = entry.progress, progressSeen.insert(entry.id).inserted {
                row.progress = Progress(
                    current: progress.currentUnit,
                    total: progress.totalUnits,
                    unit: progress.unitLabel,
                    targetPerSession: progress.targetUnitsPerSession
                )
            }

            if entry.supportsSessionLog {
                row.plannedActivity = trimmed(entry.plannedActivity)
                let players = entry.playedWith
                row.playedWith = players.isEmpty ? nil : players
            }

            rows.append(row)
        }

        rows.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.title != $1.title { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return $0.category < $1.category
        }

        let endInclusive = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end

        return Document(
            format: formatIdentifier,
            version: currentVersion,
            kind: kind.rawValue,
            label: period.label,
            periodStart: dayLabel(period.start, calendar: calendar),
            periodEnd: dayLabel(endInclusive, calendar: calendar),
            generatedAt: now,
            truncated: occurrences.count >= RecurrenceEngine.maxExpandedOccurrences ? true : nil,
            totals: Totals(
                events: rows.count,
                completed: completedCount,
                byCategory: byCategory,
                byGame: byGame,
                expenseTotal: expenseTotal,
                owedToYou: owedToYou
            ),
            entries: rows
        )
    }

    // MARK: - Coding

    static func exportData(
        entries: [Entry],
        kind: Kind,
        period: Period,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Data {
        let document = makeDocument(entries: entries, kind: kind, period: period, now: now, calendar: calendar)
        return try encode(document)
    }

    static func encode(_ document: Document) throws -> Data {
        do {
            return try encoder.encode(document)
        } catch {
            throw ArchiveError.encodeFailed(error.localizedDescription)
        }
    }

    static func decode(_ data: Data) throws -> Document {
        let document: Document
        do {
            document = try decoder.decode(Document.self, from: data)
        } catch {
            throw ArchiveError.decodeFailed(error.localizedDescription)
        }
        guard document.format == formatIdentifier else {
            throw ArchiveError.invalidFormat
        }
        guard document.version <= currentVersion else {
            throw ArchiveError.unsupportedVersion(document.version)
        }
        return document
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Helpers

    private static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func monthLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private static func yearLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private static func subCategoryName(for entry: Entry) -> String? {
        switch entry.category {
        case .game: return entry.gameSubCategory?.rawValue
        case .entertainment: return entry.entertainmentSubCategory?.rawValue
        case .irl: return trimmed(entry.subCategory)
        }
    }

    private static func durationMinutes(for entry: Entry) -> Int? {
        guard let duration = entry.duration, duration > 0 else { return nil }
        return max(1, Int((duration / 60).rounded()))
    }

    private static func locationNames(for entry: Entry) -> [String] {
        let named = entry.locations.map(\.name).filter { !$0.isEmpty }
        if !named.isEmpty { return named }
        if let legacy = trimmed(entry.location) { return [legacy] }
        return []
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
