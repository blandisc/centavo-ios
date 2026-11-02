import Foundation

/// «+$1,000 desde sep» (second audit, 2026-11-02): what changed between two cuts, counted over
/// the same accounts on both sides. An account archived since, one added after the earlier cut
/// (its first balance is where it starts, not money saved) or one that can't be converted in
/// either cut is left out of both, so none of them reads as a gain or a loss.
public enum MoneyChange {
    /// A cut's lines by account, with what it adds up in.
    public struct Cut<ID: Hashable> {
        public var lines: [ID: MoneyLine]
        public var main: String
        public var rates: [String: Decimal]

        public init(lines: [ID: MoneyLine], main: String, rates: [String: Decimal]) {
            self.lines = lines
            self.main = main
            self.rates = rates
        }

        func converts(_ line: MoneyLine) -> Bool {
            line.currency == main || (rates[line.currency] ?? 0) > 0
        }
    }

    /// The later cut's total minus the earlier one's, over the accounts in `counting` that are in
    /// both cuts and convert in both.
    public static func since<ID: Hashable>(previous: Cut<ID>, latest: Cut<ID>, counting: Set<ID>) -> Decimal {
        var before: [MoneyLine] = [], after: [MoneyLine] = []
        for id in counting {
            guard let old = previous.lines[id], let new = latest.lines[id],
                  previous.converts(old), latest.converts(new) else { continue }
            before.append(old)
            after.append(new)
        }
        return NetWorth(lines: after, main: latest.main, rates: latest.rates).total
            - NetWorth(lines: before, main: previous.main, rates: previous.rates).total
    }
}

extension MoneyMath {
    /// The months «Hacer corte» offers (second audit, 2026-11-02): the one that just ended
    /// first in the first `lateDays` days of a month (the statements arrive then), this one after
    /// that; never a month before the latest finished cut, which would go behind it.
    public static func cutMonths(now: Date, latest: String?, lateDays: Int = 7,
                                 calendar: Calendar = .current) -> [String] {
        let this = monthKey(of: now, calendar: calendar)
        let last = calendar.date(byAdding: .month, value: -1, to: now).map { monthKey(of: $0, calendar: calendar) } ?? this
        let ordered = calendar.component(.day, from: now) <= lateDays ? [last, this] : [this, last]
        guard let latest else { return ordered }
        return ordered.filter { $0 >= latest }
    }

    /// Whether an account created on `createdAt` existed in `month` («2026-10»): one created
    /// later isn't asked for in that month's cut.
    public static func belongs(createdAt: Date, to month: String, calendar: Calendar = .current) -> Bool {
        monthKey(of: createdAt, calendar: calendar) <= month
    }
}

/// What's typed in «Mi dinero»'s amount fields (2026-11-02): the point is the decimal, commas
/// only group thousands, never more than cents, and a word after it («25 mil») doesn't read.
public enum MoneyTyping {
    public enum Reading: Equatable, Sendable {
        case empty
        case value(Decimal)
        /// Something typed that isn't an amount: said, never taken as the last one that read.
        case unreadable
    }

    public static func amount(_ text: String) -> Decimal? {
        guard let parsed = AmountParser.parsePointDecimal(text), !parsed.hasMoreThanCents else { return nil }
        if let marker = parsed.currencyMarker {
            guard let code = CurrencyResolver.isoCode(for: marker, primary: "MXN"),
                  Locale.commonISOCurrencyCodes.contains(code) else { return nil }
        }
        return parsed.value
    }

    public static func reading(_ text: String) -> Reading {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        return amount(text).map(Reading.value) ?? .unreadable
    }

    /// An investment's movement: «−300» if money came out.
    public static func signedReading(_ text: String) -> Reading {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let negative = trimmed.hasPrefix("-") || trimmed.hasPrefix("−")
        switch reading(String(trimmed.drop(while: { $0 == "-" || $0 == "−" }))) {
        case .empty: return negative ? .unreadable : .empty
        case .unreadable: return .unreadable
        case .value(let value): return .value(negative ? -value : value)
        }
    }

    /// A saved balance back in its field, as it would be typed.
    public static func text(_ value: Decimal) -> String { BackupNumber.text(value) }

    public static func signedText(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return value < 0 ? "−" + text(-value) : text(value)
    }
}
