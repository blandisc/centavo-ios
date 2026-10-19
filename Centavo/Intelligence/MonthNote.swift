import CentavoCore
import Foundation

/// The note in the budget ticket: the most useful fact about this month, as `SpendingFacts`
/// worked it out. With the on-device model it may come reworded, once per fact, and only if
/// `FactCheck` finds the same figures in it; without it, the plain sentence.
enum MonthNote {
    /// «key|text»: the wording kept for the fact it was written for.
    static let storedKey = "notaDelMes"

    /// The facts for this month, most useful first. Only the last few months matter to them.
    static func facts(_ expenses: [Expense], now: Date, primary: String, budget: Decimal?) -> [SpendingFact] {
        let since = Calendar.current.date(byAdding: .month, value: -4, to: now) ?? now
        let records = expenses.lazy.filter { $0.date >= since }.map {
            SpendingRecord(amount: $0.amount, currencyMarker: $0.currencyMarker, merchant: $0.shownName,
                           category: $0.category, date: $0.date, isFixed: $0.isFixed)
        }
        return SpendingFacts.detect(Array(records), now: now, primary: primary, budget: budget,
                                    money: { formatMoney($0, isoCode: primary, label: primary) })
    }

    /// What to show for `fact`: the kept wording if it was written for it, else the plain line.
    static func text(for fact: SpendingFact, stored: String) -> String {
        guard stored.hasPrefix(fact.key + "|") else { return fact.line }
        return String(stored.dropFirst(fact.key.count + 1))
    }

    /// Asks the model for a wording of `fact`, once, and keeps it if it says the same.
    static func reword(_ fact: SpendingFact) async {
        let defaults = UserDefaults.standard
        guard LocalModel.isReady,
              !(defaults.string(forKey: storedKey) ?? "").hasPrefix(fact.key + "|") else { return }
        guard let text = await LocalModel.reword(fact)?.trimmingCharacters(in: .whitespacesAndNewlines),
              FactCheck.accepts(text, for: fact) else {
            // Not usable: keep the plain line for this fact rather than asking again.
            defaults.set(fact.key + "|" + fact.line, forKey: storedKey)
            return
        }
        defaults.set(fact.key + "|" + text, forKey: storedKey)
    }
}
