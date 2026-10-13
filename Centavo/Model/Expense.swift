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
    /// Free text, remembered per merchant by `CategoryMemory`. Optional on purpose:
    /// a payment Wallet just captured hasn't been filed anywhere yet.
    var category: String?
    /// The amount text exactly as Wallet sent it, kept so a parsing bug is recoverable.
    var rawAmount: String?

    init(amount: Decimal, currencyMarker: String? = nil, merchant: String,
         card: String? = nil, date: Date = .now, category: String? = nil,
         rawAmount: String? = nil) {
        self.amount = amount
        self.currencyMarker = currencyMarker
        self.merchant = merchant
        self.card = card
        self.date = date
        self.category = category
        self.rawAmount = rawAmount
    }
}

enum Store {
    /// The on-device store, opened once. Kept as a result, not forced open: if the file is
    /// damaged or the disk is full, the app explains it instead of crashing at launch on
    /// every launch, forever.
    static let opened: Result<ModelContainer, Error> = Result {
        #if DEBUG
        if DemoData.isBrokenStoreRequested { throw DemoData.DemoError.brokenStore }
        if DemoData.isRequested { return try DemoData.makeContainer() }
        #endif
        return try ModelContainer(for: Expense.self)
    }

    /// For code with no screen to show an error on (the App Intent).
    static var container: ModelContainer {
        get throws { try opened.get() }
    }
}
