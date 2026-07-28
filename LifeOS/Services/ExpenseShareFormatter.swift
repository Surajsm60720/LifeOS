import Foundation

enum ExpenseShareFormatter {
    static func plainSettlement(for entry: Entry, occurrenceDate: Date, calendar: Calendar = .current) -> String {
        var blocks: [String] = []

        blocks.append(entry.title)

        blocks.append(DateFormatting.recapLine.string(from: occurrenceDate))

        if let locations = entry.locationSummary, !locations.isEmpty {
            blocks.append(locations)
        }

        let lines = entry.expenseLines.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.amount != 0 }
        if !lines.isEmpty || entry.trackExpense {
            var itemLines: [String] = ["Items"]
            for line in entry.expenseLines {
                let title = line.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = title.isEmpty ? "Item" : title
                itemLines.append("• \(label) — \(formatAmount(line.amount))")
            }
            itemLines.append("Total — \(formatAmount(entry.expenseTotal))")
            blocks.append(itemLines.joined(separator: "\n"))
        }

        if !entry.expenseBalances.isEmpty {
            var settlementLines: [String] = ["Settlements"]
            for balance in entry.expenseBalances {
                let name = balance.personName.trimmingCharacters(in: .whitespacesAndNewlines)
                let person = name.isEmpty ? "Someone" : name
                settlementLines.append("• \(person) owes you \(formatAmount(balance.amount))")
            }
            settlementLines.append("Owed to you — \(formatAmount(entry.expenseOwedToYou))")
            blocks.append(settlementLines.joined(separator: "\n"))

            let yourShare = entry.expenseTotal - entry.expenseOwedToYou
            blocks.append(
                "Your share (if settled): \(formatAmount(entry.expenseTotal)) − \(formatAmount(entry.expenseOwedToYou)) = \(formatAmount(yourShare))"
            )
        }

        if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            blocks.append("Notes: \(notes)")
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func formatAmount(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
