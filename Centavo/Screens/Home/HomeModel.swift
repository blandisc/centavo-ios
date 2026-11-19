import CentavoCore
import Foundation
import SwiftData
import SwiftUI

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
    /// A finger holding the boleto and reading its days: the carousel doesn't scroll meanwhile.
    var scrubbing = false
    /// This sideways swipe began while the boleto was being read: it doesn't turn the page.
    @ObservationIgnored var swipeBlocked = false
    /// Where the carousel's pages stand, moved by the swipe over the whole top of the screen.
    let carousel = CarouselMotion()
    /// Goes up each time the store saves (here, or iCloud bringing changes), so a search on
    /// screen is asked again (an edit can make an expense match or stop matching) and the
    /// month's numbers are worked out again. Reading it is what has the screen redraw after an
    /// expense is edited in place.
    private(set) var revision = 0

    /// How long typing has to pause before the search runs over every month.
    static let searchPause = Duration.milliseconds(200)

    @ObservationIgnored private var monthMemo = Memo<MonthKey, HomeMonth>()
    @ObservationIgnored private var numbersMemo = Memo<MonthKey, MonthNumbers>()
    @ObservationIgnored private var noteMemo = Memo<NoteKey, String?>()
    @ObservationIgnored private var searchMemo = Memo<SearchKey, HomeSearch>()
    @ObservationIgnored private var catalogMemo = Memo<[String], CategoryCatalog>()

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func storeSaved() { revision += 1 }

    // MARK: The month on screen

    /// Everything about the month on screen. `rows` are that month's expenses, newest first;
    /// `originals` the fixed expenses' first charges.
    func month(_ inputs: MonthInputs, rows: [Expense], originals: [Expense]) -> HomeMonth {
        // The save counter and a light print of the rows (independent review, 2026-11-02): a
        // counter alone missed what iCloud or a restore merged after it moved.
        let key = MonthKey(inputs: inputs, rows: Self.lightPrint(rows), originals: Self.fixedPrint(originals),
                           revision: revision)
        // A tapped day or category only narrows the list: the month's numbers are the same, and
        // are kept apart so the tap doesn't work all of them out again.
        let whole = MonthKey(inputs: inputs.unfiltered, rows: key.rows, originals: key.originals, revision: revision)
        let numbers = numbersMemo.value(for: whole) { Self.makeNumbers(inputs, rows: rows, originals: originals) }
        return monthMemo.value(for: key) { Self.makeMonth(numbers, inputs: inputs, rows: rows) }
    }

    private static func makeNumbers(_ inputs: MonthInputs, rows: [Expense], originals: [Expense]) -> MonthNumbers {
        let primary = inputs.currency
        // What doesn't count is left out here, the same way Siri leaves it out (`MonthStatus`).
        let amounts = rows.map(\.asAmount)
        let summary = MonthSummarizer.summarize(amounts, inMonthOf: inputs.viewed, primary: primary)
        let pace = TodayBudget.pace(budget: BudgetStore.amount(from: inputs.budget), rows: rows,
                                    originals: originals, plans: FixedPlan.decode(inputs.plans),
                                    primary: primary, month: inputs.viewed, now: inputs.now,
                                    mode: AllowanceMode(stored: inputs.mode), history: inputs.history)
        return MonthNumbers(
            summary: summary,
            pace: pace,
            calendar: MonthCalendar.make(amounts, inMonthOf: inputs.viewed, primary: primary, today: inputs.now),
            code: monthCode(rows, inputs: inputs, pace: pace),
            shares: CategoryShare.top(summary.categories),
            returned: CategoryShare.returned(summary.categories),
            currencySwitch: inputs.isCurrent
                ? CurrencySuggestion.switchTo(markers: rows.map(\.currencyMarker), primary: primary,
                                              offered: CurrencyPreference.offered)
                : nil
        )
    }

    /// The month's numbers and its list, narrowed to the tapped day or category.
    private static func makeMonth(_ numbers: MonthNumbers, inputs: MonthInputs, rows: [Expense]) -> HomeMonth {
        let filtered = inputs.selectedDay != nil || inputs.selectedCategory != nil
        let shown = !filtered ? rows : rows.filter { expense in
            (inputs.selectedDay.map { Calendar.current.component(.day, from: expense.date) == $0 } ?? true)
                && (inputs.selectedCategory?.contains(expense.category) ?? true)
        }
        return HomeMonth(
            summary: numbers.summary,
            pace: numbers.pace,
            calendar: numbers.calendar,
            code: numbers.code,
            shares: numbers.shares,
            returned: numbers.returned,
            currencySwitch: numbers.currencySwitch,
            hasExpenses: !rows.isEmpty,
            shownCount: shown.count,
            shownTotal: filtered ? DayGroup(day: inputs.viewed, items: shown).total(in: inputs.currency) : nil,
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
    /// `reserved`: the fixed expenses still to come, which the projection adds (second audit).
    func note(rows: [Expense], now: Date, primary: String, budget: String, reserved: Decimal = 0) -> String? {
        let key = NoteKey(now: now, primary: primary, budget: budget, rows: Self.lightPrint(rows), revision: revision,
                          reserved: reserved)
        return noteMemo.value(for: key) {
            MonthNote.facts(rows, now: now, primary: primary, budget: BudgetStore.amount(from: budget),
                            reserved: reserved).first?.line
        }
    }

    // MARK: Search

    /// Every expense the search asks for, from any month, newest first. Asked of the store
    /// only when the words, the store or `revision` change.
    func search(now: Date, stamp: StoreStamp, in context: ModelContext) -> HomeSearch {
        let key = SearchKey(query: query, now: now, stamp: stamp, revision: revision)
        return searchMemo.value(for: key) {
            let parsed = ExpenseSearch.query(from: key.query, now: now)
            // Only words that ask for nothing («el», «de», on the way to «el palacio»): no
            // results, instead of every expense ever loaded on the main thread (2026-11-18).
            guard !parsed.isEmpty else { return HomeSearch(count: 0, groups: []) }
            // The store narrows it down first (audit 2026-11-02: every letter loaded every
            // expense); the exact rule (`ExpenseSearch.matches`) then decides, as before.
            let candidates = (try? context.fetch(Self.searchCandidates(for: parsed))) ?? []
            let found = candidates.filter { ExpenseSearch.matches($0.searchable, parsed) }
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

    /// What the store can rule out of a search, newest first: never fewer than
    /// `ExpenseSearch.matches` would keep. A word that can't be part of an amount must be in
    /// the merchant, its readable name, the category or the card, ignoring accents and
    /// capitals (`localizedStandardContains`); the longest one narrows the most. With only a
    /// month, the month's days, or an expense named after it («Don Julio»). With only a year,
    /// its days, a name with it or an amount that big; with only «más de» or «menos de», the
    /// amounts inside them, charges and refunds alike. With only figures to find («300»),
    /// everything: «5» is in $1.25.
    ///
    /// A word of the translation of one of the app's own names («groc» in «Groceries», «merchant»
    /// in «No merchant») is not in the store, which keeps the Spanish: it narrows to what holds
    /// it or is stored as one of those names (2026-11-19). Before, it didn't narrow at all, and
    /// in English most words scanned every expense; and «No merchant» found nothing.
    /// `display`: how a stored own name reads (the catalog's; tests pass their own).
    static func searchCandidates(for query: SearchQuery,
                                 display: (String) -> String = HomeModel.shownOwnName) -> FetchDescriptor<Expense> {
        let newestFirst = [SortDescriptor(\Expense.date, order: .reverse)]
        guard query.category == nil else { return FetchDescriptor(sortBy: newestFirst) }
        let lettered = query.words.filter { $0.contains { !$0.isNumber && $0 != "." } }
        let wordy = lettered.compactMap { word in narrowing(word, display: display) }
        if let word = wordy.max(by: { $0.word.count < $1.word.count }) {
            return FetchDescriptor(predicate: word.predicate, sortBy: newestFirst)
        }
        if query.words.isEmpty, let interval = query.interval, let month = query.monthWord {
            let start = interval.start, end = interval.end
            let named = names(containing: month)
            return FetchDescriptor(predicate: #Predicate<Expense> { expense in
                (expense.date >= start && expense.date <= end) || named.evaluate(expense)
            }, sortBy: newestFirst)
        }
        // «2026» or «más de 500» alone loaded every expense ever on the main thread, at each
        // pause of the keyboard (2026-11-18).
        if lettered.isEmpty, query.monthWord == nil, let year = query.year, let interval = query.interval {
            return FetchDescriptor(predicate: within(year: year, interval), sortBy: newestFirst)
        }
        if lettered.isEmpty, query.interval == nil, query.minAmount != nil || query.maxAmount != nil {
            return FetchDescriptor(predicate: amounts(over: query.minAmount, upTo: query.maxAmount),
                                   sortBy: newestFirst)
        }
        return FetchDescriptor(sortBy: newestFirst)
    }

    /// A year's days, a name with the year in it, or an amount the year is part of: `matches`
    /// finds «2026» in $2,026.00 and in $12,026.00, never in a smaller one (amounts are kept to
    /// cents, so its four figures can't be in the decimals). In pieces, for the CI's compiler.
    private static func within(year: Int, _ interval: DateInterval) -> Predicate<Expense> {
        let start = interval.start, end = interval.end
        let figure = Decimal(year)
        let refund = -figure
        let named = names(containing: String(year))
        let dated = #Predicate<Expense> { expense in expense.date >= start && expense.date <= end }
        let priced = #Predicate<Expense> { expense in expense.amount >= figure || expense.amount <= refund }
        return #Predicate<Expense> { expense in
            dated.evaluate(expense) || priced.evaluate(expense) || named.evaluate(expense)
        }
    }

    /// The amounts between the bounds, by their size: a refund of $600 is «más de 500» as a
    /// charge is (`matches` compares the magnitude). Each bound counting itself, so «desde» and
    /// «más de» both fit; `matches` then decides the exact edge.
    private static func amounts(over low: Decimal?, upTo high: Decimal?) -> Predicate<Expense> {
        let floor = low ?? 0
        let negativeFloor = -floor
        guard let high else {
            return #Predicate<Expense> { expense in expense.amount >= floor || expense.amount <= negativeFloor }
        }
        let negativeHigh = -high
        let charge = #Predicate<Expense> { expense in expense.amount >= floor && expense.amount <= high }
        let refund = #Predicate<Expense> { expense in
            expense.amount <= negativeFloor && expense.amount >= negativeHigh
        }
        return #Predicate<Expense> { expense in charge.evaluate(expense) || refund.evaluate(expense) }
    }

    /// How a stored own name reads in the iPhone's language: a category or «Efectivo»
    /// (`BuiltInName`), or «Sin comercio» (`Expense.shownMerchant`).
    static func shownOwnName(_ stored: String) -> String {
        stored == Expense.noMerchant ? Expense.shownMerchant(stored) : BuiltInName.localized(stored)
    }

    /// A word and what the store can keep for it. `nil` when it can't narrow: it is in the
    /// translations of too many own names («e»), and the predicate would only grow.
    private static func narrowing(_ word: String, display: (String) -> String) -> (word: String, predicate: Predicate<Expense>)? {
        let wanted = fold(word)
        let own = (BuiltInName.categories + [BuiltInName.cash]).filter { name in
            let translated = display(name)
            return translated != name && fold(translated).contains(wanted)
        }
        guard own.count <= ownNamesLimit else { return nil }
        let blank = display(Expense.noMerchant)
        let noMerchant = blank != Expense.noMerchant && fold(blank).contains(wanted)
        var found = names(containing: word)
        for name in own {
            let before = found
            let stored = filed(as: name)
            found = #Predicate<Expense> { expense in before.evaluate(expense) || stored.evaluate(expense) }
        }
        if noMerchant {
            let before = found
            let none = Expense.noMerchant
            found = #Predicate<Expense> { expense in before.evaluate(expense) || expense.merchant == none }
        }
        return (word, found)
    }

    /// More own names than this for one word and the store isn't asked to narrow.
    private static let ownNamesLimit = 6

    /// An expense whose category or card holds one of the app's own names, as it's stored
    /// (ignoring accents and capitals, as `BuiltInName.shown` does).
    private static func filed(as name: String) -> Predicate<Expense> {
        #Predicate<Expense> { expense in
            (expense.category?.localizedStandardContains(name) ?? false)
                || (expense.card?.localizedStandardContains(name) ?? false)
        }
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// An expense whose merchant, readable name, category or card holds `word`, ignoring
    /// accents and capitals. In pieces: as one expression the CI's compiler gave up on it.
    private static func names(containing word: String) -> Predicate<Expense> {
        let shop = #Predicate<Expense> { expense in
            expense.merchant.localizedStandardContains(word)
                || (expense.displayName?.localizedStandardContains(word) ?? false)
        }
        let filed = #Predicate<Expense> { expense in
            (expense.category?.localizedStandardContains(word) ?? false)
                || (expense.card?.localizedStandardContains(word) ?? false)
        }
        return #Predicate<Expense> { expense in shop.evaluate(expense) || filed.evaluate(expense) }
    }

    /// The oldest expense, one row: how far back the months go.
    static var oldest: FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Only what the month's numbers read of each row: which one, when, how much, how much
    /// counts, in what and under what. Reading them is also what has the screen redraw when
    /// one is changed in place, or by a merge.
    static func lightPrint(_ rows: [Expense]) -> Int {
        var hasher = Hasher()
        hasher.combine(rows.count)
        for row in rows {
            hasher.combine(row.persistentModelID)
            hasher.combine(row.date)
            hasher.combine(row.amount)
            hasher.combine(row.countedAmount)
            hasher.combine(row.currencyMarker)
            hasher.combine(row.category)
        }
        return hasher.finalize()
    }

    /// The fixed expenses' first charges, with how they repeat: what sets the month's fixed part.
    static func fixedPrint(_ rows: [Expense]) -> Int {
        var hasher = Hasher()
        hasher.combine(lightPrint(rows))
        for row in rows {
            hasher.combine(row.repeatsMonthly)
            hasher.combine(row.repeatsThrough)
            hasher.combine(row.repeatDay)
            hasher.combine(row.repeatRule)
        }
        return hasher.finalize()
    }

    /// The newest `limit` expenses.
    static func newest(_ limit: Int) -> FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return descriptor
    }

}

/// What the month's numbers depend on besides its expenses.
struct MonthInputs: Equatable {
    let viewed: Date
    let now: Date
    let isCurrent: Bool
    let budget: String
    /// When the budget changed (`BudgetHistory`, as stored): which one judges `viewed`.
    var history: String = ""
    let plans: String
    let currency: String
    let mode: String
    let selectedDay: Int?
    let selectedCategory: CategoryShare?

    /// The same month with nothing tapped: what its numbers depend on.
    var unfiltered: MonthInputs {
        MonthInputs(viewed: viewed, now: now, isCurrent: isCurrent, budget: budget, history: history,
                    plans: plans, currency: currency, mode: mode, selectedDay: nil, selectedCategory: nil)
    }
}

private struct MonthKey: Equatable {
    let inputs: MonthInputs
    let rows: Int
    let originals: Int
    let revision: Int
}

private struct NoteKey: Equatable {
    let now: Date
    let primary: String
    let budget: String
    let rows: Int
    let revision: Int
    let reserved: Decimal
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

/// The month's numbers: what a tapped day or category doesn't change.
private struct MonthNumbers {
    let summary: MonthSummary
    let pace: BudgetPace?
    let calendar: MonthCalendar
    let code: MonthCode
    let shares: [CategoryShare]
    let returned: Decimal
    let currencySwitch: String?
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

/// Where the carousel's two pages stand (owner, 2026-10-30, «brusca»: a finger and an animation
/// took turns moving them, and the glide stopped dead or snapped back). Now one thing moves them:
/// they follow the finger anywhere at the top of the screen and, when it lets go, glide on at its
/// speed to the page it was headed for. Its own object, so only the carousel redraws while it moves.
@MainActor @Observable
final class CarouselMotion {
    static let pageCount = 2
    /// The page they rest on, or glide to.
    var page = 0
    /// How far a finger has pulled them from `page`, in points (left is negative).
    var drag: CGFloat = 0
    /// One page's width, measured by the carousel.
    var width = CGFloat.zero
    /// Goes up each time they land on another page, for the tick.
    var landings = 0

    /// 0 on the boleto, 1 on the calendar, in between while they move; past either end the
    /// finger pulls against resistance.
    var progress: CGFloat {
        guard width > 0 else { return CGFloat(page) }
        let raw = CGFloat(page) - drag / width
        let last = CGFloat(Self.pageCount - 1)
        if raw < 0 { return raw * Theme.Size.pageEdgeResistance }
        if raw > last { return last + (raw - last) * Theme.Size.pageEdgeResistance }
        return raw
    }

    /// The finger let go after moving `dx` at `velocity` (points per second): a short swipe or a
    /// flick turns the page toward where the finger went; a flick back the other way wins.
    func release(_ dx: CGFloat, velocity: CGFloat, reduceMotion: Bool) {
        let flick = abs(velocity) >= Theme.Size.pageSwipeVelocity
        let swiped = abs(dx) >= Theme.Size.pageSwipeDistance
        var target = page
        if flick || swiped { target += (flick ? velocity : dx) < 0 ? 1 : -1 }
        go(to: min(max(target, 0), Self.pageCount - 1), velocity: velocity, reduceMotion: reduceMotion)
    }

    /// Glides to `target` from wherever the pages are, leaving at the finger's speed when it is
    /// headed there (none from a tapped dot).
    func go(to target: Int, velocity: CGFloat = 0, reduceMotion: Bool) {
        let distance = (CGFloat(target) - progress) * width
        // In page-distances per second; positive only when the finger was going that way.
        let speed = abs(distance) > 1 ? max(-velocity / distance, 0) : 0
        if target != page { landings += 1 }
        withAnimation(reduceMotion ? nil : Theme.Motion.pageGlide(velocity: speed)) {
            page = target
            drag = 0
        }
    }
}
