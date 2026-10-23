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
        // Same second, same amount, same merchant: the same expense (an export re-imported).
        var seen = Set(existing.map { key($0.date, $0.amount, $0.merchant) })
        var summary = Summary(unreadable: parsed.skipped)
        for record in parsed.records {
            let k = key(record.date, record.amount, record.merchant)
            guard !seen.contains(k) else { summary.alreadyThere += 1; continue }
            seen.insert(k)
            let category = record.category
                ?? CategoryMemory.remembered(for: record.merchant, rules: rules, latest: latest, hidden: hidden)
            context.insert(Expense(amount: record.amount, currencyMarker: record.currency,
                                   merchant: record.merchant, card: record.card,
                                   date: record.date, category: category))
            summary.added += 1
        }
        if summary.added > 0 { try context.save() }
        return summary
    }

    private static func key(_ date: Date, _ amount: Decimal, _ merchant: String) -> String {
        let name = merchant.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
        // Whole seconds, floored like the export writes them: rounding put 12:00:20.7 at :21
        // while the file said :20, and the same expense came in twice.
        return "\(Int(date.timeIntervalSince1970.rounded(.down)))|\(amount)|\(name)"
    }
}
