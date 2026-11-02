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
    /// While a draft: the currencies whose rate was already looked at (`MoneyWords.encodeCodes`),
    /// so reopening the cut doesn't ask them again (2026-11-02 audit). Empty once finished.
    var reviewedRates: String = ""
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

    var lines: [MoneyLine] { lines(withArchived: true) }

    func lines(withArchived: Bool) -> [MoneyLine] {
        (entries ?? []).compactMap { entry in
            guard let account = entry.account, withArchived || !account.archived else { return nil }
            return MoneyLine(kind: account.kind, currency: account.currency, balance: entry.balance)
        }
    }

    /// The cut as it was made: past cuts keep every account, archived ones too.
    var netWorth: NetWorth { NetWorth(lines: lines, main: mainCurrency, rates: rateTable) }

    /// Today's view of the latest cut: an account archived since no longer adds up, so the
    /// figure matches the accounts listed under it.
    var activeNetWorth: NetWorth {
        NetWorth(lines: lines(withArchived: false), main: mainCurrency, rates: rateTable)
    }

    func entry(for account: MoneyAccount) -> MoneyEntry? {
        (entries ?? []).first { $0.account?.id == account.id }
    }

    /// Every line by its account, archived ones too: the cut as it was made.
    var linesByAccount: MoneyChange.Cut<UUID> {
        var lines: [UUID: MoneyLine] = [:]
        for entry in entries ?? [] {
            guard let account = entry.account else { continue }
            lines[account.id] = MoneyLine(kind: account.kind, currency: account.currency, balance: entry.balance)
        }
        return MoneyChange.Cut(lines: lines, main: mainCurrency, rates: rateTable)
    }

    /// «+$1,000 desde sep» (second audit, 2026-11-02): what changed since `previous`, over the
    /// accounts both cuts have. Archiving one later doesn't turn it into a loss, and one added
    /// after `previous` (its first balance) doesn't count as saved.
    func change(since previous: MoneyCut) -> Decimal {
        let latest = linesByAccount
        return MoneyChange.since(previous: previous.linesByAccount, latest: latest, counting: Set(latest.lines.keys))
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
    /// When it stopped counting (archived, or replaced by a new amount). Optional (2026-11-02).
    var until: Date?

    init(name: String, institution: String?, amount: Decimal, currency: String, since: Date = .now) {
        self.name = name
        self.institution = institution
        self.amount = amount
        self.currency = currency
        self.since = since
    }
}

/// A line written in a row, before it's saved: an account, a debt, money owed, or an income.
/// An amount typed in «Mi dinero» (2026-11-02): the point is the decimal («18.125» is never
/// 18,125), commas only group thousands, and never more than cents, since no account holds a
/// fraction of one. A word after it («25 mil») isn't a currency, so it doesn't read.
enum MoneyAmount {
    static func read(_ text: String) -> Decimal? { MoneyTyping.amount(text) }
}

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
        // A cut being written gets the new lines too, or finishing it would leave them out.
        let openDrafts = accounts.isEmpty ? [] : try drafts(in: context).filter { MoneyMath.belongs(createdAt: now, to: $0.month) }
        // This month's rates may be updated; an older cut keeps the rates it was made with.
        for target in [cut].compactMap({ $0 }) + openDrafts {
            for (code, rate) in rates { setRate(rate, for: code, in: target, now: now) }
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
            for draft in openDrafts {
                let copy = MoneyEntry(balance: line.amount, account: account, reviewed: true)
                context.insert(copy)
                copy.cut = draft
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Its own file next to the expenses' store, never synced.
    static let url = URL.applicationSupportDirectory.appending(path: "dinero.store")

    /// Opened on first use and kept once it opens. A failure isn't kept: the next ask tries
    /// again, so a store that was busy or locked at launch doesn't stay shut until a restart.
    static var opened: Result<ModelContainer, Error> {
        openLock.lock()
        defer { openLock.unlock() }
        if let container = openedContainer { return .success(container) }
        let result = Result { () throws -> ModelContainer in
            #if DEBUG
            if DemoData.isMoneyDemoRequested { return try MoneyDemo.makeContainer() }
            #endif
            let configuration = ModelConfiguration("dinero", schema: Schema(models), url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: Schema(models), configurations: configuration)
        }
        if case .success(let container) = result { openedContainer = container }
        return result
    }

    /// Whether «Mi dinero» was ever written on this phone: a file that exists and doesn't open
    /// is a problem to say out loud, never an empty «Mi dinero».
    static var hasFile: Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// Forgets the container kept by `opened`, so the next ask opens the file again: a restore
    /// that set a damaged store aside makes a new one in its place (2026-11-02, second audit).
    static func forget() {
        openLock.lock()
        defer { openLock.unlock() }
        openedContainer = nil
    }

    private static let openLock = NSLock()
    nonisolated(unsafe) private static var openedContainer: ModelContainer?

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
    /// money saved; the next cut takes it from there. A cut being written gets it too, already
    /// looked at: otherwise finishing that cut would leave it out (or, the same month, delete
    /// the only line it has).
    @discardableResult
    static func add(_ account: MoneyAccount, balance: Decimal, rate: Decimal?, in context: ModelContext,
                    mainCurrency: String, now: Date = .now, defaults: UserDefaults = .standard) throws -> MoneyCut {
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
        var kept = false
        // Not into a draft of a month before it existed (second audit): finishing that cut
        // carries it over instead.
        for draft in try drafts(in: context) where MoneyMath.belongs(createdAt: account.createdAt, to: draft.month) {
            let line = MoneyEntry(balance: balance, account: account, reviewed: true)
            context.insert(line)
            line.cut = draft
            kept = setRate(rate, for: account.currency, in: draft, now: now) || kept
        }
        kept = setRate(rate, for: account.currency, in: cut, now: now) || kept
        do { try context.save() } catch { context.rollback(); throw error }
        if !kept { keepForNextCut(rate, for: account.currency, mainCurrency: cut.mainCurrency, defaults: defaults) }
        return cut
    }

    // MARK: A rate typed between cuts

    /// Where a rate typed in «Nueva cuenta» or «Cuenta» waits when the latest cut is of a past
    /// month that already has one (it keeps the rate it was made with) and no cut is being
    /// written: the next cut starts from it (second audit, 2026-11-02). Not a figure of the
    /// person's money, so it can live outside the store.
    static let pendingRatesKey = "dinero.cambiosPendientes"

    static func pendingRates(_ defaults: UserDefaults = .standard) -> [String: Decimal] {
        MoneyMath.decodeRates(defaults.string(forKey: pendingRatesKey))
    }

    private static func keepForNextCut(_ rate: Decimal?, for currency: String, mainCurrency: String, defaults: UserDefaults) {
        guard let rate, rate > 0, currency != mainCurrency else { return }
        var table = pendingRates(defaults)
        table[currency] = rate
        defaults.set(MoneyMath.encodeRates(table), forKey: pendingRatesKey)
    }

    /// Whether a rate typed now for `currency` would wait for the next cut instead of changing
    /// the latest one: the sheet says so.
    static func rateWaits(for currency: String, in context: ModelContext, now: Date = .now) -> Bool {
        guard let latest = latestCut(in: context), currency != latest.mainCurrency,
              ((try? drafts(in: context)) ?? []).isEmpty else { return false }
        return latest.month != MoneyMath.monthKey(of: now) && latest.rateTable[currency] != nil
    }

    /// An exchange rate written today goes into a cut of this month (or a draft, which is
    /// today's), or fills one a past cut never had. A past cut keeps the rate it was made with.
    /// Whether it was kept there.
    @discardableResult
    private static func setRate(_ rate: Decimal?, for currency: String, in cut: MoneyCut, now: Date) -> Bool {
        guard let rate, rate > 0, currency != cut.mainCurrency else { return true }
        var table = cut.rateTable
        guard cut.isDraft || cut.month == MoneyMath.monthKey(of: now) || table[currency] == nil else { return false }
        table[currency] = rate
        cut.rateTable = table
        return true
    }

    /// Cuts being written, of any month.
    static func drafts(in context: ModelContext) throws -> [MoneyCut] {
        try context.fetch(FetchDescriptor<MoneyCut>(predicate: #Predicate { $0.isDraft }, sortBy: [SortDescriptor(\.month)]))
    }

    /// The month a new cut is most likely for: the one that just ended in the first days of a
    /// month (the statements arrive then), this one after that.
    static let lateCutDays = 7

    /// Never a month before the latest finished cut (`latest`, «2026-10»): a cut there would
    /// go behind it (second audit, 2026-11-02).
    static func suggestedMonths(now: Date = .now, latest: String? = nil, calendar: Calendar = .current) -> [String] {
        MoneyMath.cutMonths(now: now, latest: latest, lateDays: lateCutDays, calendar: calendar)
    }

    /// The finished cut of a month, if it has one.
    static func finishedCut(of month: String, in context: ModelContext) throws -> MoneyCut? {
        try context.fetch(FetchDescriptor<MoneyCut>(predicate: #Predicate { $0.month == month && !$0.isDraft })).first
    }

    /// The cut being written, if there's one (of any month): it's finished or dropped before a
    /// new one starts, so nothing typed is left behind in an old month.
    static func openDraft(in context: ModelContext) throws -> MoneyCut? {
        guard let draft = try drafts(in: context).last else { return nil }
        try complete(draft, in: context)
        return draft
    }

    /// A month's cut being written: that month's draft, or a new one with every active account
    /// waiting to be reviewed (the last balance kept as the starting value, never as an answer).
    static func draft(for month: String, in context: ModelContext, now: Date = .now, mainCurrency: String,
                      defaults: UserDefaults = .standard) throws -> MoneyCut {
        let mine = try context.fetch(FetchDescriptor<MoneyCut>(predicate: #Predicate { $0.month == month }))
        if let draft = mine.first(where: \.isDraft) {
            try complete(draft, in: context)
            return draft
        }
        let previous = cut(before: month, in: context)
        let draft = MoneyCut(month: month, date: now, mainCurrency: previous?.mainCurrency ?? mainCurrency, isDraft: true)
        // A rate typed since the last cut (`pendingRates`) is where this one starts.
        var rates = previous?.rateTable ?? [:]
        let pending = pendingRates(defaults)
        for (code, rate) in pending where code != draft.mainCurrency { rates[code] = rate }
        draft.rateTable = rates
        context.insert(draft)
        // An account created after the month isn't asked for in it (second audit).
        for account in try context.fetch(activeAccounts) where MoneyMath.belongs(createdAt: account.createdAt, to: month) {
            let entry = MoneyEntry(balance: previous?.entry(for: account)?.balance ?? 0, account: account, reviewed: false)
            context.insert(entry)
            entry.cut = draft
        }
        do { try context.save() } catch { context.rollback(); throw error }
        if !pending.isEmpty { defaults.removeObject(forKey: pendingRatesKey) }
        return draft
    }

    static func draftForThisMonth(in context: ModelContext, now: Date = .now, mainCurrency: String) throws -> MoneyCut {
        try draft(for: MoneyMath.monthKey(of: now), in: context, now: now, mainCurrency: mainCurrency)
    }

    /// The finished cut a draft starts from: the same month's (being redone) or the latest one
    /// before it. Never a later month's.
    static func cut(before month: String, in context: ModelContext) -> MoneyCut? {
        var descriptor = FetchDescriptor<MoneyCut>(predicate: #Predicate { !$0.isDraft && $0.month <= month },
                                                   sortBy: [SortDescriptor(\.month, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Brings a draft up to date: an account added since gets its line (waiting to be looked
    /// at), and one archived since leaves, unless it was already written.
    static func complete(_ draft: MoneyCut, in context: ModelContext) throws {
        let active = try context.fetch(activeAccounts)
        let have = Set((draft.entries ?? []).compactMap { $0.account?.id })
        let previous = cut(before: draft.month, in: context)
        var changed = false
        for account in active where !have.contains(account.id)
            && MoneyMath.belongs(createdAt: account.createdAt, to: draft.month) {
            let entry = MoneyEntry(balance: previous?.entry(for: account)?.balance ?? 0, account: account, reviewed: false)
            context.insert(entry)
            entry.cut = draft
            changed = true
        }
        for entry in draft.entries ?? [] where entry.account?.archived == true && !entry.reviewed {
            context.delete(entry)
            changed = true
        }
        if changed {
            do { try context.save() } catch { context.rollback(); throw error }
        }
    }

    enum CutProblem: Error, Equatable {
        /// The month already has a finished cut, made on that date: ask before replacing it.
        case monthHasCut(Date)
    }

    /// Saves a reviewed draft as its month's cut. A month has one cut: if it already has one,
    /// it's replaced only when the person said so (`replacing`); otherwise this throws
    /// `CutProblem.monthHasCut` and nothing changes. Lines the old cut had and the draft
    /// doesn't (an account added while it was being written) move to the draft first, so
    /// replacing never deletes a balance with it.
    static func finish(_ draft: MoneyCut, replacing: Bool = false, in context: ModelContext, now: Date = .now) throws {
        let month = draft.month
        let others = try context.fetch(FetchDescriptor<MoneyCut>(predicate: #Predicate { $0.month == month && !$0.isDraft }))
            .filter { $0.id != draft.id }
        if let old = others.first, !replacing { throw CutProblem.monthHasCut(old.date) }
        let have = Set((draft.entries ?? []).compactMap { $0.account?.id })
        var moved = have
        for old in others {
            for entry in old.entries ?? [] {
                guard let account = entry.account, !moved.contains(account.id) else { continue }
                let line = MoneyEntry(balance: entry.balance, account: account, reviewed: true)
                line.yieldOverride = entry.yieldOverride
                line.movement = entry.movement
                context.insert(line)
                line.cut = draft
                moved.insert(account.id)
            }
            var table = draft.rateTable
            for (code, rate) in old.rateTable where table[code] == nil { table[code] = rate }
            draft.rateTable = table
            context.delete(old)
        }
        // An account created after this month isn't in its cut, but lives in the cut before
        // (where it was added): it goes on with that balance, already looked at, so becoming
        // the latest cut never drops it from the net worth (second audit, 2026-11-02).
        if let before = cut(before: month, in: context), before.id != draft.id, before.month < month {
            for entry in before.entries ?? [] {
                guard let account = entry.account, !account.archived, !moved.contains(account.id),
                      !MoneyMath.belongs(createdAt: account.createdAt, to: month) else { continue }
                let line = MoneyEntry(balance: entry.balance, account: account, reviewed: true)
                line.yieldOverride = entry.yieldOverride
                context.insert(line)
                line.cut = draft
                moved.insert(account.id)
                if account.currency != draft.mainCurrency, draft.rateTable[account.currency] == nil,
                   let rate = before.rateTable[account.currency] {
                    var table = draft.rateTable
                    table[account.currency] = rate
                    draft.rateTable = table
                }
            }
        }
        draft.isDraft = false
        draft.date = now
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Changes today's balance (and the exchange rate) of an account in the latest cut, and in a
    /// cut being written, where it counts as looked at.
    static func update(_ account: MoneyAccount, balance: Decimal, rate: Decimal?, in context: ModelContext,
                       now: Date = .now, defaults: UserDefaults = .standard) throws {
        let cuts = [latestCut(in: context)].compactMap { $0 } + (try drafts(in: context))
        var kept = cuts.isEmpty
        for cut in cuts {
            if let entry = cut.entry(for: account) {
                entry.balance = balance
                if cut.isDraft { entry.reviewed = true }
            } else if !cut.isDraft || MoneyMath.belongs(createdAt: account.createdAt, to: cut.month) {
                let entry = MoneyEntry(balance: balance, account: account, reviewed: true)
                context.insert(entry)
                entry.cut = cut
            }
            kept = setRate(rate, for: account.currency, in: cut, now: now) || kept
        }
        do { try context.save() } catch { context.rollback(); throw error }
        if !kept, let main = cuts.first?.mainCurrency {
            keepForNextCut(rate, for: account.currency, mainCurrency: main, defaults: defaults)
        }
    }

    /// A line with a history: in more than one finished cut. Drafts don't count.
    static func hasHistory(_ account: MoneyAccount) -> Bool {
        (account.entries ?? []).filter { $0.cut?.isDraft != true }.count > 1
    }

    /// Removes an account written by mistake during the first time, with its lines: it has no
    /// history yet. Later, accounts are only archived.
    static func remove(_ account: MoneyAccount, in context: ModelContext) throws {
        // In more than one cut it has a history: it's archived instead, and past cuts keep it.
        if hasHistory(account) {
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
