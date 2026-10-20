import CentavoCore
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
    /// The whole Wallet notification as Atajos handed it over, so a misread merchant can be
    /// traced to the real text. Optional: a lightweight, CloudKit-safe addition.
    var rawNotice: String?
    /// A fixed expense (rent, a subscription) that logs itself again every month. Set on the
    /// original only. Optional, so adding it is a lightweight migration.
    var repeatsMonthly: Bool?
    /// On the original: the last month already logged, so a copy deleted by hand stays gone.
    var repeatsThrough: Date?
    /// On the original: the day of the month it repeats on, when the original's own date had
    /// to fall earlier (set up on the 31st in a 30-day month).
    var repeatDay: Int?
    /// On the original: how often it comes back (`RepeatRule.stored`). `nil` is every month,
    /// which is what every fixed expense from before this existed is.
    var repeatRule: String?
    /// On a copy: logged by itself from a fixed expense.
    var isRepeat: Bool?
    /// How the merchant reads on screen («Taquería El Güero» for «CLIP*MX TAQ GUERO 02»).
    /// Only for showing: `merchant` keeps what Wallet sent, for the CSV and the memory.
    var displayName: String?
    /// Where `category` came from when nobody chose it: `suggestedCategory` for the on-device
    /// model's guess. `nil` is a category someone chose (or one from before this existed).
    var categorySource: String?

    static let suggestedCategory = "sugerida"
    /// Someone took the category off on purpose: nothing suggests one again.
    static let clearedCategory = "ninguna"

    /// Fixed: the original or one of its copies.
    var isFixed: Bool { repeatsMonthly == true || isRepeat == true }

    /// How often a fixed expense comes back. `repeatsMonthly` keeps its old name: it means
    /// «repeats», at whatever rule this says.
    var rule: RepeatRule { RepeatRule(stored: repeatRule) }

    /// The name the screen shows.
    var shownName: String { displayName ?? merchant }

    /// A category the model suggested and nobody confirmed yet.
    var hasSuggestedCategory: Bool { category != nil && categorySource == Self.suggestedCategory }

    /// As a search sees it.
    var searchable: SearchableExpense {
        SearchableExpense(merchant: merchant, readableName: displayName, category: category,
                          card: card, amount: amount, date: date)
    }

    /// As the category rule sees it: a suggestion is shown but never remembered as a choice.
    var categorized: CategorizedExpense {
        CategorizedExpense(merchant: merchant, category: category, date: date,
                           isSuggested: hasSuggestedCategory)
    }

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
