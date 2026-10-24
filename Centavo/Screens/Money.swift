import CentavoCore
import Foundation

/// An amount as the ledger prints it: money in the primary currency ("$89.00"),
/// the code in front of any other ("USD 24.99"), and a "+" when money came back.
func ledgerAmount(for expense: Expense, primary: String) -> String {
    let iso = CurrencyResolver.isoCode(for: expense.currencyMarker, primary: primary)
    let number = expense.amount.magnitude.formatted(.number.precision(.fractionLength(2)))
    let sign = expense.amount < 0 ? "+" : ""
    // The month's own money reads like every other figure on screen: «$47.50».
    if iso == primary { return sign + formatMoney(expense.amount.magnitude, isoCode: primary, label: primary) }
    // A marker is a few characters. Anything longer is junk that slipped in (a merchant's
    // name, seen for real) and must not push the row off the screen.
    let code = String((iso ?? expense.currencyMarker ?? "").prefix(4))
    return sign + (code.isEmpty ? number : "\(code) \(number)")
}

/// "12/10": day and month, in the order the region writes them.
func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
}
