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

    static func importCSV(_ text: String, into context: ModelContext) throws -> Summary {
        let parsed = try CSVImporter.records(from: text)
        let existing = try context.fetch(FetchDescriptor<Expense>())
        // Same second, same amount, same merchant: the same expense (an export re-imported).
        var seen = Set(existing.map { key($0.date, $0.amount, $0.merchant) })
        var summary = Summary(unreadable: parsed.skipped)
        for record in parsed.records {
            let k = key(record.date, record.amount, record.merchant)
            guard !seen.contains(k) else { summary.alreadyThere += 1; continue }
            seen.insert(k)
            context.insert(Expense(amount: record.amount, currencyMarker: record.currency,
                                   merchant: record.merchant, card: record.card,
                                   date: record.date, category: record.category))
            summary.added += 1
        }
        if summary.added > 0 { try context.save() }
        return summary
    }

    private static func key(_ date: Date, _ amount: Decimal, _ merchant: String) -> String {
        let name = merchant.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
        return "\(Int(date.timeIntervalSince1970.rounded()))|\(amount)|\(name)"
    }
}
