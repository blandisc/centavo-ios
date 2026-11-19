import CentavoCore
import Foundation

/// An amount as the ledger prints it: money in the primary currency ("$89.00"),
/// the code in front of any other ("USD 24.99"), and a "+" when money came back.
func ledgerAmount(for expense: Expense, primary: String) -> String {
    let iso = CurrencyResolver.isoCode(for: expense.currencyMarker, primary: primary)
    let number = plainAmount(expense.amount.magnitude)
    let sign = expense.amount < 0 ? "+" : ""
    // The month's own money reads like every other figure on screen: «$47.50».
    if iso == primary { return sign + formatMoney(expense.amount.magnitude, isoCode: primary, label: primary) }
    // A marker is a few characters. Anything longer is junk that slipped in (a merchant's
    // name, seen for real) and must not push the row off the screen.
    let code = String((iso ?? expense.currencyMarker ?? "").prefix(4))
    return sign + (code.isEmpty ? number : "\(code) \(number)")
}

/// The same amount for VoiceOver: in Spanish exactly `ledgerAmount`; in English with the
/// currency's name («89.00 Mexican pesos»), since «$» alone is read «dollars» (2026-11-19).
func spokenLedgerAmount(for expense: Expense, primary: String) -> String {
    guard !saysMoneyAsWritten,
          let iso = CurrencyResolver.isoCode(for: expense.currencyMarker, primary: primary) else {
        return ledgerAmount(for: expense, primary: primary)
    }
    let sign = expense.amount < 0 ? "+" : ""
    return sign + spokenMoney(expense.amount.magnitude, isoCode: iso, label: iso)
}

/// "1,234.50": an amount in another currency, beside its code («EUR 1,234.50»), written the
/// Mexican way in any region, like the main currency's (2026-10-18). It followed the phone's
/// region, and «$47.50» and «EUR 12,50» shared one screen (2026-11-18).
func plainAmount(_ amount: Decimal) -> String {
    amount.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "es_MX")))
}

/// "12/10": day and month, in the order the region writes them.
func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
}
