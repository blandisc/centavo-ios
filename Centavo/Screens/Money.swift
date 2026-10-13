import CentavoCore
import Foundation

/// Formats money for the screen: the real currency style when the ISO code is known,
/// otherwise the marker Wallet sent in front of a plain number.
func formatMoney(_ amount: Decimal, isoCode: String?, label: String) -> String {
    if let isoCode {
        return amount.formatted(.currency(code: isoCode))
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
    let code = iso ?? expense.currencyMarker ?? ""
    return sign + (code.isEmpty ? number : "\(code) \(number)")
}

/// "13 oct": day and month, in the order the region writes them.
func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated))
}

/// "octubre": the month's name, lowercase, for the middle of a sentence.
func monthName(_ date: Date) -> String {
    date.formatted(.dateTime.month(.wide))
}

/// "Octubre 2026": a month as a title.
func monthTitle(_ date: Date) -> String {
    let name = monthName(date)
    return name.prefix(1).uppercased() + name.dropFirst() + " " + date.formatted(.dateTime.year())
}
