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
    /// Parses a locale-agnostic amount string. Returns `nil` when no digits are present.
    ///
    /// Separator rule: the LAST `.` or `,` is the decimal separator only when it is
    /// followed by 1–2 digits; every other separator is digit grouping.
    /// A leading `-` or wrapping parentheses mark a negative amount (refund).
    public static func parse(_ raw: String) -> ParsedAmount? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: \.isNumber) else { return nil }

        // A minus can sit on either side of the symbol (`-$20`, `$-20`), and some
        // locales wrap refunds in parentheses. Nothing else in an amount uses one.
        let isNegative = text.contains("-") || text.contains("−")
            || (text.hasPrefix("(") && text.hasSuffix(")"))

        // Everything that isn't a digit, separator, sign or space is the currency marker.
        let marker = text
            .filter { !$0.isNumber && !",.-−() \u{00A0}\u{202F}".contains($0) }
        let numeric = text.filter { $0.isNumber || $0 == "." || $0 == "," }

        var integerPart = numeric
        var fractionPart = ""
        if let lastSep = numeric.lastIndex(where: { $0 == "." || $0 == "," }) {
            let tail = numeric[numeric.index(after: lastSep)...]
            if (1...2).contains(tail.count) {
                integerPart = String(numeric[..<lastSep])
                fractionPart = String(tail)
            }
        }
        let digits = integerPart.filter(\.isNumber)
        let normalized = (digits.isEmpty ? "0" : digits) + (fractionPart.isEmpty ? "" : "." + fractionPart)
        guard var value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        if isNegative { value.negate() }
        return ParsedAmount(value: value, currencyMarker: marker.isEmpty ? nil : marker)
    }
}
