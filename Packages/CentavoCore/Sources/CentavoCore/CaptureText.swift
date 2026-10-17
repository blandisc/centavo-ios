import Foundation

/// Finds the amount in whatever text the Wallet automation hands over.
///
/// Normally that is just the amount (`"$89.00"`). But in Atajos it is easy to connect the
/// whole payment instead of its «Importe». On iOS 27 that arrives as the merchant's name
/// alone (seen for real: "Oxxo Roble Mty 50ht1", twice), with no amount at all; other
/// setups may carry the amount among other text. Reading all of that as one number would save
/// a nonsense amount, so in a longer text only a figure with a currency next to it counts.
public enum CaptureText {
    /// The amount in `text`, or `nil` when there is none to trust.
    public static func amount(in text: String) -> ParsedAmount? {
        let visible = text.filter { !invisible.contains($0) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Just an amount, as Wallet sends it: read it whole, exactly as before.
        if matches(singleAmount, visible) {
            return AmountParser.parse(text)
        }
        // Anything longer: the first figure that carries a currency.
        for candidate in candidates(in: visible) {
            if let parsed = AmountParser.parse(candidate), let marker = parsed.currencyMarker,
               isCurrency(marker) {
                return parsed
            }
        }
        return nil
    }

    /// Direction marks some languages wrap amounts in. `AmountParser` already skips them.
    private static let invisible = Set("\u{200B}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")

    private static let digits = #"\d(?:[\d.,'’  ]|\s(?=\d))*"#
    /// One number with at most one marker, on one side: a short run with a symbol in it
    /// (`$`, `MX$`, `Bs.`, `€`) or capital letters (`USD`). "Nu 1234" is not an amount.
    private static let marker = #"(?:[^\d\s()]{0,3}[^\d\s()\p{L}][^\d\s()]{0,3}|\p{Lu}{2,4})"#
    private static let singleAmount = try! NSRegularExpression(
        pattern: #"^\(?[-−]?\s?(?:\#(marker)\s?)?[-−]?\#(digits)\)?$|^\(?[-−]?\#(digits)(?:\s?\#(marker))?\)?$"#
    )
    private static let symbols = "$€£¥₱₩₹"
    private static let figures: [NSRegularExpression] = [
        // `$89.00`, `MX$1,234.50`, `-$230`, `USD 24.99`
        #"[-−]?(?:[A-Z]{1,2}\$|\b[A-Z]{3}\b|[\#(symbols)])\s?[-−]?\#(digits)"#,
        // `12,50 €`, `24.99 USD`
        #"[-−]?\#(digits)\s?(?:[\#(symbols)]|\b[A-Z]{3}\b)"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// A symbol (`$`, `MX$`, `€`) or a real ISO code (`USD`). "BBVA" or "Nu" are not.
    static func isCurrency(_ marker: String) -> Bool {
        if marker.contains(where: { symbols.contains($0) }) { return marker.count <= 3 }
        return marker.count == 3 && Locale.commonISOCurrencyCodes.contains(marker)
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Currency-looking figures in reading order, trailing punctuation trimmed.
    private static func candidates(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return figures
            .flatMap { $0.matches(in: text, range: range) }
            .sorted { $0.range.location < $1.range.location }
            .compactMap { match in
                guard let found = Range(match.range, in: text) else { return nil }
                var candidate = String(text[found])
                while let last = candidate.last, ".,'’ \u{00A0}\u{202F}".contains(last) {
                    candidate.removeLast()
                }
                return candidate
            }
    }
}
