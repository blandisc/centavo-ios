import Foundation

/// The monthly budget, one amount in the primary currency.
///
/// It lives in UserDefaults (as text, to keep the cents exact) rather than in SwiftData:
/// it is a single setting, and keeping it out of the store means the `Expense` schema
/// does not change. Empty text means no budget.
enum BudgetStore {
    static let key = "monthlyBudget"

    static func amount(from stored: String) -> Decimal? {
        guard let value = Decimal(string: stored, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    static func stored(_ amount: Decimal?) -> String {
        guard let amount, amount > 0 else { return "" }
        return "\(amount)"
    }
}
