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
    /// Where the iPhone was when it was logged (see `PaymentPlace`), and that place's name,
    /// looked up the first time the expense is opened. Optional: CloudKit-safe additions.
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
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
    /// How much counts toward the budget and every total (`CountedAmount`): `nil` is all of it,
    /// as every expense from before this existed; `0` is «No cuenta». A share in between is kept
    /// for later. `amount` stays the real amount. Optional: a lightweight, CloudKit-safe addition.
    var countedAmount: Decimal?
    /// Why it doesn't count (`UncountedReason.rawValue`). Kept when it counts again, so turning
    /// «No cuenta» back on brings the same reason. Optional, like the above.
    var uncountedReason: String?

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

    /// What adds up: the amount, or none of it when it doesn't count.
    var counted: Decimal { CountedAmount.effective(amount: amount, counted: countedAmount) }

    /// «No cuenta»: in the list with its amount, but in no total.
    var isUncounted: Bool { CountedAmount.isUncounted(countedAmount) }

    /// Why it doesn't count, if it was said.
    var reason: UncountedReason? { UncountedReason(rawValue: uncountedReason ?? "") }

    /// Leaves it out of the budget, for `reason`.
    func markUncounted(_ reason: UncountedReason) {
        countedAmount = 0
        uncountedReason = reason.rawValue
    }

    /// Counts in full again. The reason stays, for if it is left out once more.
    func markCounted() {
        countedAmount = nil
    }

    /// As every total sees it: the screen, Siri and the notice all add up this, so they can
    /// never disagree. The only place an `ExpenseAmount` is made from an expense.
    var asAmount: ExpenseAmount {
        ExpenseAmount(value: counted, currencyMarker: currencyMarker, date: date, category: category,
                      excluded: CountedAmount.excluded(amount: amount, counted: countedAmount))
    }

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
