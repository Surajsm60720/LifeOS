import Foundation
import SwiftData

@Model
final class ExpenseLine {
    var title: String
    var amount: Decimal

    @Relationship(inverse: \Entry.expenseLines)
    var entry: Entry?

    init(title: String = "", amount: Decimal = 0) {
        self.title = title
        self.amount = amount
    }
}

@Model
final class ExpenseBalance {
    var personName: String
    var amount: Decimal

    @Relationship(inverse: \Entry.expenseBalances)
    var entry: Entry?

    init(personName: String = "", amount: Decimal = 0) {
        self.personName = personName
        self.amount = amount
    }
}
