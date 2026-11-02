import Foundation

/// A monetary amount decoded from the text Apple Wallet hands to a Shortcuts
/// "Transaction" automation (e.g. `"$1,234.56"`, `"MX$89.00"`, `"12,50 €"`).
public struct ParsedAmount: Equatable, Sendable {
    public var value: Decimal
    /// The currency marker found in the text (`"$"`, `"MX$"`, `"€"`, `"USD"`), if any.
    public var currencyMarker: String?

    public init(value: Decimal, currencyMarker: String? = nil) {
        self.value = value
        self.currencyMarker = currencyMarker
    }

    /// More than two decimals (`8333.333`): no account or card holds a fraction of a cent, so
    /// a figure like that is a calculation pasted whole, to be checked before it is kept.
    public var hasMoreThanCents: Bool { value != MoneyMath.cents(value) }
}

public enum AmountParser {
    /// More integer digits than this is not an amount, it is a typo (or an attack): no
    /// card statement has a trillion pesos on it, and `Decimal` silently rounds past 38.
    public static let maxIntegerDigits = 12

    /// Characters that sit around an amount without being part of it or of its currency:
    /// signs, brackets, spaces of every width, the apostrophes Swiss formats group with,
    /// and the invisible direction marks Wallet adds in right-to-left languages.
    private static let ignorable = Set(
        ",.-−–() \u{00A0}\u{202F}\u{2009}\u{2007}\u{2008}'’´ʼ`\u{200B}\u{200E}\u{200F}"
        + "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"
    )

    /// Parses a locale-agnostic amount string. Returns `nil` when no digits are present,
    /// when it has more than `maxIntegerDigits`, or when the last separator is followed by
    /// something that is neither cents nor a group of three.
    ///
    /// Separator rule: the LAST `.` or `,` is the decimal separator only when it is
    /// followed by 1–2 digits; every other separator is digit grouping. A group of three
    /// is only a group when it can be one: `1,000` is a thousand, but `0.005` (nothing to
    /// group), `15000.125` (a first group of more than three) and `$1,234.567` (two kinds of
    /// separator, so the last one is decimal) are rejected rather than read a thousand times
    /// bigger. A leading `-` or wrapping parentheses mark a negative amount (refund).
    public static func parse(_ raw: String) -> ParsedAmount? {
        read(raw, pointDecimal: false)
    }

    /// For text written to a format that asks for a decimal point («Mi dinero», the import of
    /// «¿Lo tienes en Excel?»): the `.` is always the decimal point, with as many decimals as
    /// it brings (`18.125` is eighteen and a bit, never 18,125), and commas only group thousands
    /// in threes (`1,234.56`, `12,500`). A lone comma before one or two digits is a decimal
    /// comma (`7,5`). Two points, or a comma after the point (`1.234,56`), are rejected: that is
    /// another format, and guessing it could be off a thousand times. Signs and currency
    /// markers read as in `parse`; check `hasMoreThanCents` before keeping it as money.
    public static func parsePointDecimal(_ raw: String) -> ParsedAmount? {
        read(raw, pointDecimal: true)
    }

    /// Decimals a point-decimal figure may bring; past this it is not a figure anyone typed.
    static let maxFractionDigits = 10

    private static func read(_ raw: String, pointDecimal: Bool) -> ParsedAmount? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: \.isNumber) else { return nil }

        // A minus can sit on either side of the symbol (`-$20`, `$-20`), and some
        // locales wrap refunds in parentheses. Nothing else in an amount uses one.
        let isNegative = text.contains(where: minusSigns.contains)
            || (text.hasPrefix("(") && text.hasSuffix(")"))
        // A plus is just a sign, never a currency; with a minus too it says nothing (`+-50`).
        let isPositive = text.contains("+")
        guard !(isNegative && isPositive) else { return nil }

        // The currency sits on one side of the number. Letters between digits (`1e5`,
        // `50ht1`) make it something else: an exponent, a code, a typo.
        let isMarker: (Character) -> Bool = {
            !$0.isNumber && !$0.isWhitespace && $0 != "+" && !ignorable.contains($0)
        }
        if let first = text.firstIndex(where: \.isNumber), let last = text.lastIndex(where: \.isNumber),
           text[first...last].contains(where: isMarker) {
            return nil
        }

        // Everything that isn't a digit, separator, sign or space is the currency marker.
        let marker = text.filter(isMarker)
        let numeric = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        let threeDecimals = threeDecimalCurrencies.contains(marker.uppercased())
        guard let (integerPart, fractionPart) = pointDecimal
                ? splitPointDecimal(numeric) : split(numeric, threeDecimals: threeDecimals) else {
            return nil
        }
        // Grouping is a first run of one to three digits and then runs of two or three
        // (`1,234,567`, `1,23,456`); with a point for decimals, runs of exactly three. A run
        // of one is not grouping (`1.2.3` is not a number), and neither is a first run of four
        // or more (`15000.125`): no one writes fifteen thousand like that.
        let groups = integerPart.split(separator: ".", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ",", omittingEmptySubsequences: false) }
        if groups.count > 1 {
            let rest = pointDecimal ? 3...3 : 2...3
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ rest.contains($0.count) }) else {
                return nil
            }
        }
        let digits = integerPart.filter(\.isNumber)
        guard digits.count <= maxIntegerDigits else { return nil }
        let normalized = (digits.isEmpty ? "0" : digits) + (fractionPart.isEmpty ? "" : "." + fractionPart)
        guard var value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        if isNegative { value.negate() }
        return ParsedAmount(value: value, currencyMarker: marker.isEmpty ? nil : marker)
    }

    /// The minus signs an amount may come with: the hyphen, the math minus Wallet uses in some
    /// languages, and the en dash some notices put before a refund (`–$50.00`).
    static let minusSigns: Set<Character> = ["-", "−", "–"]

    /// Currencies whose cents come in thousandths (Kuwaiti, Bahraini, Omani, Jordanian,
    /// Tunisian, Libyan dinars and the Iraqi dinar): «JOD 1.250» is one and a quarter, never
    /// 1,250, and «BHD 0.750» is three quarters (2026-11-02, second audit).
    public static let threeDecimalCurrencies: Set<String> = ["KWD", "BHD", "OMR", "JOD", "TND", "LYD", "IQD"]

    /// `parse`'s rule: the last separator is decimal before one or two digits, a group before
    /// three. With a currency that has three decimals, three digits after it are decimals too.
    private static func split(_ numeric: String, threeDecimals: Bool = false) -> (integer: String, fraction: String)? {
        guard let lastSep = numeric.lastIndex(where: { $0 == "." || $0 == "," }) else { return (numeric, "") }
        let head = numeric[..<lastSep]
        let tail = numeric[numeric.index(after: lastSep)...]
        switch tail.count {
        case 1...2:
            return (String(head), String(tail))
        case 3 where threeDecimals:
            return (String(head), String(tail))
        case 3:
            // A group of three: `1,000` is a thousand. Not after another kind of
            // separator (`1,234.567`: that one is decimal) nor with nothing to group
            // (`0.005`, `.500`): those would silently become thousands.
            let otherSeparator: Character = numeric[lastSep] == "." ? "," : "."
            guard !head.contains(otherSeparator), head.contains(where: { $0.isNumber && $0 != "0" }) else {
                return nil
            }
            return (numeric, "")
        default:
            return nil                  // `0.0001`, `1.23456`: not money
        }
    }

    /// `parsePointDecimal`'s rule: one point at most, and it is the decimal point.
    private static func splitPointDecimal(_ numeric: String) -> (integer: String, fraction: String)? {
        let points = numeric.filter { $0 == "." }.count
        guard points <= 1 else { return nil }
        if let point = numeric.firstIndex(of: ".") {
            let fraction = numeric[numeric.index(after: point)...]
            guard !fraction.contains(","), fraction.count <= maxFractionDigits else { return nil }
            return (String(numeric[..<point]), String(fraction))
        }
        // No point: a lone comma before one or two digits is a decimal comma (`7,5`).
        if numeric.filter({ $0 == "," }).count == 1, let comma = numeric.firstIndex(of: ","),
           (1...2).contains(numeric.distance(from: comma, to: numeric.endIndex) - 1) {
            return (String(numeric[..<comma]), String(numeric[numeric.index(after: comma)...]))
        }
        // Only grouping: `0,500` has nothing to group.
        if numeric.contains(","), !(numeric.first.map { $0 != "0" } ?? false) { return nil }
        return (numeric, "")
    }
}
