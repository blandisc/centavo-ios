import Foundation

/// The bits of an expense the summary needs. Keeps this package free of SwiftData.
public struct ExpenseAmount: Equatable, Sendable {
    public var value: Decimal
    public var currencyMarker: String?
    public var date: Date
    public var category: String?

    public init(value: Decimal, currencyMarker: String? = nil, date: Date,
                category: String? = nil) {
        self.value = value
        self.currencyMarker = currencyMarker
        self.date = date
        self.category = category
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

    public init(primary: MoneyTotal, others: [MoneyTotal], categories: [CategoryTotal]) {
        self.primary = primary
        self.others = others
        self.categories = categories
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

        for amount in amounts
        where calendar.isDate(amount.date, equalTo: reference, toGranularity: .month) {
            let iso = CurrencyResolver.isoCode(for: amount.currencyMarker, primary: primaryCode)
            let marker = amount.currencyMarker?.trimmingCharacters(in: .whitespaces) ?? ""
            let label = iso ?? (marker.isEmpty ? primaryCode : marker)
            totals[label, default: 0] += amount.value
            codes[label] = iso

            guard label == primaryCode else { continue }
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
            categories: categories
        )
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
    /// How many smaller categories this line gathers («Otras»); 0 for a real category.
    public var restCount = 0

    public var isRest: Bool { restCount > 0 }

    public init(category: String?, share: Double, amount: Decimal = 0, restCount: Int = 0) {
        self.category = category
        self.share = share
        self.amount = amount
        self.restCount = restCount
    }

    /// Where the month went, biggest first, adding up to everything spent (refunds that left
    /// a category in the negative don't count, or the shares would stop adding up). Past
    /// `limit` lines, the smallest are gathered in one «Otras» line, so the list grows with
    /// the categories but never past `limit`. Empty when nothing is filed under a name:
    /// "100 % sin categoría" says nothing.
    public static func top(_ categories: [CategoryTotal], limit: Int = 6) -> [CategoryShare] {
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
            lines.append(CategoryShare(category: nil, share: share(amount), amount: amount, restCount: rest.count))
        }
        return lines
    }
}
