import Foundation
import Testing
@testable import CentavoCore

@Suite struct MerchantCatalogTests {
    @Test(arguments: [
        ("OXXO ROBLE MTY 1234", "Despensa"),
        ("Oxxo Roble Mty 50ht1", "Despensa"),
        ("UBER *TRIP", "Transporte"),
        ("Uber Eats", "Comida"),
        ("DIDI FOOD MX", "Comida"),
        ("NETFLIX.COM", "Suscripciones"),
        ("CFE SUMINISTRADOR", "Servicios"),
        ("AT&T México", "Servicios"),
        ("Sam's Club", "Despensa"),
        ("Cinépolis Galerías", "Salidas"),
        ("Farmacias del Ahorro 123", "Salud"),
        ("Mercado Libre", "Compras"),
        ("H&M Parque Delta", "Ropa"),
    ] as [(String, String)])
    func knowsCommonMexicanMerchants(merchant: String, category: String) {
        #expect(MerchantCatalog.category(for: merchant) == category, "«\(merchant)»")
    }

    /// Whole words only: a brand hidden inside another word is not that brand.
    @Test(arguments: ["Boxxon", "Superuberto", "Boru Oum", "Zapatos Max", ""])
    func doesNotGuessFromPiecesOfWords(merchant: String) {
        #expect(MerchantCatalog.category(for: merchant) == nil, "«\(merchant)»")
    }

    @Test func whatYouChoseWinsOverTheCatalog() {
        let history = [CategorizedExpense(merchant: "Oxxo", category: "Antojos", date: .now)]
        #expect(MerchantCatalog.suggestion(for: "OXXO", history: history) == "Antojos")
        #expect(MerchantCatalog.suggestion(for: "Uber", history: history) == "Transporte")
    }
}
