import XCTest
@testable import LifeOS

final class RecapExporterTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 10
        return calendar.date(from: components)!
    }

    func testExportContainsStatsAndSections() {
        let irl = Entry(title: "Dentist", category: .irl, startDate: date(2026, 7, 5), isCompletable: true)
        let completion = EntryCompletion(occurrenceStart: date(2026, 7, 5))
        completion.entry = irl
        irl.completions = [completion]
        irl.locations = [LocationEntry(name: "Clinic")]
        irl.trackExpense = true
        irl.expenseLines = [
            ExpenseLine(title: "Consult", amount: Decimal(string: "50")!),
            ExpenseLine(title: "Meds", amount: Decimal(string: "25.5")!)
        ]
        irl.expenseBalances = [ExpenseBalance(personName: "Alex", amount: Decimal(25))]

        let game = Entry(
            title: "Genshin Dailies",
            category: .game,
            subCategory: GameSubCategory.genshinImpact.rawValue,
            startDate: date(2026, 7, 1),
            isCompletable: true
        )
        game.recurrence = RecurrenceRule(frequency: .daily)
        game.eventType = .dailies

        let other = Entry(
            title: "Couch Co-op",
            category: .game,
            subCategory: GameSubCategory.other.rawValue,
            startDate: date(2026, 7, 3)
        )
        other.plannedActivity = "Boss rush"
        other.playedWith = ["Alex"]

        let anime = Entry(
            title: "Sample Anime",
            category: .entertainment,
            subCategory: EntertainmentSubCategory.anime.rawValue,
            startDate: date(2026, 7, 2)
        )
        anime.progress = EntryProgress(
            currentUnit: 5,
            totalUnits: 12,
            unitLabel: "episode",
            targetUnitsPerSession: 2
        )

        let exporter = RecapExporter()
        let result = exporter.export(
            entries: [irl, game, other, anime],
            range: date(2026, 7, 1)...date(2026, 7, 7, hour: 23),
            calendar: calendar
        )

        XCTAssertTrue(result.markdown.contains("# LifeOS Recap"))
        XCTAssertTrue(result.markdown.contains("## Stats"))
        XCTAssertTrue(result.markdown.contains("## IRL"))
        XCTAssertTrue(result.markdown.contains("## Games"))
        XCTAssertTrue(result.markdown.contains("## Entertainment"))
        XCTAssertTrue(result.markdown.contains("Dentist"))
        XCTAssertTrue(result.markdown.contains("@ Clinic"))
        XCTAssertTrue(result.markdown.contains("spend 75.5"))
        XCTAssertTrue(result.markdown.contains("Consult 50"))
        XCTAssertTrue(result.markdown.contains("Meds 25.5"))
        XCTAssertTrue(result.markdown.contains("Alex owes 25"))
        XCTAssertTrue(result.markdown.contains("IRL spend:"))
        XCTAssertTrue(result.markdown.contains("Owed to you:"))
        XCTAssertTrue(result.markdown.contains("(completed)"))
        XCTAssertTrue(result.markdown.contains("Genshin Dailies"))
        XCTAssertTrue(result.markdown.contains("[Dailies]"))
        XCTAssertTrue(result.markdown.contains("Game event types:"))
        XCTAssertTrue(result.markdown.contains("Couch Co-op"))
        XCTAssertTrue(result.markdown.contains("planned: Boss rush"))
        XCTAssertTrue(result.markdown.contains("with: Alex"))
        XCTAssertTrue(result.markdown.contains("Sample Anime"))
        XCTAssertTrue(result.markdown.contains("target 2/session"))
        XCTAssertTrue(result.suggestedFilename.hasSuffix(".md"))
    }

    func testEmptyRangeProducesPlaceholderSections() {
        let exporter = RecapExporter()
        let result = exporter.export(
            entries: [],
            range: date(2026, 1, 1)...date(2026, 1, 31, hour: 23),
            calendar: calendar
        )
        XCTAssertTrue(result.markdown.contains("_No entries_"))
        XCTAssertTrue(result.markdown.contains("IRL: 0 events, 0 completed"))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }
}
