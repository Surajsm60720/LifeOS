import Foundation
import SwiftData

enum BackupService {
    static let formatIdentifier = "lifeos.backup"
    static let currentVersion = 1

    enum BackupError: LocalizedError {
        case invalidFormat
        case unsupportedVersion(Int)
        case decodeFailed(String)
        case encodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "This file is not a LifeOS backup."
            case .unsupportedVersion(let version):
                return "Unsupported backup version \(version)."
            case .decodeFailed(let detail):
                return "Could not read backup: \(detail)"
            case .encodeFailed(let detail):
                return "Could not write backup: \(detail)"
            }
        }
    }

    struct PreferencesDTO: Codable, Equatable, Sendable {
        var calendarDefaultMode: String?
        var liveActivityEnabled: Bool?
        var liveActivityDefaultScope: String?
    }

    struct Document: Codable, Equatable, Sendable {
        var format: String
        var version: Int
        var exportedAt: Date
        var preferences: PreferencesDTO
        var entries: [EntryDTO]
    }

    struct EntryDTO: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var categoryRaw: String
        var subCategory: String?
        var startDate: Date
        var duration: TimeInterval?
        var location: String?
        var notes: String?
        var isCompletable: Bool
        var colorOverrideHex: String?
        var expenseAmount: String?
        var expenseCategory: String?
        var trackExpense: Bool
        var eventTypeRaw: String?
        var plannedActivity: String?
        var playedWithRaw: String
        var locations: [LocationDTO]
        var expenseLines: [ExpenseLineDTO]
        var expenseBalances: [ExpenseBalanceDTO]
        var recurrence: RecurrenceDTO?
        var notificationRules: [NotificationRuleDTO]
        var progress: ProgressDTO?
        var completions: [CompletionDTO]
    }

    struct LocationDTO: Codable, Equatable, Sendable {
        var name: String
        var latitude: Double?
        var longitude: Double?
    }

    struct ExpenseLineDTO: Codable, Equatable, Sendable {
        var title: String
        var amount: String
    }

    struct ExpenseBalanceDTO: Codable, Equatable, Sendable {
        var personName: String
        var amount: String
    }

    struct RecurrenceDTO: Codable, Equatable, Sendable {
        var frequencyRaw: String
        var interval: Int
        var daysOfWeekRaw: String?
        var endDate: Date?
        var occurrenceCount: Int?
    }

    struct NotificationRuleDTO: Codable, Equatable, Sendable {
        var ruleID: UUID
        var triggerKindRaw: String
        var triggerDate: Date?
        var triggerInterval: TimeInterval?
        var messageTemplate: String
        var isActive: Bool
    }

    struct ProgressDTO: Codable, Equatable, Sendable {
        var currentUnit: Int
        var totalUnits: Int?
        var unitLabel: String
        var targetUnitsPerSession: Int?
    }

    struct CompletionDTO: Codable, Equatable, Sendable {
        var occurrenceStart: Date
        var completedAt: Date
    }

    struct ImportSummary: Equatable, Sendable {
        var inserted: Int
        var updated: Int

        var descriptionText: String {
            "Inserted \(inserted), updated \(updated)."
        }
    }

    // MARK: - Export / decode

    static func makeDocument(entries: [Entry], preferences: PreferencesDTO = currentPreferences(), exportedAt: Date = .now) -> Document {
        Document(
            format: formatIdentifier,
            version: currentVersion,
            exportedAt: exportedAt,
            preferences: preferences,
            entries: entries.map(EntryDTO.init(entry:))
        )
    }

    static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(document)
        } catch {
            throw BackupError.encodeFailed(error.localizedDescription)
        }
    }

    static func exportData(entries: [Entry], preferences: PreferencesDTO = currentPreferences()) throws -> Data {
        try encode(makeDocument(entries: entries, preferences: preferences))
    }

    static func writeTemporaryFile(entries: [Entry], preferences: PreferencesDTO = currentPreferences(), now: Date = .now) throws -> URL {
        let data = try exportData(entries: entries, preferences: preferences)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "LifeOS-Backup-\(formatter.string(from: now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func decode(_ data: Data) throws -> Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: Document
        do {
            document = try decoder.decode(Document.self, from: data)
        } catch {
            throw BackupError.decodeFailed(error.localizedDescription)
        }
        guard document.format == formatIdentifier else {
            throw BackupError.invalidFormat
        }
        guard document.version == currentVersion else {
            throw BackupError.unsupportedVersion(document.version)
        }
        return document
    }

    static func currentPreferences() -> PreferencesDTO {
        PreferencesDTO(
            calendarDefaultMode: UserDefaults.standard.string(forKey: CalendarViewMode.defaultStorageKey),
            liveActivityEnabled: UserDefaults.standard.object(forKey: LiveActivityManager.enabledStorageKey) as? Bool,
            // Retained only so older backup files (format version 1) still decode cleanly;
            // the Live Activity is Day-only now, so this preference is no longer read anywhere.
            liveActivityDefaultScope: nil
        )
    }

    static func applyPreferences(_ preferences: PreferencesDTO) {
        if let mode = preferences.calendarDefaultMode {
            UserDefaults.standard.set(mode, forKey: CalendarViewMode.defaultStorageKey)
        }
        if let enabled = preferences.liveActivityEnabled {
            UserDefaults.standard.set(enabled, forKey: LiveActivityManager.enabledStorageKey)
        }
        // preferences.liveActivityDefaultScope is intentionally ignored (see currentPreferences).
    }

    // MARK: - Import

    @MainActor
    static func replace(document: Document, modelContext: ModelContext, entryStore: EntryStore) throws -> ImportSummary {
        entryStore.deleteAll(modelContext: modelContext)
        for dto in document.entries {
            let entry = makeEntry(from: dto, modelContext: modelContext)
            modelContext.insert(entry)
        }
        try modelContext.save()
        applyPreferences(document.preferences)
        return ImportSummary(inserted: document.entries.count, updated: 0)
    }

    @MainActor
    static func merge(document: Document, modelContext: ModelContext) throws -> ImportSummary {
        let existing = (try? modelContext.fetch(FetchDescriptor<Entry>())) ?? []
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var inserted = 0
        var updated = 0

        for dto in document.entries {
            if let entry = byID[dto.id] {
                apply(dto, to: entry, modelContext: modelContext, replaceChildren: true, mergeRulesAndCompletions: true)
                updated += 1
            } else {
                let entry = makeEntry(from: dto, modelContext: modelContext)
                modelContext.insert(entry)
                byID[entry.id] = entry
                inserted += 1
            }
        }

        try modelContext.save()
        applyPreferences(document.preferences)
        return ImportSummary(inserted: inserted, updated: updated)
    }

    // MARK: - Mapping

    private static func makeEntry(from dto: EntryDTO, modelContext: ModelContext) -> Entry {
        let entry = Entry(
            title: dto.title,
            category: EntryCategory(rawValue: dto.categoryRaw) ?? .irl,
            subCategory: dto.subCategory,
            startDate: dto.startDate,
            duration: dto.duration,
            location: dto.location,
            notes: dto.notes,
            isCompletable: dto.isCompletable,
            colorOverrideHex: dto.colorOverrideHex,
            trackExpense: dto.trackExpense,
            eventTypeRaw: dto.eventTypeRaw,
            plannedActivity: dto.plannedActivity,
            playedWithRaw: dto.playedWithRaw
        )
        entry.id = dto.id
        entry.expenseAmount = decimal(from: dto.expenseAmount)
        entry.expenseCategory = dto.expenseCategory
        apply(dto, to: entry, modelContext: modelContext, replaceChildren: true, mergeRulesAndCompletions: false)
        return entry
    }

    private static func apply(
        _ dto: EntryDTO,
        to entry: Entry,
        modelContext: ModelContext,
        replaceChildren: Bool,
        mergeRulesAndCompletions: Bool
    ) {
        entry.title = dto.title
        entry.categoryRaw = dto.categoryRaw
        entry.subCategory = dto.subCategory
        entry.startDate = dto.startDate
        entry.duration = dto.duration
        entry.location = dto.location
        entry.notes = dto.notes
        entry.isCompletable = dto.isCompletable
        entry.colorOverrideHex = dto.colorOverrideHex
        entry.expenseAmount = decimal(from: dto.expenseAmount)
        entry.expenseCategory = dto.expenseCategory
        entry.trackExpense = dto.trackExpense
        entry.eventTypeRaw = dto.eventTypeRaw
        entry.plannedActivity = dto.plannedActivity
        entry.playedWithRaw = dto.playedWithRaw

        if replaceChildren {
            replaceLocations(dto.locations, on: entry, modelContext: modelContext)
            replaceExpenseLines(dto.expenseLines, on: entry, modelContext: modelContext)
            replaceExpenseBalances(dto.expenseBalances, on: entry, modelContext: modelContext)
            replaceRecurrence(dto.recurrence, on: entry, modelContext: modelContext)
            replaceProgress(dto.progress, on: entry, modelContext: modelContext)
        }

        if mergeRulesAndCompletions {
            mergeNotificationRules(dto.notificationRules, on: entry, modelContext: modelContext)
            mergeCompletions(dto.completions, on: entry, modelContext: modelContext)
        } else {
            replaceNotificationRules(dto.notificationRules, on: entry, modelContext: modelContext)
            replaceCompletions(dto.completions, on: entry, modelContext: modelContext)
        }
    }

    private static func replaceLocations(_ dtos: [LocationDTO], on entry: Entry, modelContext: ModelContext) {
        for place in entry.locations {
            modelContext.delete(place)
        }
        entry.locations = dtos.map { dto in
            let place = LocationEntry(name: dto.name, latitude: dto.latitude, longitude: dto.longitude)
            place.entry = entry
            modelContext.insert(place)
            return place
        }
    }

    private static func replaceExpenseLines(_ dtos: [ExpenseLineDTO], on entry: Entry, modelContext: ModelContext) {
        for line in entry.expenseLines {
            modelContext.delete(line)
        }
        entry.expenseLines = dtos.map { dto in
            let line = ExpenseLine(title: dto.title, amount: decimal(from: dto.amount) ?? 0)
            line.entry = entry
            modelContext.insert(line)
            return line
        }
    }

    private static func replaceExpenseBalances(_ dtos: [ExpenseBalanceDTO], on entry: Entry, modelContext: ModelContext) {
        for balance in entry.expenseBalances {
            modelContext.delete(balance)
        }
        entry.expenseBalances = dtos.map { dto in
            let balance = ExpenseBalance(personName: dto.personName, amount: decimal(from: dto.amount) ?? 0)
            balance.entry = entry
            modelContext.insert(balance)
            return balance
        }
    }

    private static func replaceRecurrence(_ dto: RecurrenceDTO?, on entry: Entry, modelContext: ModelContext) {
        if let existing = entry.recurrence {
            modelContext.delete(existing)
            entry.recurrence = nil
        }
        guard let dto else { return }
        let rule = RecurrenceRule(
            frequency: RecurrenceFrequency(rawValue: dto.frequencyRaw) ?? .daily,
            interval: dto.interval,
            daysOfWeek: nil,
            endDate: dto.endDate,
            occurrenceCount: dto.occurrenceCount
        )
        rule.daysOfWeekRaw = dto.daysOfWeekRaw
        rule.entry = entry
        entry.recurrence = rule
        modelContext.insert(rule)
    }

    private static func replaceProgress(_ dto: ProgressDTO?, on entry: Entry, modelContext: ModelContext) {
        if let existing = entry.progress {
            modelContext.delete(existing)
            entry.progress = nil
        }
        guard let dto else { return }
        let progress = EntryProgress(
            currentUnit: dto.currentUnit,
            totalUnits: dto.totalUnits,
            unitLabel: dto.unitLabel,
            targetUnitsPerSession: dto.targetUnitsPerSession
        )
        progress.entry = entry
        entry.progress = progress
        modelContext.insert(progress)
    }

    private static func replaceNotificationRules(_ dtos: [NotificationRuleDTO], on entry: Entry, modelContext: ModelContext) {
        for rule in entry.notificationRules {
            modelContext.delete(rule)
        }
        entry.notificationRules = dtos.map { makeNotificationRule(from: $0, entry: entry, modelContext: modelContext) }
    }

    private static func mergeNotificationRules(_ dtos: [NotificationRuleDTO], on entry: Entry, modelContext: ModelContext) {
        var byID = Dictionary(uniqueKeysWithValues: entry.notificationRules.map { ($0.ruleID, $0) })
        for dto in dtos {
            if let existing = byID[dto.ruleID] {
                existing.triggerKindRaw = dto.triggerKindRaw
                existing.triggerDate = dto.triggerDate
                existing.triggerInterval = dto.triggerInterval
                existing.messageTemplate = dto.messageTemplate
                existing.isActive = dto.isActive
            } else {
                let rule = makeNotificationRule(from: dto, entry: entry, modelContext: modelContext)
                entry.notificationRules.append(rule)
                byID[rule.ruleID] = rule
            }
        }
    }

    private static func makeNotificationRule(from dto: NotificationRuleDTO, entry: Entry, modelContext: ModelContext) -> NotificationRule {
        let rule = NotificationRule(
            triggerKind: NotificationTriggerKind(rawValue: dto.triggerKindRaw) ?? .ifNotCompletedBy,
            triggerDate: dto.triggerDate,
            triggerInterval: dto.triggerInterval,
            messageTemplate: dto.messageTemplate,
            isActive: dto.isActive
        )
        rule.ruleID = dto.ruleID
        rule.entry = entry
        modelContext.insert(rule)
        return rule
    }

    private static func replaceCompletions(_ dtos: [CompletionDTO], on entry: Entry, modelContext: ModelContext) {
        for completion in entry.completions {
            modelContext.delete(completion)
        }
        entry.completions = dtos.map { dto in
            let completion = EntryCompletion(occurrenceStart: dto.occurrenceStart, completedAt: dto.completedAt)
            completion.entry = entry
            modelContext.insert(completion)
            return completion
        }
    }

    private static func mergeCompletions(_ dtos: [CompletionDTO], on entry: Entry, modelContext: ModelContext) {
        let existingStarts = Set(entry.completions.map(\.occurrenceStart))
        for dto in dtos where !existingStarts.contains(dto.occurrenceStart) {
            let completion = EntryCompletion(occurrenceStart: dto.occurrenceStart, completedAt: dto.completedAt)
            completion.entry = entry
            entry.completions.append(completion)
            modelContext.insert(completion)
        }
    }

    private static func decimal(from string: String?) -> Decimal? {
        guard let string, !string.isEmpty else { return nil }
        return Decimal(string: string)
    }
}

private extension BackupService.EntryDTO {
    init(entry: Entry) {
        self.init(
            id: entry.id,
            title: entry.title,
            categoryRaw: entry.categoryRaw,
            subCategory: entry.subCategory,
            startDate: entry.startDate,
            duration: entry.duration,
            location: entry.location,
            notes: entry.notes,
            isCompletable: entry.isCompletable,
            colorOverrideHex: entry.colorOverrideHex,
            expenseAmount: entry.expenseAmount.map { NSDecimalNumber(decimal: $0).stringValue },
            expenseCategory: entry.expenseCategory,
            trackExpense: entry.trackExpense,
            eventTypeRaw: entry.eventTypeRaw,
            plannedActivity: entry.plannedActivity,
            playedWithRaw: entry.playedWithRaw,
            locations: entry.locations.map {
                BackupService.LocationDTO(name: $0.name, latitude: $0.latitude, longitude: $0.longitude)
            },
            expenseLines: entry.expenseLines.map {
                BackupService.ExpenseLineDTO(
                    title: $0.title,
                    amount: NSDecimalNumber(decimal: $0.amount).stringValue
                )
            },
            expenseBalances: entry.expenseBalances.map {
                BackupService.ExpenseBalanceDTO(
                    personName: $0.personName,
                    amount: NSDecimalNumber(decimal: $0.amount).stringValue
                )
            },
            recurrence: entry.recurrence.map {
                BackupService.RecurrenceDTO(
                    frequencyRaw: $0.frequencyRaw,
                    interval: $0.interval,
                    daysOfWeekRaw: $0.daysOfWeekRaw,
                    endDate: $0.endDate,
                    occurrenceCount: $0.occurrenceCount
                )
            },
            notificationRules: entry.notificationRules.map {
                BackupService.NotificationRuleDTO(
                    ruleID: $0.ruleID,
                    triggerKindRaw: $0.triggerKindRaw,
                    triggerDate: $0.triggerDate,
                    triggerInterval: $0.triggerInterval,
                    messageTemplate: $0.messageTemplate,
                    isActive: $0.isActive
                )
            },
            progress: entry.progress.map {
                BackupService.ProgressDTO(
                    currentUnit: $0.currentUnit,
                    totalUnits: $0.totalUnits,
                    unitLabel: $0.unitLabel,
                    targetUnitsPerSession: $0.targetUnitsPerSession
                )
            },
            completions: entry.completions.map {
                BackupService.CompletionDTO(occurrenceStart: $0.occurrenceStart, completedAt: $0.completedAt)
            }
        )
    }
}
