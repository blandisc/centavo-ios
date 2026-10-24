import Foundation

// Shared with the widgets: no SwiftData here.

/// A currency the way it is written in Mexico, whatever region the phone is set to: "$402"
/// for pesos (a US region printed "MXN 402"), and "$" for dollars only when they are the
/// main currency, where there is no doubt.
func currencyStyle(_ isoCode: String) -> Decimal.FormatStyle.Currency {
    .currency(code: isoCode).locale(Locale(identifier: isoCode == "USD" ? "en_US" : "es_MX"))
}

/// Formats money for the screen: the real currency style when the ISO code is known,
/// otherwise the marker Wallet sent in front of a plain number.
func formatMoney(_ amount: Decimal, isoCode: String?, label: String) -> String {
    if let isoCode {
        return amount.formatted(currencyStyle(isoCode))
    }
    let digits = amount.magnitude.formatted(.number.precision(.fractionLength(2)))
    return (amount < 0 ? "-" : "") + label + digits
}
