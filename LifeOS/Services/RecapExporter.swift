import Foundation

struct RecapExportResult {
    let markdown: String
    let suggestedFilename: String
}

struct RecapExporter {
    private let engine = RecurrenceEngine.shared

    struct Options {
        var includeIRL: Bool = true
        var includeGames: Bool = true
        var includeEntertainment: Bool = true
    }

    func export(
        entries: [Entry],
        range: ClosedRange<Date>,
        options: Options = Options(),
        calendar: Calendar = .current
    ) -> RecapExportResult {
        var irlLines: [String] = []
        var gameLines: [String] = []
        var entertainmentLines: [String] = []

        var irlCount = 0
        var irlCompleted = 0
        var gameCount = 0
        var gameCompleted = 0
        var entertainmentCount = 0
        var entertainmentUnits = 0
        var dailyCompletableDays = 0
        var dailyCompletableDoneDays = 0

        for entry in entries {
            if entry.category == .irl && !options.includeIRL { continue }
            if entry.category == .game && !options.includeGames { continue }
            if entry.category == .entertainment && !options.includeEntertainment { continue }

            let occurrences = engine.occurrences(for: entry, in: range, calendar: calendar)
            guard !occurrences.isEmpty else { continue }

            if entry.isCompletable, entry.recurrence?.frequency == .daily {
                for occurrence in occurrences {
                    dailyCompletableDays += 1
                    if entry.isCompleted(on: occurrence, calendar: calendar) {
                        dailyCompletableDoneDays += 1
                    }
                }
            }

            for occurrence in occurrences {
                let completed = entry.isCompletable && entry.isCompleted(on: occurrence, calendar: calendar)
                let dateText = DateFormatting.recapLine.string(from: occurrence)
                var line = "- \(dateText) — \(entry.title)"
                if entry.isCompletable {
                    line += completed ? " (completed)" : " (pending)"
                }
                if let progress = entry.progress {
                    line += " — \(progress.currentUnit)"
                    if let total = progress.totalUnits {
                        line += "/\(total)"
                    }
                    line += " \(progress.unitLabel)"
                }
                if let notes = entry.notes, !notes.isEmpty {
                    line += " — \(notes)"
                }

                switch entry.category {
                case .irl:
                    irlCount += 1
                    if completed { irlCompleted += 1 }
                    irlLines.append(line)
                case .game:
                    gameCount += 1
                    if completed { gameCompleted += 1 }
                    gameLines.append(line)
                case .entertainment:
                    entertainmentCount += 1
                    if let progress = entry.progress {
                        entertainmentUnits += progress.currentUnit
                    }
                    entertainmentLines.append(line)
                }
            }
        }

        let start = DateFormatting.recapRange.string(from: range.lowerBound)
        let end = DateFormatting.recapRange.string(from: range.upperBound)
        let irlRate = percent(irlCompleted, of: irlCount)
        let gameRate = percent(gameCompleted, of: gameCount)
        let dailyRate = percent(dailyCompletableDoneDays, of: dailyCompletableDays)

        var markdown = "# LifeOS Recap — \(start) to \(end)\n\n"
        markdown += "## Stats\n"
        markdown += "- IRL: \(irlCount) events, \(irlCompleted) completed (\(irlRate))\n"
        markdown += "- Games: \(gameCount) entries, \(gameCompleted) completed (\(gameRate))\n"
        markdown += "- Entertainment: \(entertainmentCount) titles, \(entertainmentUnits) units logged\n"
        if dailyCompletableDays > 0 {
            markdown += "- Daily completable hit rate: \(dailyCompletableDoneDays)/\(dailyCompletableDays) (\(dailyRate))\n"
        }
        markdown += "\n"

        if options.includeIRL {
            markdown += "## IRL\n"
            markdown += irlLines.isEmpty ? "_No entries_\n\n" : irlLines.joined(separator: "\n") + "\n\n"
        }
        if options.includeGames {
            markdown += "## Games\n"
            markdown += gameLines.isEmpty ? "_No entries_\n\n" : gameLines.joined(separator: "\n") + "\n\n"
        }
        if options.includeEntertainment {
            markdown += "## Entertainment\n"
            markdown += entertainmentLines.isEmpty ? "_No entries_\n" : entertainmentLines.joined(separator: "\n")
        }

        return RecapExportResult(
            markdown: markdown,
            suggestedFilename: "LifeOS-Recap-\(start)-\(end).md"
        )
    }

    private func percent(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "n/a" }
        let value = Int((Double(part) / Double(total) * 100).rounded())
        return "\(value)%"
    }
}
