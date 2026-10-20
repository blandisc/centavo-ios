import CentavoCore
import Foundation

/// The note in the budget ticket: the most useful fact about this month, as `SpendingFacts`
/// worked it out, in its plain sentence.
enum MonthNote {
    /// The facts for this month, most useful first. Only the last few months matter to them.
    static func facts(_ expenses: [Expense], now: Date, primary: String, budget: Decimal?) -> [SpendingFact] {
        let since = Calendar.current.date(byAdding: .month, value: -4, to: now) ?? now
        let records = expenses.lazy.filter { $0.date >= since }.map {
            // By Wallet's name, so two branches stay two; said by the readable one.
            SpendingRecord(amount: $0.amount, currencyMarker: $0.currencyMarker, merchant: $0.merchant,
                           displayName: $0.displayName, category: $0.category, date: $0.date,
                           isFixed: $0.isFixed)
        }
        return SpendingFacts.detect(Array(records), now: now, primary: primary, budget: budget,
                                    money: { formatMoney($0, isoCode: primary, label: primary) })
    }
}
