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

    /// "Pesos (MXN)".
    static func name(_ code: String) -> String {
        switch code {
        case "MXN": "Pesos (MXN)"
        case "USD": "Dólares (USD)"
        case "EUR": "Euros (EUR)"
        default: code
        }
    }
}
