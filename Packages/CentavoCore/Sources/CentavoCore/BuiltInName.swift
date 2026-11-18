import Foundation

/// The app's own category names and «Efectivo», which are stored data: expenses, the merchant
/// memory, backups, the CSV and iCloud always keep them in Spanish, so colors, icons and the
/// memory keep matching on them (2026-11-18, docs/DECISIONS.md). They are translated only when
/// shown (`shown`), and a name typed or said in the iPhone's language is stored back in Spanish
/// (`category`, `paymentSource`), so «Groceries» never becomes a second «Despensa».
///
/// Spanish is byte for byte what it was: a stored name whose translation is itself is shown as
/// it is stored, and a typed Spanish name is stored as it was typed.
public enum BuiltInName {
    /// The categories offered with one tap (`CategoryStyle.common` in the app), then the two
    /// names that read as «Hogar» («Casa», «Renta»).
    public static let categories = [
        "Despensa", "Comida", "Café", "Transporte", "Servicios", "Suscripciones", "Salidas",
        "Ropa", "Salud", "Hogar", "Compras", "Casa", "Renta",
    ]

    /// The way of paying every list offers.
    public static let cash = "Efectivo"

    /// How a stored category or payment name is shown: the translation of one of the app's own
    /// names (compared ignoring case and accents), anything else as it is.
    /// `display`: the translation of a canonical name (the catalog's, by default; tests pass
    /// their own).
    public static func shown(_ stored: String, display: (String) -> String = BuiltInName.localized) -> String {
        guard let canonical = builtIn(stored, among: categories + [cash]) else { return stored }
        let translated = display(canonical)
        return translated == canonical ? stored : translated
    }

    /// The category to store for a name typed, picked or said: one of the app's own in Spanish
    /// when it is its translation («Groceries» → «Despensa»), anything else as it is.
    public static func category(_ typed: String, display: (String) -> String = BuiltInName.localized) -> String {
        canonical(typed, among: categories, display: display)
    }

    /// The payment source to store: «Efectivo» for its translation («Cash»), anything else as it is.
    public static func paymentSource(_ typed: String, display: (String) -> String = BuiltInName.localized) -> String {
        canonical(typed, among: [cash], display: display)
    }

    /// Whether `word` is part of the translation of one of the app's own names that is not its
    /// Spanish («groc» in «Groceries»): a search for it also looks at what is stored in Spanish.
    /// Always `false` in Spanish.
    public static func inTranslation(_ word: String, display: (String) -> String = BuiltInName.localized) -> Bool {
        let wanted = fold(word)
        guard !wanted.isEmpty else { return false }
        return (categories + [cash]).contains { name in
            let translated = display(name)
            return translated != name && fold(translated).contains(wanted)
        }
    }

    /// The translation of one canonical name, from the catalog of the app (or the widgets: each
    /// reads its own `Bundle.main`). Without a catalog (`swift test`), the Spanish.
    public static func localized(_ canonical: String) -> String {
        switch canonical {
        case "Despensa": return String(localized: "Despensa", bundle: .main, comment: "Built-in category (stored in Spanish, shown translated)")
        case "Comida": return String(localized: "Comida", bundle: .main, comment: "Built-in category (stored in Spanish, shown translated)")
        case "Café": return String(localized: "Café", bundle: .main, comment: "Built-in category (stored in Spanish, shown translated)")
        case "Transporte": return String(localized: "Transporte", bundle: .main, comment: "Built-in category (stored in Spanish, shown translated)")
        case "Servicios": return String(localized: "Servicios", bundle: .main, comment: "Built-in category: power, water, gas, phone (stored in Spanish, shown translated)")
        case "Suscripciones": return String(localized: "Suscripciones", bundle: .main, comment: "Built-in category (stored in Spanish, shown translated)")
        case "Salidas": return String(localized: "Salidas", bundle: .main, comment: "Built-in category: bars, movies, nights out (stored in Spanish, shown translated)")
        case "Ropa": return String(localized: "Ropa", bundle: .main, comment: "Built-in category (stored in Spanish, shown translated)")
        case "Salud": return String(localized: "Salud", bundle: .main, comment: "Built-in category (stored in Spanish, shown translated)")
        case "Hogar": return String(localized: "Hogar", bundle: .main, comment: "Built-in category (stored in Spanish, shown translated)")
        case "Compras": return String(localized: "Compras", bundle: .main, comment: "Built-in category: shopping (stored in Spanish, shown translated)")
        case "Casa": return String(localized: "Casa", bundle: .main, comment: "Built-in category name read as «Hogar»; also the VoiceOver name of the house icon")
        case "Renta": return String(localized: "Renta", bundle: .main, comment: "Built-in category name read as «Hogar»; also a suggested fixed expense")
        case "Efectivo": return String(localized: "Efectivo", bundle: .main, comment: "Built-in payment method: cash (stored in Spanish, shown translated)")
        default: return canonical
        }
    }

    /// The canonical name `typed` is: itself when it is the Spanish one, the Spanish one when it
    /// is its translation, `typed` otherwise.
    private static func canonical(_ typed: String, among names: [String],
                                  display: (String) -> String) -> String {
        if builtIn(typed, among: names) != nil { return typed }
        let wanted = fold(typed)
        guard !wanted.isEmpty else { return typed }
        return names.first { fold(display($0)) == wanted } ?? typed
    }

    private static func builtIn(_ name: String, among names: [String]) -> String? {
        let wanted = fold(name)
        return names.first { fold($0) == wanted }
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
