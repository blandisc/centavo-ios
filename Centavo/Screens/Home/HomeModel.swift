import CentavoCore
import Foundation
import SwiftData

/// What the main screen works out from the expenses, kept until what it comes from changes.
///
/// The screen redraws for many reasons that change none of its numbers (a row swiped open, a
/// sheet, the width, a letter typed in the search). It used to walk the whole history about
/// seven times on each of them; now each piece is worked out once per change of its inputs
/// (`Memo`), and from the month on screen instead of from every month.
///
/// What it keeps is read while the screen draws, so it is not observed: only `searchText`,
/// `query`, `openRow` and `revision` redraw what reads them.
@MainActor @Observable
final class HomeModel {
    /// What is in the search field, as typed or dictated.
    var searchText = ""
    /// What is searched: `searchText` once typing pauses (`searchPause`); at once when cleared.
    var query = ""
    /// The expense row left open by a swipe, showing «Borrar». Kept here and not in the
    /// screen's state, so opening a row redraws the rows and not the hero or the carousel.
    var openRow: AnyHashable?
    /// Goes up each time the store saves, so a search on screen is asked again (an edit can
    /// make an expense match or stop matching).
    private(set) var revision = 0

    /// How long typing has to pause before the search runs over every month.
    static let searchPause = Duration.milliseconds(200)

    @ObservationIgnored private var monthMemo = Memo<MonthKey, HomeMonth>()
    @ObservationIgnored private var noteMemo = Memo<NoteKey, String?>()
    @ObservationIgnored private var searchMemo = Memo<SearchKey, HomeSearch>()
    @ObservationIgnored private var catalogMemo = Memo<[String], CategoryCatalog>()

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func storeSaved() { revision += 1 }

    // MARK: The month on screen

    /// Everything about the month on screen. `rows` are that month's expenses, newest first;
    /// `originals` the fixed expenses' first charges.
    func month(_ inputs: MonthInputs, rows: [Expense], originals: [Expense]) -> HomeMonth {
        let key = MonthKey(inputs: inputs, rows: Self.fingerprint(rows), originals: Self.fingerprint(originals))
        return monthMemo.value(for: key) { Self.makeMonth(inputs, rows: rows, originals: originals) }
    }

    private static func makeMonth(_ inputs: MonthInputs, rows: [Expense], originals: [Expense]) -> HomeMonth {
        let primary = inputs.currency
        // What doesn't count is left out here, the same way Siri leaves it out (`MonthStatus`).
        let amounts = rows.map(\.asAmount)
        let summary = MonthSummarizer.summarize(amounts, inMonthOf: inputs.viewed, primary: primary)
        let pace = TodayBudget.pace(budget: BudgetStore.amount(from: inputs.budget), rows: rows,
                                    originals: originals, plans: FixedPlan.decode(inputs.plans),
                                    primary: primary, month: inputs.viewed, now: inputs.now,
                                    mode: AllowanceMode(stored: inputs.mode))
        let shown = rows.filter { expense in
            (inputs.selectedDay.map { Calendar.current.component(.day, from: expense.date) == $0 } ?? true)
                && (inputs.selectedCategory?.contains(expense.category) ?? true)
        }
        let filtered = inputs.selectedDay != nil || inputs.selectedCategory != nil
        return HomeMonth(
            summary: summary,
            pace: pace,
            calendar: MonthCalendar.make(amounts, inMonthOf: inputs.viewed, primary: primary, today: inputs.now),
            code: monthCode(rows, inputs: inputs, pace: pace),
            shares: CategoryShare.top(summary.categories),
            returned: CategoryShare.returned(summary.categories),
            currencySwitch: inputs.isCurrent
                ? CurrencySuggestion.switchTo(markers: rows.map(\.currencyMarker), primary: primary,
                                              offered: CurrencyPreference.offered)
                : nil,
            hasExpenses: !rows.isEmpty,
            shownCount: shown.count,
            shownTotal: filtered ? DayGroup(day: inputs.viewed, items: shown).total(in: primary) : nil,
            groups: DayGroup.split(shown)
        )
    }

    // MARK: The month's barcode

    /// Each day of the viewed month added up in its currency, for the barcode under the bar.
    private static func monthCode(_ rows: [Expense], inputs: MonthInputs, pace: BudgetPace?) -> MonthCode {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: inputs.viewed)?.count ?? 31
        let byDay = Dictionary(grouping: rows) { calendar.component(.day, from: $0.date) }
        let input = (1...days).map { number -> MonthCode.DayInput in
            let dayRows = byDay[number] ?? []
            guard !dayRows.isEmpty else { return MonthCode.DayInput() }
            func sum(_ list: [Expense]) -> Decimal {
                MonthSummarizer.summarize(list.map(\.asAmount), inMonthOf: inputs.viewed,
                                          primary: inputs.currency).primary.amount
            }
            let counted = dayRows.filter { !$0.isUncounted }
            let biggest = counted.max { $0.amount < $1.amount }
            return MonthCode.DayInput(total: sum(dayRows), variable: sum(dayRows.filter { !$0.isFixed }),
                                      payments: dayRows.count, fixedPayments: dayRows.filter(\.isFixed).count,
                                      biggest: biggest.map { ($0.shownName, $0.amount) })
        }
        let today = inputs.isCurrent ? calendar.component(.day, from: inputs.now) : nil
        // The budget shared over the month's days, fixed expenses aside: the same in either rule.
        // `dailyBase` is not it with «Se reparte», where it is what is left over the days left and
        // reached $0 once the month went over (owner's iPhone, 2026-10-30).
        let limit = pace.map { max(($0.budget - $0.fixedMonth) / Decimal(days), 0) }
        return MonthCode(days: input, today: today, limitPerDay: limit)
    }

    // MARK: The note

    /// The month's most useful fact (`MonthNote`), from the last few months' `rows`.
    func note(rows: [Expense], now: Date, primary: String, budget: String) -> String? {
        let key = NoteKey(now: now, primary: primary, budget: budget, rows: Self.fingerprint(rows))
        return noteMemo.value(for: key) {
            MonthNote.facts(rows, now: now, primary: primary, budget: BudgetStore.amount(from: budget)).first?.line
        }
    }

    // MARK: Search

    /// Every expense the search asks for, from any month, newest first. Asked of the store
    /// only when the words, the store or `revision` change.
    func search(now: Date, stamp: StoreStamp, in context: ModelContext) -> HomeSearch {
        let key = SearchKey(query: query, now: now, stamp: stamp, revision: revision)
        return searchMemo.value(for: key) {
            let parsed = ExpenseSearch.query(from: key.query, now: now)
            let all = (try? context.fetch(FetchDescriptor<Expense>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
            let found = all.filter { ExpenseSearch.matches($0.searchable, parsed) }
            return HomeSearch(count: found.count, groups: DayGroup.split(found))
        }
    }

    /// Lets go of the last search's expenses once the search is closed.
    func searchClosed() { searchMemo.reset() }

    // MARK: Categories

    /// The categories someone made and the ones hidden, the cards' icons and everyone's
    /// colors, read once per change instead of once per row.
    func catalog(categories: String, hidden: String, sources: String = "",
                 categoryColors: String = "", sourceColors: String = "") -> CategoryCatalog {
        catalogMemo.value(for: [categories, hidden, sources, categoryColors, sourceColors]) {
            CategoryCatalog(custom: UserCatalog.decode(categories), hidden: UserCatalog.decodeNames(hidden),
                            sources: UserCatalog.decode(sources),
                            colors: CatalogColors(categories: categoryColors, sources: sourceColors))
        }
    }

    // MARK: What is asked of the store

    /// One month's expenses, newest first: from its first instant up to the next month's.
    static func monthRows(of month: Date) -> FetchDescriptor<Expense> {
        let bounds = MonthNavigator.bounds(of: month)
        let start = bounds.start, end = bounds.end
        return FetchDescriptor(predicate: #Predicate { $0.date >= start && $0.date < end },
                               sortBy: [SortDescriptor(\.date, order: .reverse)])
    }

    /// The last few months, for the note (`MonthNote.since`). Only this month has a note:
    /// another month asks for nothing.
    static func recentRows(now: Date, isCurrent: Bool) -> FetchDescriptor<Expense> {
        let since = isCurrent ? MonthNote.since(now) : Date.distantFuture
        return FetchDescriptor(predicate: #Predicate { $0.date >= since },
                               sortBy: [SortDescriptor(\.date, order: .reverse)])
    }

    /// The fixed expenses' first charges (`repeatsMonthly`), whatever their month.
    static var originals: FetchDescriptor<Expense> {
        FetchDescriptor(predicate: #Predicate { $0.repeatsMonthly == true },
                        sortBy: [SortDescriptor(\.date, order: .reverse)])
    }

    /// Every expense, but only its date: how many there are, the newest and the oldest. A
    /// payment that lands, a delete or an import changes it; nothing reads the rest of each row.
    static var dated: FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.propertiesToFetch = [\.date]
        return descriptor
    }

    /// The newest `limit` expenses.
    static func newest(_ limit: Int) -> FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// What of each expense the screen's numbers use: when it changes (an amount, a category,
    /// «No cuenta»), they are worked out again. Reading it is also what has the screen redraw
    /// when one of them is edited in place.
    static func fingerprint(_ rows: [Expense]) -> Int {
        var hasher = Hasher()
        hasher.combine(rows.count)
        for row in rows {
            hasher.combine(row.persistentModelID)
            hasher.combine(row.date)
            hasher.combine(row.amount)
            hasher.combine(row.countedAmount)
            hasher.combine(row.currencyMarker)
            hasher.combine(row.category)
            hasher.combine(row.merchant)
            hasher.combine(row.displayName)
            hasher.combine(row.repeatsMonthly)
            hasher.combine(row.isRepeat)
            hasher.combine(row.repeatsThrough)
            hasher.combine(row.repeatDay)
            hasher.combine(row.repeatRule)
        }
        return hasher.finalize()
    }
}

/// What the month's numbers depend on besides its expenses.
struct MonthInputs: Equatable {
    let viewed: Date
    let now: Date
    let isCurrent: Bool
    let budget: String
    let plans: String
    let currency: String
    let mode: String
    let selectedDay: Int?
    let selectedCategory: CategoryShare?
}

private struct MonthKey: Equatable {
    let inputs: MonthInputs
    let rows: Int
    let originals: Int
}

private struct NoteKey: Equatable {
    let now: Date
    let primary: String
    let budget: String
    let rows: Int
}

private struct SearchKey: Equatable {
    let query: String
    let now: Date
    let stamp: StoreStamp
    let revision: Int
}

/// How the whole store stands, cheaply: it changes when an expense comes or goes.
struct StoreStamp: Equatable {
    let count: Int
    let newest: Date?
}

/// The month on screen, worked out.
struct HomeMonth {
    let summary: MonthSummary
    let pace: BudgetPace?
    let calendar: MonthCalendar
    /// One bar per day under the budget bar, and the figures under it (`MonthCode`).
    let code: MonthCode
    let shares: [CategoryShare]
    let returned: Decimal
    /// Most of this month's payments are in this other currency: offer to add up in it.
    let currencySwitch: String?
    let hasExpenses: Bool
    /// How many the tapped day or category leaves, and what they add up to.
    let shownCount: Int
    let shownTotal: String?
    /// The list: the month, narrowed to the tapped day or category, by day.
    let groups: [DayGroup]
}

/// A search's results, by day.
struct HomeSearch {
    let count: Int
    let groups: [DayGroup]
}

/// The categories someone made (their icons), the ones hidden from the choices, the cards'
/// icons and the colors of both.
struct CategoryCatalog: Equatable {
    let custom: [LabeledIcon]
    let hidden: [String]
    var sources: [LabeledIcon] = []
    var colors: CatalogColors = .empty

    static let empty = CategoryCatalog(custom: [], hidden: [])

    func icon(for category: String) -> String { CategoryStyle.icon(for: category, custom: custom) }
    func sourceIcon(for card: String) -> String { PaymentChoices.icon(for: card, sources: sources) }

    /// The categories a long press offers: the usual ones, yours and the expense's own.
    func choices(for expense: Expense) -> [String] {
        CategoryStyle.offered(known: [], custom: custom, current: expense.category ?? "", hidden: hidden)
    }
}
