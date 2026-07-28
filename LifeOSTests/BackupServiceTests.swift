import XCTest
import SwiftData
@testable import LifeOS

@MainActor
final class BackupServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: LifeOSSharedStore.schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    func testRoundTripPreservesEntryGraph() throws {
        let entry = sampleEntry()
        context.insert(entry)
        try context.save()

        let data = try BackupService.exportData(entries: [entry], preferences: .init(
            calendarDefaultMode: "week",
            liveActivityEnabled: true,
            liveActivityDefaultScope: "day"
        ))
        let document = try BackupService.decode(data)

        XCTAssertEqual(document.format, BackupService.formatIdentifier)
        XCTAssertEqual(document.version, BackupService.currentVersion)
        XCTAssertEqual(document.entries.count, 1)

        let dto = try XCTUnwrap(document.entries.first)
        XCTAssertEqual(dto.id, entry.id)
        XCTAssertEqual(dto.title, "Dinner")
        XCTAssertEqual(dto.locations.count, 1)
        XCTAssertEqual(dto.expenseLines.count, 2)
        XCTAssertEqual(dto.expenseBalances.count, 1)
        XCTAssertEqual(dto.notificationRules.count, 1)
        XCTAssertEqual(dto.completions.count, 1)
        XCTAssertEqual(document.preferences.calendarDefaultMode, "week")
        XCTAssertEqual(document.preferences.liveActivityEnabled, true)
    }

    func testReplaceWipesThenRestores() throws {
        let keepID = UUID()
        let old = Entry(title: "Old", category: .irl, startDate: date(2026, 1, 1))
        old.id = keepID
        context.insert(old)
        try context.save()

        let backupEntry = sampleEntry()
        let document = BackupService.makeDocument(entries: [backupEntry])

            let summary = try BackupService.replace(
                document: document,
                modelContext: context,
                entryStore: EntryStore()
            )
        XCTAssertEqual(summary.inserted, 1)
        XCTAssertEqual(summary.updated, 0)

        let remaining = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.title, "Dinner")
        XCTAssertEqual(remaining.first?.id, backupEntry.id)
        XCTAssertNotEqual(remaining.first?.id, keepID)
    }

    func testMergeInsertsAndUpdatesByID() throws {
        let sharedID = UUID()
        let existing = Entry(title: "Local Dinner", category: .irl, startDate: date(2026, 7, 1), isCompletable: true)
        existing.id = sharedID
        let existingRule = NotificationRule(
            triggerKind: .fixedTime,
            triggerDate: date(2026, 7, 1, hour: 9),
            messageTemplate: "Local",
            isActive: true
        )
        existingRule.ruleID = UUID()
        existingRule.entry = existing
        existing.notificationRules = [existingRule]
        let existingCompletion = EntryCompletion(occurrenceStart: date(2026, 7, 1), completedAt: date(2026, 7, 1, hour: 12))
        existingCompletion.entry = existing
        existing.completions = [existingCompletion]
        context.insert(existing)
        context.insert(existingRule)
        context.insert(existingCompletion)

        let otherLocal = Entry(title: "Stay Local", category: .irl, startDate: date(2026, 6, 1))
        context.insert(otherLocal)
        try context.save()

        let incoming = Entry(title: "Backup Dinner", category: .irl, startDate: date(2026, 7, 28), notes: "Updated")
        incoming.id = sharedID
        incoming.trackExpense = true
        incoming.expenseLines = [ExpenseLine(title: "Pizza", amount: 800)]
        let incomingRuleID = UUID()
        let incomingRule = NotificationRule(
            triggerKind: .ifNotCompletedBy,
            triggerDate: date(2026, 7, 28, hour: 21),
            messageTemplate: "From backup",
            isActive: false
        )
        incomingRule.ruleID = incomingRuleID
        incomingRule.entry = incoming
        incoming.notificationRules = [incomingRule]
        let newCompletion = EntryCompletion(occurrenceStart: date(2026, 7, 28), completedAt: date(2026, 7, 28, hour: 22))
        newCompletion.entry = incoming
        incoming.completions = [newCompletion]

        let brandNew = Entry(title: "Brand New", category: .game, startDate: date(2026, 7, 20))
        brandNew.gameSubCategory = .genshinImpact

        let document = BackupService.makeDocument(entries: [incoming, brandNew])
        let summary = try BackupService.merge(document: document, modelContext: context)

        XCTAssertEqual(summary.inserted, 1)
        XCTAssertEqual(summary.updated, 1)

        let all = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(all.count, 3)

        let merged = try XCTUnwrap(all.first { $0.id == sharedID })
        XCTAssertEqual(merged.title, "Backup Dinner")
        XCTAssertEqual(merged.notes, "Updated")
        XCTAssertEqual(merged.expenseLines.count, 1)
        XCTAssertEqual(merged.expenseLines.first?.title, "Pizza")

        // Existing completion kept; new completion added.
        XCTAssertEqual(merged.completions.count, 2)

        // Existing rule kept; new rule upserted by ID.
        XCTAssertEqual(merged.notificationRules.count, 2)
        let upserted = try XCTUnwrap(merged.notificationRules.first { $0.ruleID == incomingRuleID })
        XCTAssertEqual(upserted.messageTemplate, "From backup")
        XCTAssertFalse(upserted.isActive)

        XCTAssertTrue(all.contains { $0.title == "Stay Local" })
        XCTAssertTrue(all.contains { $0.title == "Brand New" })
    }

    func testDecodeRejectsWrongFormat() {
        let json = Data(#"{"format":"other","version":1,"exportedAt":"2026-07-28T00:00:00Z","preferences":{},"entries":[]}"#.utf8)
        XCTAssertThrowsError(try BackupService.decode(json)) { error in
            guard case BackupService.BackupError.invalidFormat = error else {
                return XCTFail("Expected invalidFormat, got \(error)")
            }
        }
    }

    private func sampleEntry() -> Entry {
        let entry = Entry(
            title: "Dinner",
            category: .irl,
            startDate: date(2026, 7, 28),
            notes: "Catch up",
            isCompletable: true,
            trackExpense: true
        )
        entry.locations = [LocationEntry(name: "Cafe")]
        entry.expenseLines = [
            ExpenseLine(title: "Pizza", amount: 800),
            ExpenseLine(title: "Drinks", amount: 400)
        ]
        entry.expenseBalances = [ExpenseBalance(personName: "Alex", amount: 400)]
        let rule = NotificationRule(
            triggerKind: .fixedTime,
            triggerDate: date(2026, 7, 28, hour: 20),
            messageTemplate: "Pay up",
            isActive: true
        )
        rule.entry = entry
        entry.notificationRules = [rule]
        let completion = EntryCompletion(occurrenceStart: date(2026, 7, 28), completedAt: date(2026, 7, 28, hour: 23))
        completion.entry = entry
        entry.completions = [completion]
        return entry
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }
}
