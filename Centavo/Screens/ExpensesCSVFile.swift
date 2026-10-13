import CentavoCore
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The whole expense history as a `.csv` the share sheet can hand to Archivos,
/// Mail, Numbers or anything else. Built in memory; nothing touches the network.
struct ExpensesCSVFile: Transferable {
    let text: String
    let suggestedName: String

    init(expenses: [Expense], primaryCurrency: String, now: Date = .now) {
        text = CSVExporter.csv(from: expenses.map { expense in
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
        })
        suggestedName = "Centavo-\(now.formatted(.iso8601.year().month().day())).csv"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { $0.suggestedName }
    }
}
