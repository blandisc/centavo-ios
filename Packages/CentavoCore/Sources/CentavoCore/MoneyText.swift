import Foundation

/// Helpers for showing an already-formatted amount.
public enum MoneyText {
    /// A formatted amount cut around its cents, so the cents can be drawn quieter.
    public struct Parts: Equatable, Sendable {
        public let head: String
        public let cents: String
        public let tail: String
    }

    /// Splits `"$1,093.50"` into `"$1,093"`, `".50"` and `""`. Whatever follows the cents
    /// (a trailing `" €"`) lands in `tail`. An amount without a two-digit decimal part
    /// comes back whole in `head`.
    public static func splitCents(_ formatted: String, decimalSeparator: String) -> Parts {
        let whole = Parts(head: formatted, cents: "", tail: "")
        guard !decimalSeparator.isEmpty,
              let range = formatted.range(of: decimalSeparator, options: .backwards)
        else { return whole }
        let after = formatted[range.upperBound...]
        let digits = after.prefix(while: \.isNumber)
        guard digits.count == 2 else { return whole }
        return Parts(
            head: String(formatted[..<range.lowerBound]),
            cents: decimalSeparator + digits,
            tail: String(after.dropFirst(digits.count))
        )
    }
}
