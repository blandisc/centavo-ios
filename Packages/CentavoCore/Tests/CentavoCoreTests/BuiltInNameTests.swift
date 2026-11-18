import Testing
@testable import CentavoCore

/// The app's own categories and «Efectivo» are kept in Spanish and shown in the iPhone's
/// language (2026-11-18). The tests run without the app's catalog, so the English is passed in.
@Suite struct BuiltInNameTests {
    private static let english: [String: String] = [
        "Despensa": "Groceries", "Comida": "Food", "Café": "Coffee", "Transporte": "Transportation",
        "Servicios": "Utilities", "Suscripciones": "Subscriptions", "Salidas": "Going out",
        "Ropa": "Clothes", "Salud": "Health", "Hogar": "Home", "Compras": "Shopping",
        "Casa": "Home", "Renta": "Rent", "Efectivo": "Cash",
    ]

    private static func inEnglish(_ canonical: String) -> String { english[canonical] ?? canonical }
    private static func inSpanish(_ canonical: String) -> String { canonical }

    @Test func theAppsOwnNamesAreShownInEnglish() {
        #expect(BuiltInName.shown("Despensa", display: Self.inEnglish) == "Groceries")
        #expect(BuiltInName.shown("Salidas", display: Self.inEnglish) == "Going out")
        #expect(BuiltInName.shown("Efectivo", display: Self.inEnglish) == "Cash")
        #expect(BuiltInName.shown("Renta", display: Self.inEnglish) == "Rent")
        // Compared the way people read them: case, accents and spaces don't count.
        #expect(BuiltInName.shown("cafe", display: Self.inEnglish) == "Coffee")
        #expect(BuiltInName.shown(" ROPA ", display: Self.inEnglish) == "Clothes")
    }

    @Test func spanishIsShownExactlyAsStored() {
        for name in BuiltInName.categories + [BuiltInName.cash] {
            #expect(BuiltInName.shown(name, display: Self.inSpanish) == name)
        }
        // A spelling of its own stays that spelling, not the app's.
        #expect(BuiltInName.shown("cafe", display: Self.inSpanish) == "cafe")
        #expect(BuiltInName.shown("DESPENSA", display: Self.inSpanish) == "DESPENSA")
    }

    @Test func otherNamesAreShownAsTheyAre() {
        for name in ["Mascotas", "Gimnasio", "BBVA", "Nu", "Groceries", ""] {
            #expect(BuiltInName.shown(name, display: Self.inEnglish) == name)
        }
    }

    @Test func aTranslationTypedIsStoredInSpanish() {
        #expect(BuiltInName.category("Groceries", display: Self.inEnglish) == "Despensa")
        #expect(BuiltInName.category("going OUT ", display: Self.inEnglish) == "Salidas")
        // «Home» is «Hogar», the one offered with a tap, never «Casa».
        #expect(BuiltInName.category("home", display: Self.inEnglish) == "Hogar")
        #expect(BuiltInName.paymentSource("Cash", display: Self.inEnglish) == "Efectivo")
        // Each in its own list: «Cash» is no category, «Coffee» no way of paying.
        #expect(BuiltInName.category("Cash", display: Self.inEnglish) == "Cash")
        #expect(BuiltInName.paymentSource("Coffee", display: Self.inEnglish) == "Coffee")
    }

    @Test func spanishTypedIsStoredAsTyped() {
        for name in ["Despensa", "despensa", "Cafe", "Café", "Mascotas", "Groceries"] {
            #expect(BuiltInName.category(name, display: Self.inSpanish) == name)
        }
        #expect(BuiltInName.category("Despensa", display: Self.inEnglish) == "Despensa")
        #expect(BuiltInName.paymentSource("efectivo", display: Self.inEnglish) == "efectivo")
        #expect(BuiltInName.paymentSource("Nu", display: Self.inEnglish) == "Nu")
        #expect(BuiltInName.category("", display: Self.inEnglish) == "")
    }

    @Test func shownAndStoredRoundTrip() {
        // «Casa» reads as «Hogar», so its «Home» is stored as «Hogar».
        for name in BuiltInName.categories where name != "Casa" {
            let shown = BuiltInName.shown(name, display: Self.inEnglish)
            #expect(BuiltInName.category(shown, display: Self.inEnglish) == name)
        }
        let cash = BuiltInName.shown(BuiltInName.cash, display: Self.inEnglish)
        #expect(BuiltInName.paymentSource(cash, display: Self.inEnglish) == BuiltInName.cash)
    }

    @Test func aSearchWordInATranslationIsKnown() {
        #expect(BuiltInName.inTranslation("groc", display: Self.inEnglish))
        #expect(BuiltInName.inTranslation("CASH", display: Self.inEnglish))
        #expect(!BuiltInName.inTranslation("uber", display: Self.inEnglish))
        #expect(!BuiltInName.inTranslation("", display: Self.inEnglish))
        // In Spanish nothing is translated, so a search narrows as it always did.
        #expect(!BuiltInName.inTranslation("despensa", display: Self.inSpanish))
    }

    @Test func withoutTheAppsCatalogItIsSpanish() {
        // `swift test` has no catalog: the default reads the Spanish, as the app's tests do.
        #expect(BuiltInName.shown("Despensa") == "Despensa")
        #expect(BuiltInName.category("Despensa") == "Despensa")
        #expect(BuiltInName.localized("Efectivo") == "Efectivo")
    }
}
