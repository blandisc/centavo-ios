import CentavoCore
import CoreLocation
import Foundation
import SwiftData

/// What happened to a payment the Wallet automation handed over.
enum CaptureOutcome: Equatable {
    case saved(merchant: String)
    /// The same payment was saved a moment ago.
    case duplicate(merchant: String)
    /// Wallet sent a zero amount, almost certainly a glitch.
    case empty
    /// The amount text could not be read as money.
    case unreadable
}

/// Saves one payment from the Shortcuts "Transaction" automation. It lives apart from the
/// App Intent so it can be tested with an in-memory store.
enum ExpenseRecorder {
    /// A merchant name longer than this is not a name, it is noise.
    static let maxMerchantLength = 120

    static func record(
        amountText: String,
        merchant: String?,
        card: String?,
        rawNotice: String? = nil,
        place: CLLocationCoordinate2D? = nil,
        in context: ModelContext,
        rules: CategoryRules = UserCatalog.categoryRules,
        hidden: [String] = UserCatalog.notAutoAssigned,
        renames: MerchantRenames = UserCatalog.merchantRenames,
        now: Date = .now
    ) throws -> CaptureOutcome {
        // Usually just the amount; `CaptureText` also finds it when the whole payment came.
        guard let parsed = CaptureText.amount(in: amountText) else { return .unreadable }

        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sent = name.isEmpty ? "Sin comercio" : String(name.prefix(maxMerchantLength))
        // A merchant renamed by hand comes back with its new name.
        let renamed = renames.name(for: sent)
        let merchantName = renamed ?? sent
        // A card that is only spaces is no card: it would print as an empty gap in the ledger.
        let cardName = card?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCard = (cardName?.isEmpty ?? true) ? nil : cardName

        switch CaptureGuard.check(amount: parsed.value, merchant: merchantName, card: cleanCard,
                                  at: now, recent: recentCaptures(before: now, in: context)) {
        case .empty: return .empty
        case .duplicate: return .duplicate(merchant: merchantName)
        case .save: break
        }

        let before = remembered(for: merchantName, in: context, rules: rules, hidden: hidden, now: now)
        let expense = Expense(
            amount: parsed.value,
            currencyMarker: parsed.currencyMarker,
            merchant: merchantName,
            card: cleanCard,
            date: now,
            category: before.category,
            rawAmount: amountText
        )
        expense.rawNotice = rawNotice
        expense.latitude = place?.latitude
        expense.longitude = place?.longitude
        before.apply(to: expense, withName: true)
        if let renamed { expense.displayName = renamed }
        // Only what Wallet sends gets a cleaner reading: a name someone typed is theirs.
        if expense.displayName == nil { expense.displayName = MerchantName.readable(merchantName) }
        context.insert(expense)
        try context.save()
        return .saved(merchant: merchantName)
    }

    /// Where `repairBankMerchants` left off: the moment of its last run and the cards it knew.
    static let repairedUntilKey = "repairedBankMerchantsUntil"
    static let repairedCardsKey = "repairedBankMerchantsCards"

    /// Wallet captures saved with the bank as the merchant, read again from the notice they
    /// kept. Only the bank's own lines are touched: a name someone typed is not a bank.
    ///
    /// It runs on every return to the app, so it only reads what came since its last run
    /// (kept in `defaults`); a change in the list of cards reads everything again, since a new
    /// card may make an old line readable. `defaults: nil` reads everything and keeps no mark.
    @discardableResult
    static func repairBankMerchants(in context: ModelContext,
                                    knownCards: [String] = UserCatalog.sourceNames,
                                    defaults: UserDefaults? = .standard,
                                    now: Date = .now) throws -> Int {
        let cards = knownCards.joined(separator: "\n")
        let since: Date? = defaults?.string(forKey: repairedCardsKey) == cards
            ? defaults?.object(forKey: repairedUntilKey) as? Date : nil
        let descriptor: FetchDescriptor<Expense>
        if let since {
            descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.rawNotice != nil && $0.date >= since })
        } else {
            descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.rawNotice != nil })
        }
        var fixed = 0
        for expense in try context.fetch(descriptor) {
            guard let raw = expense.rawNotice,
                  WalletNotice.looksLikeCard(expense.merchant, knownCards: knownCards),
                  let read = WalletNotice.parse(raw, knownCards: knownCards),
                  let merchant = read.merchant, merchant != expense.merchant else { continue }
            let wasReadable = expense.displayName == nil
                || expense.displayName == MerchantName.readable(expense.merchant)
            if expense.card == nil || expense.card == "" { expense.card = read.card ?? expense.merchant }
            expense.merchant = String(merchant.prefix(maxMerchantLength))
            if wasReadable { expense.displayName = MerchantName.readable(expense.merchant) }
            fixed += 1
        }
        if fixed > 0 { try context.save() }
        // Only once it all went through: a failed save reads the same lines next time.
        defaults?.set(now, forKey: repairedUntilKey)
        defaults?.set(cards, forKey: repairedCardsKey)
        return fixed
    }

    /// A payment told to Siri or the Action button: how much and where, nothing else.
    ///
    /// Not a Wallet capture, so the raw text is not kept and nothing is treated as a repeat
    /// (two coffees in a row are two coffees). A word for a currency ("89 pesos") is ignored,
    /// as in the expense sheet, so the expense stays in the month's total.
    static func recordByHand(
        amountText: String,
        merchant: String,
        card: String? = nil,
        category: String? = nil,
        in context: ModelContext,
        primary: String = CurrencyPreference.current,
        rules: CategoryRules = UserCatalog.categoryRules,
        hidden: [String] = UserCatalog.notAutoAssigned,
        now: Date = .now
    ) throws -> CaptureOutcome {
        guard let parsed = AmountParser.parse(amountText) else { return .unreadable }
        guard parsed.value != 0 else { return .empty }
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantName = name.isEmpty ? "Sin comercio" : String(name.prefix(maxMerchantLength))
        // A category said out loud is a choice: it beats the memory, and no history is read.
        let said = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = (said?.isEmpty ?? true)
            ? remembered(for: merchantName, in: context, rules: rules, hidden: hidden, now: now)
            : Remembered(category: said)
        let expense = Expense(
            amount: parsed.value,
            currencyMarker: spokenCurrency(parsed.currencyMarker, primary: primary),
            merchant: merchantName,
            card: card,
            date: now,
            category: before.category
        )
        before.apply(to: expense, withName: false)
        context.insert(expense)
        try context.save()
        return .saved(merchant: merchantName)
    }

    /// «Borrar el último gasto»: the newest expense up to now. A fixed expense (rent, a
    /// subscription) is left out: deleting it by voice would quietly stop or skip it.
    static func lastLogged(in context: ModelContext, now: Date = .now) throws -> Expense? {
        var descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date <= now },
                                                  sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = lastLoggedLookahead
        return try context.fetch(descriptor).first { !$0.isFixed }
    }

    /// How many of the newest expenses `lastLogged` looks through to skip the fixed ones.
    private static let lastLoggedLookahead = 50

    /// What Siri heard as a currency, as an ISO code: "20 dólares" is USD, "89 pesos" or no
    /// word at all is the month's currency. A code or symbol it recognizes is kept.
    static func spokenCurrency(_ marker: String?, primary: String) -> String {
        let word = (marker ?? "").lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespaces)
        if word.hasPrefix("dolar") { return "USD" }
        if word.hasPrefix("euro") { return "EUR" }
        if word.hasPrefix("peso") { return "MXN" }
        if let marker, CurrencyResolver.recognizes(marker),
           let code = CurrencyResolver.isoCode(for: marker, primary: primary) {
            return code
        }
        return primary
    }

    /// Payments saved in the last few minutes, the only ones a repeat could match.
    private static func recentCaptures(before now: Date, in context: ModelContext) -> [RecentCapture] {
        let since = now.addingTimeInterval(-CaptureGuard.duplicateWindow)
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= since })
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map {
            RecentCapture(amount: $0.amount, merchant: $0.merchant, card: $0.card, date: $0.date)
        }
    }

    /// What a merchant was filed and shown as before, so a captured payment lands in the
    /// right place without anyone touching the app.
    struct Remembered {
        var category: String?
        /// The category is the model's suggestion from last time, still unconfirmed.
        var isSuggested = false
        /// The readable name it was shown with last time.
        var name: String?

        /// `withName` only for what Wallet sends: a name someone typed or said reads as they wrote it.
        func apply(to expense: Expense, withName: Bool) {
            if isSuggested { expense.categorySource = Expense.suggestedCategory }
            if withName, let name { expense.displayName = name }
        }
    }

    /// How far back a captured payment looks to remember a merchant: a year, and at most this
    /// many expenses, newest first. Captures run in the background with little time and the
    /// history grows every month; a merchant last seen over a year ago starts over (an explicit
    /// rule still wins, it does not come from the history).
    static let memoryMonths = 12
    static let memoryLimit = 2_000

    private static func remembered(for merchant: String, in context: ModelContext,
                                   rules: CategoryRules, hidden: [String], now: Date) -> Remembered {
        let since = Calendar.current.date(byAdding: .month, value: -memoryMonths, to: now) ?? now
        var descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= since },
                                                  sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = memoryLimit
        guard let history = try? context.fetch(descriptor) else { return Remembered() }
        let key = UserCatalog.fold(merchant)
        let sameMerchant = history.filter { UserCatalog.fold($0.merchant) == key }
        let name = sameMerchant.first?.displayName
        // What you filed this merchant under before; failing that, the catalog's guess.
        if let category = CategoryMemory.suggestion(for: merchant, rules: rules,
                                                    history: history.map(\.categorized), hidden: hidden) {
            return Remembered(category: category, name: name)
        }
        // What you decided here (none, or a category since hidden) beats an old model guess.
        guard rules.choice(for: merchant) == nil else { return Remembered(name: name) }
        // Failing both, what the on-device model suggested last time, still as a suggestion.
        let suggested = sameMerchant.first { expense in
            expense.hasSuggestedCategory && !hidden.contains { UserCatalog.same($0, expense.category ?? "") }
        }
        return Remembered(category: suggested?.category, isSuggested: suggested != nil, name: name)
    }
}
