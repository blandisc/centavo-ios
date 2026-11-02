import Foundation

// Shared with the widgets: no SwiftData here.

/// A currency the way it is written in Mexico, whatever region the phone is set to: "$402"
/// for pesos (a US region printed "MXN 402"), and "$" for dollars only when they are the
/// main currency, where there is no doubt.
///
/// `main`: the currency everything adds up in. Another currency next to it says its code
/// («USD 20.00», «MX$500.00»), never a bare «$» that reads as the main one (2026-11-02).
func currencyStyle(_ isoCode: String, main: String? = nil) -> Decimal.FormatStyle.Currency {
    let isMain = main.map { $0 == isoCode } ?? true
    let locale = isMain ? (isoCode == "USD" ? "en_US" : "es_MX") : (isoCode == "MXN" ? "en_US" : "es_MX")
    return .currency(code: isoCode).locale(Locale(identifier: locale))
}

/// Formats money for the screen: the real currency style when the ISO code is known,
/// otherwise the marker Wallet sent in front of a plain number.
func formatMoney(_ amount: Decimal, isoCode: String?, label: String, main: String? = nil) -> String {
    if let isoCode {
        return amount.formatted(currencyStyle(isoCode, main: main))
    }
    let digits = amount.magnitude.formatted(.number.precision(.fractionLength(2)))
    return (amount < 0 ? "-" : "") + label + digits
}
