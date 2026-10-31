import CentavoCore
import Foundation
import SwiftData

// «Mi dinero» (2026-10-31): accounts, and one cut per month with each account's balance.
//
// It lives in its own store (`MoneyStore`), apart from the expenses: a problem opening it can
// never stop «Hoy» or the Wallet capture, and the expenses' store is never migrated for it.
// Every property has a default or is optional and the relationships are optional with an
// inverse, so it stays CloudKit-shaped; it still never syncs (`cloudKitDatabase: .none`).

@Model
final class MoneyAccount {
    var id: UUID = UUID()
    var name: String = ""
    /// `MoneyKind.rawValue`.
    var kindRaw: String = MoneyKind.account.rawValue
    var currency: String = "MXN"
    /// Yearly rate in percent (10.5 is 10.5%), for the yield hint. `nil`: no rate.
    var yearlyRate: Decimal?
    var order: Int = 0
    /// Accounts are archived, never deleted: past cuts keep their lines.
    var archived: Bool = false
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \MoneyEntry.account)
    var entries: [MoneyEntry]? = []

    var kind: MoneyKind {
        get { MoneyKind(rawValue: kindRaw) ?? .account }
        set { kindRaw = newValue.rawValue }
    }

    init(name: String, kind: MoneyKind, currency: String, yearlyRate: Decimal? = nil, order: Int = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.currency = currency
        self.yearlyRate = yearlyRate
        self.order = order
    }
}

@Model
final class MoneyCut {
    var id: UUID = UUID()
    /// «2026-10»: one cut per calendar month.
    var month: String = ""
    var date: Date = Date.now
    /// The main currency the cut adds up in, kept with it so a later change can't rewrite it.
    var mainCurrency: String = "MXN"
    /// `MoneyMath.encodeRates`: «USD=18.5».
    var rates: String = ""
    /// A cut being written (the sheet is open, or was left half-done). Never counts: every
    /// query that adds up goes through `MoneyCut.finished`.
    var isDraft: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \MoneyEntry.cut)
    var entries: [MoneyEntry]? = []

    init(month: String, date: Date, mainCurrency: String, isDraft: Bool) {
        self.month = month
        self.date = date
        self.mainCurrency = mainCurrency
        self.isDraft = isDraft
    }

    /// The only way to ask for cuts that count.
    static var finished: FetchDescriptor<MoneyCut> {
        FetchDescriptor(predicate: #Predicate { !$0.isDraft }, sortBy: [SortDescriptor(\.month)])
    }

    var rateTable: [String: Decimal] {
        get { MoneyMath.decodeRates(rates) }
        set { rates = MoneyMath.encodeRates(newValue) }
    }

    var lines: [MoneyLine] {
        (entries ?? []).compactMap { entry in
            guard let account = entry.account else { return nil }
            return MoneyLine(kind: account.kind, currency: account.currency, balance: entry.balance)
        }
    }

    var netWorth: NetWorth { NetWorth(lines: lines, main: mainCurrency, rates: rateTable) }

    func entry(for account: MoneyAccount) -> MoneyEntry? {
        (entries ?? []).first { $0.account?.id == account.id }
    }
}

@Model
final class MoneyEntry {
    var balance: Decimal = 0
    /// The real yield, when the person corrected the hint. Replaces it; never adds to it.
    var yieldOverride: Decimal?
    /// Investments only: what went in (positive) or came out (negative) since the last cut.
    var movement: Decimal?
    /// The cut sheet's «revisado»: a balance typed or «Sin cambio» tapped.
    var reviewed: Bool = false
    var account: MoneyAccount?
    var cut: MoneyCut?

    init(balance: Decimal, account: MoneyAccount, reviewed: Bool) {
        self.balance = balance
        self.account = account
        self.reviewed = reviewed
    }
}

enum MoneyStore {
    static let models: [any PersistentModel.Type] = [MoneyAccount.self, MoneyCut.self, MoneyEntry.self]

    /// Its own file next to the expenses' store, never synced.
    static let opened: Result<ModelContainer, Error> = Result {
        #if DEBUG
        if DemoData.isMoneyDemoRequested { return try MoneyDemo.makeContainer() }
        #endif
        let url = URL.applicationSupportDirectory.appending(path: "dinero.store")
        let configuration = ModelConfiguration("dinero", schema: Schema(models), url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: Schema(models), configurations: configuration)
    }

    static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: Schema(models),
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// Accounts in the order they're shown, archived ones left out.
    static var activeAccounts: FetchDescriptor<MoneyAccount> {
        FetchDescriptor(predicate: #Predicate { !$0.archived },
                        sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)])
    }

    /// The latest finished cut, if any.
    static func latestCut(in context: ModelContext) -> MoneyCut? {
        var descriptor = MoneyCut.finished
        descriptor.sortBy = [SortDescriptor(\.month, order: .reverse)]
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Adds an account with today's balance to the latest cut, so the net worth shows it at
    /// once (the first account makes the first cut). Its first balance is where it starts, not
    /// money saved; the next cut takes it from there.
    @discardableResult
    static func add(_ account: MoneyAccount, balance: Decimal, rate: Decimal?, in context: ModelContext,
                    mainCurrency: String, now: Date = .now) throws -> MoneyCut {
        let order = ((try? context.fetch(activeAccounts))?.map(\.order).max() ?? -1) + 1
        account.order = order
        context.insert(account)
        let cut: MoneyCut
        if let latest = latestCut(in: context) {
            cut = latest
        } else {
            cut = MoneyCut(month: MoneyMath.monthKey(of: now), date: now, mainCurrency: mainCurrency, isDraft: false)
            context.insert(cut)
        }
        let entry = MoneyEntry(balance: balance, account: account, reviewed: true)
        context.insert(entry)
        entry.cut = cut
        if let rate, account.currency != cut.mainCurrency {
            var table = cut.rateTable
            table[account.currency] = rate
            cut.rateTable = table
        }
        try context.save()
        return cut
    }

    /// The month's cut being written: this month's draft, or a new one with every active account
    /// waiting to be reviewed (the last balance kept as the starting value, never as an answer).
    static func draftForThisMonth(in context: ModelContext, now: Date = .now, mainCurrency: String) throws -> MoneyCut {
        let month = MoneyMath.monthKey(of: now)
        let mine = try context.fetch(FetchDescriptor<MoneyCut>(predicate: #Predicate { $0.month == month }))
        if let draft = mine.first(where: \.isDraft) { return draft }
        let previous = latestCut(in: context)
        let draft = MoneyCut(month: month, date: now, mainCurrency: previous?.mainCurrency ?? mainCurrency, isDraft: true)
        draft.rates = previous?.rates ?? ""
        context.insert(draft)
        for account in try context.fetch(activeAccounts) {
            let entry = MoneyEntry(balance: previous?.entry(for: account)?.balance ?? 0, account: account, reviewed: false)
            context.insert(entry)
            entry.cut = draft
        }
        try context.save()
        return draft
    }

    /// Saves a reviewed draft as the month's cut. A cut already finished for the same month is
    /// replaced: one cut per month, the second edits the first.
    static func finish(_ draft: MoneyCut, in context: ModelContext, now: Date = .now) throws {
        let month = draft.month
        let others = try context.fetch(FetchDescriptor<MoneyCut>(predicate: #Predicate { $0.month == month && !$0.isDraft }))
        for old in others where old.id != draft.id { context.delete(old) }
        draft.isDraft = false
        draft.date = now
        try context.save()
    }

    /// Drops a draft (Cancelar with nothing worth keeping).
    static func discard(_ draft: MoneyCut, in context: ModelContext) throws {
        guard draft.isDraft else { return }
        context.delete(draft)
        try context.save()
    }
}
