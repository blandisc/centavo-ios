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
    /// The bank, card or place it's at («Nu», «Amex»). Optional (2026-11-01).
    var institution: String?
    /// What it is within its kind (`MoneySubtype.rawValue`): a card or a loan among debts, money
    /// lent or a bonus to come among receivables. Optional: a lightweight addition (2026-11-01).
    var subtype: String?
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

/// What a line is within its kind, for the words and the drawing that go with it.
enum MoneySubtype: String, CaseIterable {
    case account = "cuenta", investment = "inversion"
    case card = "tarjeta", loan = "prestamo", other = "otros"
    case lent = "me_deben", coming = "por_caer"
    /// What comes in each month (2026-11-01). Not a line of the net worth: it's saved as a
    /// `MoneyIncome`, never as an account; it shares the rows and words of the others.
    case income = "ingreso"

    var kind: MoneyKind {
        switch self {
        case .account, .income: .account
        case .investment: .investment
        case .card, .loan, .other: .debt
        case .lent, .coming: .receivable
        }
    }

    var name: String {
        switch self {
        case .account: "Cuenta"
        case .investment: "Inversión"
        case .card: "Tarjeta"
        case .loan: "Préstamo"
        case .other: "Otros"
        case .lent: "Me deben"
        case .coming: "Por caer"
        case .income: "Ingreso"
        }
    }

    /// The quiet line under the name in a list.
    var short: String {
        switch self {
        case .account: "cuenta"
        case .investment: "inversión · varía"
        case .card: "tarjeta"
        case .loan: "préstamo"
        case .other: "debes"
        case .lent: "me deben"
        case .coming: "por caer"
        case .income: "cada mes"
        }
    }

    /// The account's subtype, or the plain one of its kind for lines from before subtypes.
    static func of(_ account: MoneyAccount) -> MoneySubtype {
        if let raw = account.subtype, let known = MoneySubtype(rawValue: raw) { return known }
        switch account.kind {
        case .account: return .account
        case .investment: return .investment
        case .debt: return .card
        case .receivable: return .lent
        }
    }
}

/// What comes in each month (2026-11-01): a salary, a rent collected. Only incomes that repeat;
/// `since` is the month it started, so a raise later doesn't rewrite what months past should
/// have saved. Not part of the net worth.
@Model
final class MoneyIncome {
    var id: UUID = UUID()
    var name: String = ""
    var institution: String?
    var amount: Decimal = 0
    var currency: String = "MXN"
    var since: Date = Date.now
    var archived: Bool = false
    var createdAt: Date = Date.now

    init(name: String, institution: String?, amount: Decimal, currency: String, since: Date = .now) {
        self.name = name
        self.institution = institution
        self.amount = amount
        self.currency = currency
        self.since = since
    }
}

/// A line written in a row, before it's saved: an account, a debt, money owed, or an income.
struct MoneyLineToSave {
    var subtype: MoneySubtype
    var name: String
    var institution: String?
    var currency: String
    var amount: Decimal
    var yearlyRate: Decimal?
}

enum MoneyStore {
    static let models: [any PersistentModel.Type] = [MoneyAccount.self, MoneyCut.self, MoneyEntry.self, MoneyIncome.self]

    /// The incomes that count today.
    static var activeIncomes: FetchDescriptor<MoneyIncome> {
        FetchDescriptor(predicate: #Predicate { !$0.archived }, sortBy: [SortDescriptor(\.createdAt)])
    }

    /// Everything an import brought, in one save: the lines into the latest cut (the first
    /// makes it), the exchange rates into that cut, the incomes apart. All or nothing.
    static func addAll(_ lines: [MoneyLineToSave], rates: [String: Decimal], in context: ModelContext,
                       mainCurrency: String, now: Date = .now) throws {
        var order = ((try? context.fetch(activeAccounts))?.map(\.order).max() ?? -1) + 1
        let accounts = lines.filter { $0.subtype != .income }
        var cut: MoneyCut?
        if !accounts.isEmpty {
            if let latest = latestCut(in: context) {
                cut = latest
            } else {
                let first = MoneyCut(month: MoneyMath.monthKey(of: now), date: now, mainCurrency: mainCurrency, isDraft: false)
                context.insert(first)
                cut = first
            }
        }
        if let cut {
            // This month's rates may be updated; an older cut keeps the rates it was made with.
            let isThisMonth = cut.month == MoneyMath.monthKey(of: now)
            var table = cut.rateTable
            for (code, rate) in rates where code != cut.mainCurrency && rate > 0 && (isThisMonth || table[code] == nil) {
                table[code] = rate
            }
            cut.rateTable = table
        }
        for line in lines {
            if line.subtype == .income {
                context.insert(MoneyIncome(name: line.name, institution: line.institution, amount: line.amount,
                                           currency: line.currency, since: now))
                continue
            }
            let account = MoneyAccount(name: line.name, kind: line.subtype.kind, currency: line.currency,
                                       yearlyRate: line.yearlyRate, order: order)
            account.subtype = line.subtype.rawValue
            account.institution = line.institution
            order += 1
            context.insert(account)
            let entry = MoneyEntry(balance: line.amount, account: account, reviewed: true)
            context.insert(entry)
            entry.cut = cut
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

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

    /// Changes today's balance (and the exchange rate) of an account in the latest cut.
    static func update(_ account: MoneyAccount, balance: Decimal, rate: Decimal?, in context: ModelContext) throws {
        guard let cut = latestCut(in: context) else { try context.save(); return }
        if let entry = cut.entry(for: account) {
            entry.balance = balance
        } else {
            let entry = MoneyEntry(balance: balance, account: account, reviewed: true)
            context.insert(entry)
            entry.cut = cut
        }
        if let rate, account.currency != cut.mainCurrency {
            var table = cut.rateTable
            table[account.currency] = rate
            cut.rateTable = table
        }
        try context.save()
    }

    /// Removes an account written by mistake during the first time, with its lines: it has no
    /// history yet. Later, accounts are only archived.
    static func remove(_ account: MoneyAccount, in context: ModelContext) throws {
        // In more than one cut it has a history: it's archived instead, and past cuts keep it.
        if (account.entries ?? []).count > 1 {
            account.archived = true
            try context.save()
            return
        }
        for entry in account.entries ?? [] { context.delete(entry) }
        context.delete(account)
        try context.save()
    }

    /// Drops a draft (Cancelar with nothing worth keeping).
    static func discard(_ draft: MoneyCut, in context: ModelContext) throws {
        guard draft.isDraft else { return }
        context.delete(draft)
        try context.save()
    }
}
