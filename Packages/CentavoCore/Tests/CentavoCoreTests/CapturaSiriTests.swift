import Foundation
import Testing
@testable import CentavoCore

/// Round 2 of the personas (2026-11-18): what a payment kept pending keeps of its amount, and
/// how it reads once the iPhone's language changes.
@Suite struct CapturaSiriTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: The whole payment connected to «Importe»

    @Test func elPagoCompletoConservaLaCifraYLlenaLaHoja() throws {
        let payment = try #require(PendingPayment.unsaved(amount: "American Express México\nGoogle\nMXN 319.00",
                                                          merchant: "Google", card: nil, date: now))
        #expect(payment.amount == "MXN 319.00")
        let fill = payment.prefill(primary: "USD")
        #expect(fill.amountText == "319.00")
        #expect(fill.currency == "MXN")
    }

    @Test func unaLineaLargaConElMontoAlFinalNoLoPierde() throws {
        let text = "Pago con tarjeta American Express terminación 1234 en Google LLC Mountain View California MXN 319.00"
        #expect(text.count > PendingPayment.maxText)
        let payment = try #require(PendingPayment.unsaved(amount: text, merchant: "Google", card: nil, date: now))
        #expect(payment.amount == "MXN 319.00")
        #expect(payment.prefill(primary: "MXN").amountText == "319.00")
    }

    @Test func soloElMontoQuedaComoLlego() throws {
        let payment = try #require(PendingPayment.unsaved(amount: " $89.00 ", merchant: "Oxxo", card: nil, date: now))
        #expect(payment.amount == "$89.00")
        #expect(payment.text == "$89.00 en Oxxo")
    }

    @Test func cifrasQueNoSeLeenSeGuardanIgual() throws {
        let payment = try #require(PendingPayment.unsaved(amount: "1.2.3 MXN", merchant: "Oxxo", card: nil, date: now))
        #expect(payment.amount == "1.2.3 MXN")
    }

    // MARK: Put together when shown

    @Test func loQueSeMuestraSeArmaConSusPartes() {
        // Kept while the iPhone was in English: the parts are what is shown now.
        let kept = PendingPayment(kind: .unsaved, text: "$89 at Oxxo", date: now, amount: "$89", merchant: "Oxxo")
        #expect(kept.display == PendingPayment.line(amount: "$89", merchant: "Oxxo"))
        #expect(kept.display == "$89 en Oxxo")
    }

    @Test func sinComercioOAvisoIlegibleSeMuestraElTexto() {
        let amountOnly = PendingPayment.unsaved(amount: "$89", merchant: nil, card: nil, date: now)
        #expect(amountOnly?.display == "$89")
        let unread = PendingPayment(kind: .unread, text: "Google", date: now)
        #expect(unread.display == "Google")
    }
}
