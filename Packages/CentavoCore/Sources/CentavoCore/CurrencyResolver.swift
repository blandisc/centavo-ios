import Foundation

/// Turns the currency marker Wallet writes into an amount (`"$"`, `"MX$"`, `"€"`, `"USD"`)
/// into an ISO 4217 code, so two spellings of the same money add up together.
public enum CurrencyResolver {
    /// Markers that name exactly one currency. Keys are already normalized.
    private static let known: [String: String] = [
        "MX$": "MXN", "MEX$": "MXN", "MXN": "MXN",
        "US$": "USD", "USD": "USD", "USD$": "USD",
        "€": "EUR", "EUR": "EUR",
        "£": "GBP", "GBP": "GBP",
        "¥": "JPY", "JPY": "JPY",
        "CN¥": "CNY", "RMB": "CNY", "CNY": "CNY",
        "CA$": "CAD", "C$": "CAD", "CAD": "CAD",
        "R$": "BRL", "BRL": "BRL",
        "₩": "KRW", "KRW": "KRW",
        "₹": "INR", "INR": "INR",
        "CHF": "CHF",
        "A$": "AUD", "AUD": "AUD",
    ]

    /// The ISO 4217 code a marker stands for, or `nil` when it names no currency we know.
    ///
    /// A bare `$` is ambiguous — dozens of currencies use it — so it resolves to
    /// `primary`, the currency the person's own money is in. So does a missing marker.
    public static func isoCode(for marker: String?, primary: String) -> String? {
        let normalized = normalize(marker)
        if normalized.isEmpty || normalized == "$" { return normalize(primary) }
        if let code = known[normalized] { return code }
        // Anything already shaped like an ISO code (`COP`, `CLP`, `PEN`, …) passes through.
        if normalized.count == 3, normalized.allSatisfy({ $0.isLetter && $0.isASCII }) {
            return normalized
        }
        return nil
    }

    /// Uppercases and drops the sign, space and padding characters a marker can pick up.
    private static func normalize(_ marker: String?) -> String {
        guard let marker else { return "" }
        return marker
            .uppercased()
            .filter { !$0.isWhitespace && !"+-−*".contains($0) }
    }
}
