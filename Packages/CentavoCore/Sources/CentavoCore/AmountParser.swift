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
}

public enum AmountParser {
    /// More integer digits than this is not an amount, it is a typo (or an attack): no
    /// card statement has a trillion pesos on it, and `Decimal` silently rounds past 38.
    public static let maxIntegerDigits = 12

    /// Characters that sit around an amount without being part of it or of its currency:
    /// signs, brackets, spaces of every width, the apostrophes Swiss formats group with,
    /// and the invisible direction marks Wallet adds in right-to-left languages.
    private static let ignorable = Set(
        ",.-−() \u{00A0}\u{202F}\u{2009}\u{2007}\u{2008}'’´ʼ`\u{200B}\u{200E}\u{200F}"
        + "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"
    )

    /// Parses a locale-agnostic amount string. Returns `nil` when no digits are present,
    /// when it has more than `maxIntegerDigits`, or when the last separator is followed by
    /// something that is neither cents nor a group of three.
    ///
    /// Separator rule: the LAST `.` or `,` is the decimal separator only when it is
    /// followed by 1–2 digits; every other separator is digit grouping. A group of three
    /// is only a group when it can be one: `1,000` is a thousand, but `0.005` (nothing to
    /// group) and `$1,234.567` (two kinds of separator, so the last one is decimal) are
    /// rejected rather than read a thousand times bigger.
    /// A leading `-` or wrapping parentheses mark a negative amount (refund).
    public static func parse(_ raw: String) -> ParsedAmount? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: \.isNumber) else { return nil }

        // A minus can sit on either side of the symbol (`-$20`, `$-20`), and some
        // locales wrap refunds in parentheses. Nothing else in an amount uses one.
        let isNegative = text.contains("-") || text.contains("−")
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

        var integerPart = numeric
        var fractionPart = ""
        if let lastSep = numeric.lastIndex(where: { $0 == "." || $0 == "," }) {
            let head = numeric[..<lastSep]
            let tail = numeric[numeric.index(after: lastSep)...]
            switch tail.count {
            case 1...2:
                integerPart = String(head)
                fractionPart = String(tail)
            case 3:
                // A group of three: `1,000` is a thousand. Not after another kind of
                // separator (`1,234.567`: that one is decimal) nor with nothing to group
                // (`0.005`, `.500`): those would silently become thousands.
                let otherSeparator: Character = numeric[lastSep] == "." ? "," : "."
                guard !head.contains(otherSeparator), head.contains(where: { $0.isNumber && $0 != "0" }) else {
                    return nil
                }
            default:
                return nil                  // `0.0001`, `1.23456`: not money
            }
        }
        // Grouping is a first run of digits and then runs of two or three (`1,234,567`,
        // `1,23,456`). A run of one is not grouping: `1.2.3` is not a number.
        let groups = integerPart.split(separator: ".", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ",", omittingEmptySubsequences: false) }
        guard groups.dropFirst().allSatisfy({ (2...3).contains($0.count) }) else { return nil }
        let digits = integerPart.filter(\.isNumber)
        guard digits.count <= maxIntegerDigits else { return nil }
        let normalized = (digits.isEmpty ? "0" : digits) + (fractionPart.isEmpty ? "" : "." + fractionPart)
        guard var value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        if isNegative { value.negate() }
        return ParsedAmount(value: value, currencyMarker: marker.isEmpty ? nil : marker)
    }
}
