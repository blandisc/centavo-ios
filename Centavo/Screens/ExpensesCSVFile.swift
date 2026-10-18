import CentavoCore
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The whole expense history as a `.csv` the share sheet can hand to Archivos,
/// Mail, Numbers or anything else. Built in memory; nothing touches the network.
struct ExpensesCSVFile: Transferable {
    /// Plain values, copied from the models; the CSV text itself is only written when the file
    /// is actually shared, not every time the main screen redraws its menu.
    let records: [ExpenseRecord]
    let suggestedName: String

    var text: String { CSVExporter.csv(from: records) }

    init(expenses: [Expense], primaryCurrency: String, now: Date = .now) {
        records = expenses.map { expense in
            ExpenseRecord(
                date: expense.date,
                merchant: expense.merchant,
                amount: expense.amount,
                currency: CurrencyResolver.isoCode(for: expense.currencyMarker,
                                                   primary: primaryCurrency)
                    ?? expense.currencyMarker ?? primaryCurrency,
                card: expense.card,
                category: expense.category
            )
        }
        suggestedName = "AlDia-\(now.formatted(.iso8601.year().month().day())).csv"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { $0.suggestedName }
    }
}
