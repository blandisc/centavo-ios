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
    // The Mexican way in any region, like every currency (2026-10-18; it followed the region).
    let digits = amount.magnitude.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "es_MX")))
    return (amount < 0 ? "-" : "") + label + digits
}

/// Whether money said out loud (Siri, VoiceOver) is said as the screen writes it: in Spanish
/// «$» is read «pesos». In English it is read «dollars», so 45 pesos sounded like 45 dollars
/// (2026-11-18, the app in English). Follows the language the app is shown in.
var saysMoneyAsWritten: Bool {
    !(Bundle.main.preferredLocalizations.first?.hasPrefix("en") ?? false)
}

/// Money for a sentence Siri or VoiceOver says: in Spanish exactly `formatMoney`; in English
/// with the currency's name, «89.00 Mexican pesos», «20.00 US dollars» (2026-11-18). A marker
/// with no ISO code stays as written.
func spokenMoney(_ amount: Decimal, isoCode: String?, label: String, main: String? = nil) -> String {
    guard let isoCode, !saysMoneyAsWritten else {
        return formatMoney(amount, isoCode: isoCode, label: label, main: main)
    }
    let english = Locale.current.language.languageCode?.identifier == "en"
    let locale = english ? Locale.current : Locale(identifier: "en_US")
    let style = Decimal.FormatStyle.Currency(code: isoCode, locale: locale).presentation(.fullName)
    return amount.formatted(style)
}
