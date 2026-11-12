import Foundation
import Testing
@testable import CentavoCore

/// 2026-11-11: importar un CSV viejo después de renombrar una tarjeta o corregir un comercio
/// metía duplicados.
@Suite struct CSVImportPlanTests {
    private let day = Date(timeIntervalSince1970: 1_792_000_000)

    private func row(_ merchant: String, _ amount: Decimal, card: String? = nil, currency: String = "MXN",
                     after seconds: TimeInterval = 0) -> ExpenseRecord {
        ExpenseRecord(date: day.addingTimeInterval(seconds), merchant: merchant, amount: amount, currency: currency, card: card)
    }

    private func saved(_ merchant: String, _ amount: Decimal, card: String? = nil, shown: String? = nil,
                       currency: String? = "MXN", after seconds: TimeInterval = 0) -> CSVImportPlan.Existing {
        CSVImportPlan.Existing(date: day.addingTimeInterval(seconds), amount: amount, currency: currency,
                               merchant: merchant, displayName: shown, card: card)
    }

    private func classify(_ rows: [ExpenseRecord], _ existing: [CSVImportPlan.Existing],
                          merchants: MerchantRenames = MerchantRenames(),
                          cards: MerchantRenames = MerchantRenames()) -> [CSVImportPlan.Verdict] {
        CSVImportPlan.classify(rows, against: existing, primary: "MXN", merchantRenames: merchants, cardRenames: cards)
    }

    // MARK: Lo que ya hacía

    @Test func theSameExpenseIsAlreadyThere() {
        #expect(classify([row("Oxxo", 89, card: "Amex")], [saved("OXXO", 89, card: "amex")]) == [.alreadyThere])
        // Con fracción de segundo en la app y sin ella en el archivo; «$» es la moneda principal.
        #expect(classify([row("Oxxo", 89)], [saved("Oxxo", 89, currency: "$", after: 0.7)]) == [.alreadyThere])
        #expect(classify([row("Oxxo", Decimal(string: "89.00")!)], [saved("Oxxo", 89)]) == [.alreadyThere])
    }

    @Test func somethingElseIsNew() {
        #expect(classify([row("Oxxo", 89)], []) == [.new])
        #expect(classify([row("Oxxo", 89)], [saved("Oxxo", 90)]) == [.new])
        #expect(classify([row("Oxxo", 89)], [saved("Oxxo", 89, after: 1)]) == [.new])
        #expect(classify([row("Oxxo", 89, currency: "USD")], [saved("Oxxo", 89)]) == [.new])
    }

    @Test func twoIdenticalRowsInAFileAreTwoExpenses() {
        let uber = row("Uber", 100)
        #expect(classify([uber, uber], []) == [.new, .new])
        #expect(classify([uber, uber], [saved("Uber", 100)]) == [.alreadyThere, .new])
        #expect(classify([uber, uber], [saved("Uber", 100), saved("Uber", 100)]) == [.alreadyThere, .alreadyThere])
    }

    // MARK: El hueco

    @Test func aRenamedCardIsTheSameCard() {
        var cards = MerchantRenames()
        cards.rename("American Express México", to: "Amex")
        // Exportado como «American Express México»; hoy el gasto dice «Amex».
        #expect(classify([row("Uber", 100, card: "American Express México")], [saved("Uber", 100, card: "Amex")],
                         cards: cards) == [.alreadyThere])
        // Renombrada dos veces: el archivo más viejo también se reconoce.
        cards.rename("Amex", to: "Amex Oro")
        #expect(classify([row("Uber", 100, card: "American Express México"), row("Uber", 100, card: "Amex", after: 60)],
                         [saved("Uber", 100, card: "Amex Oro"), saved("Uber", 100, card: "Amex Oro", after: 60)],
                         cards: cards) == [.alreadyThere, .alreadyThere])
    }

    @Test func aCorrectedMerchantNameIsTheSameMerchant() {
        // El nombre se corrigió en la hoja del gasto: Al día recuerda el cambio.
        var merchants = MerchantRenames()
        merchants.rename("REST BORU OUM 0234", to: "Boru Oum")
        #expect(classify([row("REST BORU OUM 0234", 175)], [saved("Boru Oum", 175, shown: "Boru Oum")],
                         merchants: merchants) == [.alreadyThere])
        // Sin recuerdo del cambio, el nombre que se muestra (`displayName`) también cuenta.
        #expect(classify([row("Boru Oum", 175)], [saved("REST BORU OUM 0234", 175, shown: "Boru Oum")]) == [.alreadyThere])
    }

    @Test func sameMomentAndAmountWithAnotherNameLooksRepeated() {
        #expect(classify([row("Uber", 100)], [saved("Uber Eats", 100)]) == [.looksRepeated])
        #expect(classify([row("Uber", 100, card: "BBVA")], [saved("Uber", 100, card: "Amex")]) == [.looksRepeated])
        // Otro monto, otra moneda u otro segundo no se parecen.
        #expect(classify([row("Uber", 101)], [saved("Uber Eats", 100)]) == [.new])
        #expect(classify([row("Uber", 100, after: 60)], [saved("Uber Eats", 100)]) == [.new])
    }

    @Test func eachExpenseAnswersForOneRow() {
        // Un gasto guardado con otro nombre y dos renglones iguales: uno parece repetido, el otro es nuevo.
        let uber = row("Uber", 100)
        #expect(classify([uber, uber], [saved("Uber Eats", 100)]) == [.looksRepeated, .new])
    }

    @Test func theExactOneIsMatchedBeforeALookAlike() {
        // El renglón con otro nombre viene primero en el archivo: no le quita su gasto al exacto.
        let rows = [row("Uber viaje", 100), row("Uber", 100)]
        #expect(classify(rows, [saved("Uber", 100)]) == [.new, .alreadyThere])
        #expect(classify(rows, [saved("Uber", 100), saved("Didi", 100)]) == [.looksRepeated, .alreadyThere])
    }

    @Test func aMixedFileIsSplitInThree() {
        var cards = MerchantRenames()
        cards.rename("Banamex", to: "Citi")
        let rows = [
            row("Oxxo", 89, card: "Banamex"),              // ya está, con la tarjeta renombrada
            row("Cine", 180, card: "Citi", after: 60),     // nuevo
            row("SPOTIFY P1234", 129, after: 120),         // parece repetido: hoy se llama «Spotify»
        ]
        let existing = [saved("Oxxo", 89, card: "Citi"), saved("Spotify", 129, after: 120)]
        #expect(classify(rows, existing, cards: cards) == [.alreadyThere, .new, .looksRepeated])
    }
}
