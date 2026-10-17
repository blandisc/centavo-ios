import Foundation

/// The currency the month adds up in. It starts as the region's when that is one of the
/// offered ones (pesos in Mexico), and the person can change it from «Más».
enum CurrencyPreference {
    static let key = "primaryCurrency"
    /// What the expense sheet offers. Everything else still arrives from Wallet and is
    /// listed apart, as always.
    static let offered = ["MXN", "USD", "EUR"]

    static var regionDefault: String {
        let region = Locale.current.currency?.identifier ?? "MXN"
        return offered.contains(region) ? region : "MXN"
    }

    /// What is saved, or the region's default.
    static func resolve(_ stored: String) -> String {
        offered.contains(stored) ? stored : regionDefault
    }

    static var current: String {
        resolve(UserDefaults.standard.string(forKey: key) ?? "")
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
