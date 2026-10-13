import Foundation

/// The bits of an expense the summary needs. Keeps this package free of SwiftData.
public struct ExpenseAmount: Equatable, Sendable {
    public var value: Decimal
    public var currencyMarker: String?
    public var date: Date

    public init(value: Decimal, currencyMarker: String? = nil, date: Date) {
        self.value = value
        self.currencyMarker = currencyMarker
        self.date = date
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

/// One month, split so the headline number stays a single currency.
public struct MonthSummary: Equatable, Sendable {
    /// The total in the person's own currency. Present even with no expenses, so the
    /// main screen always has a number to show.
    public let primary: MoneyTotal
    /// Every other currency that showed up, by label.
    public let others: [MoneyTotal]

    public init(primary: MoneyTotal, others: [MoneyTotal]) {
        self.primary = primary
        self.others = others
    }
}

public enum MonthSummarizer {
    /// Adds up the expenses that fall in the same calendar month as `reference`.
    ///
    /// Mixing currencies in one total would be a lie, so only `primary` goes in the
    /// headline; the rest come back in `others`, sorted by label for a stable screen.
    public static func summarize(
        _ amounts: [ExpenseAmount],
        inMonthOf reference: Date,
        primary: String,
        calendar: Calendar = .current
    ) -> MonthSummary {
        let primaryCode = CurrencyResolver.isoCode(for: primary, primary: primary) ?? primary
        var totals: [String: Decimal] = [:]
        var codes: [String: String?] = [:]

        for amount in amounts
        where calendar.isDate(amount.date, equalTo: reference, toGranularity: .month) {
            let iso = CurrencyResolver.isoCode(for: amount.currencyMarker, primary: primaryCode)
            let marker = amount.currencyMarker?.trimmingCharacters(in: .whitespaces) ?? ""
            let label = iso ?? (marker.isEmpty ? primaryCode : marker)
            totals[label, default: 0] += amount.value
            codes[label] = iso
        }

        let others = totals.keys
            .filter { $0 != primaryCode }
            .sorted()
            .map { MoneyTotal(isoCode: codes[$0] ?? nil, label: $0, amount: totals[$0] ?? 0) }

        return MonthSummary(
            primary: MoneyTotal(isoCode: primaryCode, label: primaryCode,
                                amount: totals[primaryCode] ?? 0),
            others: others
        )
    }
}
