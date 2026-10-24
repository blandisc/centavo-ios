import Foundation

/// The bits of an expense the summary needs. Keeps this package free of SwiftData.
public struct ExpenseAmount: Equatable, Sendable {
    public var value: Decimal
    public var currencyMarker: String?
    public var date: Date
    public var category: String?
    /// The part of the expense left out of the budget («No cuenta»), already taken out of
    /// `value`. Zero for an expense that counts in full, which is nearly all of them.
    public var excluded: Decimal

    public init(value: Decimal, currencyMarker: String? = nil, date: Date,
                category: String? = nil, excluded: Decimal = 0) {
        self.value = value
        self.currencyMarker = currencyMarker
        self.date = date
        self.category = category
        self.excluded = excluded
    }
}

/// What one currency added up to. Refunds are negative, so a month can total below zero.
public struct MoneyTotal: Equatable, Sendable {
    /// ISO 4217 code, when the marker named a currency we recognize.
    public let isoCode: String?
    /// Grouping key and fallback label: the ISO code, or the marker verbatim when unknown.
    public let label: String
    public let amount: Decimal

    public init(isoCode: String?, label: String, amount: Decimal) {
        self.isoCode = isoCode
        self.label = label
        self.amount = amount
    }
}

/// What one category added up to in the primary currency.
public struct CategoryTotal: Equatable, Sendable {
    /// `nil` for expenses you haven't filed anywhere yet.
    public let category: String?
    public let amount: Decimal

    public init(category: String?, amount: Decimal) {
        self.category = category
        self.amount = amount
    }
}

/// One month, split so the headline number stays a single currency.
public struct MonthSummary: Equatable, Sendable {
    /// The total in the person's own currency. Present even with no expenses, so the
    /// main screen always has a number to show.
    public let primary: MoneyTotal
    /// Every other currency that showed up, by label.
    public let others: [MoneyTotal]
    /// The primary-currency total broken down by category, biggest first.
    public let categories: [CategoryTotal]
    /// What was left out of the budget this month, in the primary currency: «Fuera del
    /// presupuesto». Not part of `primary`.
    public let outside: Decimal

    public init(primary: MoneyTotal, others: [MoneyTotal], categories: [CategoryTotal],
                outside: Decimal = 0) {
        self.primary = primary
        self.others = others
        self.categories = categories
        self.outside = outside
    }
}

public enum MonthSummarizer {
    /// Adds up the expenses that fall in the same calendar month as `reference`.
    ///
    /// Mixing currencies in one total would be a lie, so only `primary` goes in the
    /// headline; the rest come back in `others`, sorted by label for a stable screen.
    /// `categories` breaks down the headline number only, for the same reason.
    public static func summarize(
        _ amounts: [ExpenseAmount],
        inMonthOf reference: Date,
        primary: String,
        calendar: Calendar = .current
    ) -> MonthSummary {
        let primaryCode = CurrencyResolver.isoCode(for: primary, primary: primary) ?? primary
        var totals: [String: Decimal] = [:]
        var codes: [String: String?] = [:]
        var byCategory: [String?: Decimal] = [:]
        // Two spellings of one category are one category, but the screen shows the
        // spelling you used most recently.
        var categoryNames: [String?: String?] = [:]
        var outside: Decimal = 0

        for amount in amounts
        where calendar.isDate(amount.date, equalTo: reference, toGranularity: .month) {
            let iso = CurrencyResolver.isoCode(for: amount.currencyMarker, primary: primaryCode)
            let marker = amount.currencyMarker?.trimmingCharacters(in: .whitespaces) ?? ""
            let label = iso ?? (marker.isEmpty ? primaryCode : marker)
            totals[label, default: 0] += amount.value
            codes[label] = iso

            guard label == primaryCode else { continue }
            outside += amount.excluded
            // None of it counts: it is in no category either (not even a zero line).
            guard amount.value != 0 || amount.excluded == 0 else { continue }
            let name = amount.category?.trimmingCharacters(in: .whitespacesAndNewlines)
            let named = (name?.isEmpty ?? true) ? nil : name
            let key = named?.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                     locale: nil)
            byCategory[key, default: 0] += amount.value
            categoryNames[key] = named
        }

        let others = totals.keys
            .filter { $0 != primaryCode }
            .sorted()
            .map { MoneyTotal(isoCode: codes[$0] ?? nil, label: $0, amount: totals[$0] ?? 0) }

        let categories = byCategory
            .map { CategoryTotal(category: categoryNames[$0.key] ?? nil, amount: $0.value) }
            .sorted(by: biggestFirst)

        return MonthSummary(
            primary: MoneyTotal(isoCode: primaryCode, label: primaryCode,
                                amount: totals[primaryCode] ?? 0),
            others: others,
            categories: categories,
            outside: outside
        )
    }

    /// What `reference`'s day added up to in `primary`, refunds included: the part of the
    /// month's total that «Hoy puedes gastar» takes from today alone.
    public static func dayTotal(
        _ amounts: [ExpenseAmount],
        onDayOf reference: Date,
        primary: String,
        calendar: Calendar = .current
    ) -> Decimal {
        let today = amounts.filter { calendar.isDate($0.date, inSameDayAs: reference) }
        return summarize(today, inMonthOf: reference, primary: primary, calendar: calendar).primary.amount
    }

    /// Biggest spend first. Ties go to the named category, then alphabetically, so the
    /// list never shuffles between redraws.
    private static func biggestFirst(_ left: CategoryTotal, _ right: CategoryTotal) -> Bool {
        if left.amount != right.amount { return left.amount > right.amount }
        switch (left.category, right.category) {
        case let (leftName?, rightName?): return leftName < rightName
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return false
        }
    }
}

/// One line of "where it goes": a category and its share of the month's spending.
public struct CategoryShare: Equatable, Sendable {
    /// `nil` for what isn't filed anywhere yet.
    public let category: String?
    /// 0...1 of what was spent in the primary currency.
    public let share: Double
    /// What was spent there, in the primary currency.
    public var amount: Decimal = 0
    /// The smaller categories this line gathers («Otras»); empty for a real category.
    public var members: [String?] = []

    public var isRest: Bool { !members.isEmpty }
    public var restCount: Int { members.count }

    public init(category: String?, share: Double, amount: Decimal = 0, members: [String?] = []) {
        self.category = category
        self.share = share
        self.amount = amount
        self.members = members
    }

    /// How many categories get a color of their own: with five, two always looked alike on
    /// the dark paper (blue and violet), so the rest go together, in grey, as «Otras».
    public static let colored = 4

    /// Where the month went, biggest first, adding up to everything spent (refunds that left
    /// a category in the negative don't count, or the shares would stop adding up; `returned`
    /// says how much they took off, so the lines still square with the month). Past
    /// `limit` lines, the smallest are gathered in one «Otras» line. Empty when nothing is
    /// filed under a name: "100 % sin categoría" says nothing.
    public static func top(_ categories: [CategoryTotal], limit: Int = colored + 1) -> [CategoryShare] {
        let spent = categories.filter { $0.amount > 0 }
        guard spent.contains(where: { $0.category != nil }) else { return [] }
        let total = spent.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0, limit > 0 else { return [] }
        func share(_ amount: Decimal) -> Double { NSDecimalNumber(decimal: amount / total).doubleValue }
        let shown = spent.count > limit ? spent.prefix(limit - 1) : spent.prefix(limit)
        var lines = shown.map { CategoryShare(category: $0.category, share: share($0.amount), amount: $0.amount) }
        let rest = spent.dropFirst(shown.count)
        if !rest.isEmpty {
            let amount = rest.reduce(Decimal(0)) { $0 + $1.amount }
            lines.append(CategoryShare(category: nil, share: share(amount), amount: amount,
                                       members: rest.map(\.category)))
        }
        return lines
    }

    /// Whether an expense filed under `category` belongs to this line, compared the way the
    /// month groups them (case and accents aside; blank is no category).
    public func contains(_ category: String?) -> Bool {
        let key = Self.key(category)
        return isRest ? members.contains { Self.key($0) == key } : Self.key(self.category) == key
    }

    /// What came back across the month: the categories (or the unfiled) that refunds left in
    /// the negative, which `top` leaves out of the shares. The lines minus this is the month's
    /// total, the same as «Llevas».
    public static func returned(_ categories: [CategoryTotal]) -> Decimal {
        categories.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount }
    }

    /// The same line in another reading of the month (its amount may have changed since).
    public func isSameLine(as other: CategoryShare) -> Bool {
        isRest == other.isRest && (isRest || Self.key(category) == Self.key(other.category))
    }

    /// Trimmed like the month trims it, so «Café » filters the same expenses it adds up.
    static func key(_ category: String?) -> String? {
        guard let name = category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
