import Foundation
import Testing
@testable import CentavoCore

@Suite struct MerchantNameTests {
    @Test(arguments: [
        ("CLIP*MX TAQ GUERO 02", "Taq Guero"),
        ("AMZN MKTP MX*2K3J", "Amazon"),
        ("MERPAGO*ESTETICAVALE", "Esteticavale"),
        ("OXXO ROBLE MTY 1234", "Oxxo"),
        ("Oxxo Roble Mty 50ht1", "Oxxo"),
        ("UBER *TRIP", "Uber"),
        ("UBER *EATS", "Uber Eats"),
        ("PAYPAL *SPOTIFY", "Spotify"),
        ("FARMACIAS DEL AHORRO 123", "Farmacias del Ahorro"),
        ("TACOS EL PASTOR SUC CENTRO", "Tacos el Pastor"),
        ("REFACCIONARIA LOPEZ SA DE CV", "Refaccionaria Lopez"),
        ("PANADERIA LA ESPIGA S.A. de C.V.", "Panaderia la Espiga"),
        ("SQ *CAFE CENTRAL", "Cafe Central"),
        ("FARMACIA 24 HORAS", "Farmacia 24 Horas"),
        ("GASOLINERA G500 LOS ANGELES", "Gasolinera los Angeles"),
        ("GOOGLE *DUOLINGO", "Duolingo"),
        ("GOOGLE *YouTube Premium", "YouTube"),
        ("DISNEY STORE", "Disney Store"),
        ("STEAM CAR WASH", "Steam Car Wash"),
        ("DISNEY PLUS", "Disney+"),
    ] as [(String, String)])
    func readsWalletNames(raw: String, readable: String) {
        #expect(MerchantName.readable(raw) == readable, "«\(raw)»")
    }

    /// A name someone wrote, or one Wallet already sends readable, stays as it is.
    @Test(arguments: ["Tacos Don Beto", "Oxxo", "Sin comercio", "", "Café Avellaneda", "Netflix",
                      "CLIP*MX 77812", "MERPAGO*12345", "SA DE CV", "Mx Café", "GOOGLE"])
    func leavesReadableNamesAlone(raw: String) {
        #expect(MerchantName.readable(raw) == nil, "«\(raw)»")
    }
}

@Suite struct CategoryPickTests {
    @Test func offersEachNameOnce() {
        let names = CategoryPick.candidates(["Despensa", "Comida"], ["comida", "Perrhijos"], ["Ninguna", " "])
        #expect(names == ["Despensa", "Comida", "Perrhijos"])
    }

    @Test func onlyAnOfferedCategoryComesBack() {
        let offered = ["Comida", "Café", "Perrhijos"]
        #expect(CategoryPick.validate("cafe", among: offered) == "Café")
        #expect(CategoryPick.validate("Perrhijos ", among: offered) == "Perrhijos")
        #expect(CategoryPick.validate("Ninguna", among: offered) == nil)
        #expect(CategoryPick.validate("Restaurantes", among: offered) == nil)
        #expect(CategoryPick.validate(nil, among: offered) == nil)
    }

    @Test func aSuggestionIsNotRememberedAsYourChoice() {
        let history = [
            CategorizedExpense(merchant: "Veterinaria Lomas", category: "Salud", date: .now, isSuggested: true),
        ]
        #expect(CategoryMemory.category(for: "Veterinaria Lomas", in: history) == nil)
        let confirmed = [CategorizedExpense(merchant: "Veterinaria Lomas", category: "Perrhijos", date: .now)]
        #expect(CategoryMemory.category(for: "Veterinaria Lomas", in: confirmed) == "Perrhijos")
    }
}
