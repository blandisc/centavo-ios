import Foundation

/// The currency the month adds up in. Pesos unless chosen otherwise (in the welcome or in
/// «Más»), or unless the payments themselves are clearly in another one (see
/// `CurrencySuggestion`). Not the phone's region: a region set to the US turned someone's
/// budget into dollars while every Wallet payment came in pesos.
enum CurrencyPreference {
    static let key = "primaryCurrency"
    /// What the expense sheet offers. Everything else still arrives from Wallet and is
    /// listed apart, as always.
    static let offered = ["MXN", "USD", "EUR"]

    static let fallback = "MXN"

    /// What is saved, or pesos.
    static func resolve(_ stored: String) -> String {
        offered.contains(stored) ? stored : fallback
    }

    /// The one the person chose, or `nil` before choosing (or before iCloud brought it): a
    /// bare «$» isn't pinned to anything until then.
    static var chosen: String? {
        UserDefaults.standard.string(forKey: key).flatMap { $0.isEmpty ? nil : resolve($0) }
    }

    static var current: String {
        resolve(UserDefaults.standard.string(forKey: key) ?? "")
    }

    /// "pesos", inside a sentence.
    static func spoken(_ code: String) -> String {
        switch code {
        case "MXN": "pesos"
        case "USD": "dólares"
        case "EUR": "euros"
        default: code
        }
    }

    /// "🇲🇽  Peso mexicano": how a currency is named wherever one is chosen or shown in a form
    /// (`CurrencyOption` in its menu, and the menu's row). The one way to write it.
    static func flagged(_ code: String) -> String {
        let flag = flag(code)
        let name = singular(code)
        return flag.isEmpty ? name : "\(flag)  \(name)"
    }

    static func flag(_ code: String) -> String {
        switch code {
        case "MXN": "🇲🇽"
        case "USD": "🇺🇸"
        case "EUR": "🇪🇺"
        case "GBP": "🇬🇧"
        case "CAD": "🇨🇦"
        case "JPY": "🇯🇵"
        case "CHF": "🇨🇭"
        default: ""
        }
    }

    /// "Peso mexicano".
    static func singular(_ code: String) -> String {
        switch code {
        case "MXN": "Peso mexicano"
        case "USD": "Dólar de EE. UU."
        case "EUR": "Euro"
        case "GBP": "Libra esterlina"
        case "CAD": "Dólar canadiense"
        case "JPY": "Yen japonés"
        case "CHF": "Franco suizo"
        default: Locale(identifier: "es_MX").localizedString(forCurrencyCode: code)?.capitalizedFirst ?? code
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
