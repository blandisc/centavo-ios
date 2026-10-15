import Foundation
import SwiftData

/// One card payment captured from Apple Wallet (or entered by hand).
///
/// Every stored property has a default or is optional: that is what iCloud (CloudKit) asks of
/// a model before it will sync it. The defaults are never used by the app itself.
@Model
final class Expense {
    var amount: Decimal = 0
    var currencyMarker: String?
    var merchant: String = ""
    var card: String?
    var date: Date = Date.now
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
    ///
    /// It also syncs to the person's private iCloud when the app is signed with the iCloud
    /// entitlement (SwiftData picks the container up from it). Signed without it, as with a
    /// free developer account, it is the same store, only on the phone.
    static let opened: Result<ModelContainer, Error> = Result {
        #if DEBUG
        if DemoData.isBrokenStoreRequested { throw DemoData.DemoError.brokenStore }
        if DemoData.isRequested { return try DemoData.makeContainer() }
        #endif
        return try ModelContainer(for: Expense.self)
    }

    /// The demo modes start clean and must not pull a real budget from iCloud.
    static var syncsBudget: Bool {
        #if DEBUG
        return !DemoData.isRequested
        #else
        return true
        #endif
    }

    /// For code with no screen to show an error on (the App Intent).
    static var container: ModelContainer {
        get throws { try opened.get() }
    }
}
