import CentavoCore
import Foundation

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

/// An amount as the ledger prints it: bare digits in the primary currency ("89.00"),
/// the code in front of any other ("USD 24.99"), and a "+" when money came back.
func ledgerAmount(for expense: Expense, primary: String) -> String {
    let iso = CurrencyResolver.isoCode(for: expense.currencyMarker, primary: primary)
    let number = expense.amount.magnitude.formatted(.number.precision(.fractionLength(2)))
    let sign = expense.amount < 0 ? "+" : ""
    if iso == primary { return sign + number }
    // A marker is a few characters. Anything longer is junk that slipped in (a merchant's
    // name, seen for real) and must not push the row off the screen.
    let code = String((iso ?? expense.currencyMarker ?? "").prefix(4))
    return sign + (code.isEmpty ? number : "\(code) \(number)")
}

/// "12/10": day and month, in the order the region writes them.
func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
}
