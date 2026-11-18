import SwiftUI

/// One currency inside a currency menu: its flag and full name («🇲🇽 Peso mexicano»). The same in
/// every menu that picks a currency (the expense's, «Moneda principal», «Mi dinero»), so they read
/// as one (owner, 2026-11-15); before, one said «MXN», another «Pesos (MXN)», another «pesos».
/// The system's menu draws it, with the checkmark on the one chosen (it shows no subtitle).
struct CurrencyOption: View {
    let code: String

    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        Text(CurrencyPreference.flagged(code))
    }
}

/// The options of a currency menu, each tagged with its code.
struct CurrencyOptions: View {
    let codes: [String]

    var body: some View {
        ForEach(codes, id: \.self) { code in
            CurrencyOption(code).tag(code)
        }
    }
}

/// A currency as a tile: its symbol over its short name, brass when chosen. The welcome's
/// three and «Mi dinero»'s carousel are the same tile. The caller wraps it in a `Button` and adds
/// `.currencyTileAccessibility(code:selected:)`.
struct CurrencyTile: View {
    let code: String
    let selected: Bool
    /// Shares the row's width with its neighbors instead of sizing to its text.
    var fills = false

    var body: some View {
        VStack(spacing: Theme.Space.xxxs) {
            Text(MoneyCurrency.symbol(code))
                .font(.ticket(.bodyStrong))
                .foregroundStyle(selected ? Theme.brass : Theme.ink)
            Text(MoneyCurrency.name(code))
                .font(.ticket(.micro))
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, fills ? Theme.Space.none : Theme.Space.xs)
        .frame(minWidth: fills ? nil : Theme.Size.moneyCurrencyTile,
               maxWidth: fills ? .infinity : nil,
               minHeight: Theme.Size.tallRow)
        .background(selected ? Theme.brass.opacity(Theme.Opacity.moneyCurrency) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(selected ? Theme.brass : Theme.outline, lineWidth: Theme.Stroke.hairline)
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// What VoiceOver says for a `CurrencyTile` button: the currency's name, and «seleccionado».
    func currencyTileAccessibility(code: String, selected: Bool) -> some View {
        accessibilityLabel(MoneyCurrency.name(code))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The currencies «Mi dinero» counts in, with the symbol and short name its tiles print.
enum MoneyCurrency {
    /// In the order people here reach for them.
    static let offered = ["MXN", "USD", "EUR", "GBP", "CAD", "JPY", "CHF"]

    static func symbol(_ code: String) -> String {
        switch code {
        case "MXN": "$"
        case "USD": "US$"
        case "EUR": "€"
        case "GBP": "£"
        case "CAD": "CA$"
        case "JPY": "¥"
        default: code
        }
    }

    static func name(_ code: String) -> String {
        switch code {
        case "MXN": String(localized: "pesos")
        case "USD": String(localized: "dólares")
        case "EUR": String(localized: "euros")
        case "GBP": String(localized: "libras")
        case "CAD": String(localized: "dól. can.")
        case "JPY": String(localized: "yenes")
        case "CHF": String(localized: "francos")
        default: code
        }
    }
}

