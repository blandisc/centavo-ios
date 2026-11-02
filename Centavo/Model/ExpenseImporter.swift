import CentavoCore
import Foundation
import SwiftData

/// Loads an exported CSV back in. What is already in the app stays and is not repeated.
enum ExpenseImporter {
    struct Summary: Equatable {
        var added = 0
        var alreadyThere = 0
        var unreadable = 0
    }

    /// A row without a category gets the one the owner chose for that merchant (in the app or
    /// elsewhere in the file), like a new Wallet payment; a row with one keeps it. Not the
    /// catalog's guess: an empty category in an export can be on purpose.
    static func importCSV(_ text: String, into context: ModelContext,
                          rules: CategoryRules = UserCatalog.categoryRules,
                          hidden: [String] = UserCatalog.notAutoAssigned) throws -> Summary {
        let parsed = try CSVImporter.records(from: text)
        let existing = try context.fetch(FetchDescriptor<Expense>())
        let latest = CategoryMemory.latest(in: existing.map(\.categorized) + parsed.records.map {
            CategorizedExpense(merchant: $0.merchant, category: $0.category, date: $0.date)
        })
        // Same second, amount, merchant, card and currency: the same expense (an export
        // re-imported). Counted, not just seen: two «Uber $100» logged the same moment are two
        // expenses, and a file with both brings both, minus the ones already here.
        var already: [String: Int] = [:]
        for expense in existing {
            already[key(expense.date, expense.amount, expense.merchant, expense.card, expense.currencyMarker), default: 0] += 1
        }
        var summary = Summary(unreadable: parsed.skipped)
        for record in parsed.records {
            let k = key(record.date, record.amount, record.merchant, record.card, record.currency)
            if let count = already[k], count > 0 {
                already[k] = count - 1
                summary.alreadyThere += 1
                continue
            }
            let category = record.category
                ?? CategoryMemory.remembered(for: record.merchant, rules: rules, latest: latest, hidden: hidden)
            let expense = Expense(amount: record.amount, currencyMarker: record.currency,
                                  merchant: record.merchant, card: record.card,
                                  date: record.date, category: category)
            if let part = record.countedAmount, record.counts {
                expense.countedAmount = part
                expense.uncountedReason = record.uncountedReason?.rawValue
            } else if !record.counts {
                // Without a reason in the file it just doesn't count; none is made up.
                expense.countedAmount = 0
                expense.uncountedReason = record.uncountedReason?.rawValue
            }
            context.insert(expense)
            summary.added += 1
        }
        if summary.added > 0 { try context.save() }
        return summary
    }

    private static func key(_ date: Date, _ amount: Decimal, _ merchant: String, _ card: String?,
                            _ currency: String?) -> String {
        func fold(_ text: String?) -> String {
            (text ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
        }
        // A bare «$» and the main currency are the same money; the export writes the code.
        let code = CurrencyResolver.isoCode(for: currency, primary: CurrencyPreference.current) ?? fold(currency)
        // Whole seconds, floored like the export writes them: rounding put 12:00:20.7 at :21
        // while the file said :20, and the same expense came in twice.
        return "\(Int(date.timeIntervalSince1970.rounded(.down)))|\(amount)|\(fold(merchant))|\(fold(card))|\(code)"
    }
}
