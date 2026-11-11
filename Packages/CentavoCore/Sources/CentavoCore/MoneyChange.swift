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
    /// both cuts and convert in both. An account in `closed` (archived before the later cut, so
    /// it isn't in it) counts there as zero: closing it and moving its money elsewhere is not a
    /// gain, and paying off a debt and archiving it is not a loss (independent review).
    public static func since<ID: Hashable>(previous: Cut<ID>, latest: Cut<ID>, counting: Set<ID>,
                                           closed: Set<ID> = []) -> Decimal {
        var before: [MoneyLine] = [], after: [MoneyLine] = []
        for id in counting {
            guard let old = previous.lines[id], previous.converts(old) else { continue }
            let new = latest.lines[id] ?? (closed.contains(id) ? MoneyLine(kind: old.kind, currency: latest.main, balance: 0) : nil)
            guard let new, latest.converts(new) else { continue }
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

    /// Rates typed between cuts, each with the month it was typed in (independent review): one
    /// only goes into a cut of that month or later. «USD=20@2026-11;EUR=21@2026-12».
    public static func encodePending(_ pending: [String: (rate: Decimal, month: String)]) -> String {
        pending.keys.sorted().map { "\($0)=\(BackupNumber.text(pending[$0]!.rate))@\(pending[$0]!.month)" }.joined(separator: ";")
    }

    public static func decodePending(_ text: String?) -> [String: (rate: Decimal, month: String)] {
        var pending: [String: (rate: Decimal, month: String)] = [:]
        for pair in (text ?? "").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let value = parts[1].split(separator: "@", maxSplits: 1).map(String.init)
            guard value.count == 2, let rate = BackupNumber.value(value[0]), rate > 0 else { continue }
            pending[parts[0]] = (rate, value[1])
        }
        return pending
    }

    /// The pending rates a cut of `month` may start from.
    public static func pendingRates(_ pending: [String: (rate: Decimal, month: String)], for month: String) -> [String: Decimal] {
        pending.filter { $0.value.month <= month }.mapValues(\.rate)
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

    // MARK: Thousands while typing (2026-11-11)

    /// A saved balance or movement back in its field as the field writes it: thousands with
    /// commas, cents with two digits, «−» before what is below zero («−1,500», «12,000.50»).
    /// It reads back to the same amount. A figure with more than cents comes back plain, so
    /// nothing is trimmed off it.
    public static func groupedText(_ value: Decimal?) -> String {
        guard let value else { return "" }
        var plain = text(value < 0 ? -value : value)
        guard let fraction = fractionDigits(of: plain), fraction <= 2 else { return signedText(value) }
        if fraction == 1 { plain += "0" }
        return (value < 0 ? "−" : "") + AmountTyping.grouped(plain)
    }

    /// What an amount's field of «Mi dinero» shows after it changed from `old` to `new`: the
    /// thousands put in as in the expense sheet («12500» → «12,500»), with two differences that
    /// protect what is saved. The minus sign in front stays (an overdrawn account, «−300» taken
    /// out of an investment). And only what is plainly a number is rewritten: something pasted
    /// that reads becomes its amount, and what doesn't read («1.234,56», «12 mil») stays as it
    /// was written, to be said, never trimmed into another figure.
    ///
    /// - Parameter decimalSeparator: the key the decimal pad has. Where it is «,», the comma
    ///   just typed is the decimal point; the commas already there are thousands.
    public static func typed(_ new: String, was old: String, decimalSeparator: String = ".") -> String {
        var text = new
        // Digits typed fast reach here together («1,850» → «1,85000»): still typed, not pasted.
        let appended = new.hasPrefix(old) ? new.dropFirst(old.count) : Substring("")
        let typedFast = appended.count > 1 && appended.allSatisfy { $0.isASCII && $0.isNumber }
        if new.count > old.count + 1, !typedFast {
            // Pasted, or put there whole: read with the rule of «Mi dinero», then written.
            // What is already written the field's way stays as it is.
            let body = new.hasPrefix("-") || new.hasPrefix("−") ? String(new.dropFirst()) : new
            if isPlainNumber(body), AmountTyping.grouped(body) == body { return new }
            guard case .value(let value) = signedReading(new) else { return new }
            return groupedText(value)
        }
        if decimalSeparator == ",", new.count == old.count + 1, new.hasPrefix(old), new.hasSuffix(",") {
            text = String(new.dropLast()) + "."
        }
        let negative = text.hasPrefix("-") || text.hasPrefix("−")
        let body = negative ? String(text.dropFirst()) : text
        guard isPlainNumber(body) else { return text }
        if let fraction = fractionDigits(of: body), fraction > 2 {
            // A third decimal typed at the end is not typed at all; anywhere else it stays, unread.
            return new.hasPrefix(old) && new.count > old.count ? old : text
        }
        return (negative ? String(text.prefix(1)) : "") + AmountTyping.grouped(body)
    }

    /// Digits, commas before the point and at most one point: nothing else.
    private static func isPlainNumber(_ text: String) -> Bool {
        var pointSeen = false
        for character in text {
            if character.isASCII, character.isNumber { continue }
            if character == ",", !pointSeen { continue }
            if character == ".", !pointSeen { pointSeen = true; continue }
            return false
        }
        return true
    }

    /// How many digits follow the point; 0 without one.
    private static func fractionDigits(of text: String) -> Int? {
        guard let point = text.firstIndex(of: ".") else { return 0 }
        return text[text.index(after: point)...].count
    }
}
