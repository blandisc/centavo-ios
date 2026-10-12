import Foundation
import SwiftData

/// One card payment captured from Apple Wallet (or entered by hand).
@Model
final class Expense {
    var amount: Decimal
    var currencyMarker: String?
    var merchant: String
    var card: String?
    var date: Date
    /// The amount text exactly as Wallet sent it, kept so a parsing bug is recoverable.
    var rawAmount: String?

    init(amount: Decimal, currencyMarker: String? = nil, merchant: String,
         card: String? = nil, date: Date = .now, rawAmount: String? = nil) {
        self.amount = amount
        self.currencyMarker = currencyMarker
        self.merchant = merchant
        self.card = card
        self.date = date
        self.rawAmount = rawAmount
    }
}

enum Store {
    /// One container for the app UI and the App Intent (both run in the app process).
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Expense.self)
        } catch {
            fatalError("No se pudo abrir la base local: \(error)")
        }
    }()
}
