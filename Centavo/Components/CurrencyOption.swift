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
