import Foundation
import Testing
@testable import CentavoCore

/// What the Wallet automation says back of an amount (`CaptureText.shown`, 2026-11-18): the
/// figure it read, not the whole payment it came in.
@Suite struct CapturaTextoMostradoTests {
    @Test func elPagoCompletoSoloDiceLaCifra() {
        let shown = CaptureText.shown("ALL 2 GO MXN 300.00")
        #expect(shown == "MXN 300.00")
        #expect(!shown.contains("ALL 2 GO"))
        // Read again, it is the same amount.
        #expect(CaptureText.amount(in: shown)?.value == 300)
    }

    @Test(arguments: ["$89.00", "USD 24.99", "12,50 €"])
    func unMontoSoloQuedaIgual(text: String) {
        #expect(CaptureText.shown(text) == text)
    }

    @Test func loQueNoSeLeeQuedaComoLlego() {
        #expect(CaptureText.shown("Oxxo Roble Mty 50ht1") == "Oxxo Roble Mty 50ht1")
    }

    /// The Wallet intent keeps these as a payment with its shop and card, not as a notice
    /// that only brought a name (2026-11-18).
    @Test(arguments: ["1.2.3 MXN", "$1,234.567"])
    func cifrasConMonedaQueNoSeLeenCuentanComoDinero(text: String) {
        #expect(WalletNotice.mentionsMoney(text))
    }

    @Test func unComercioConNumerosNoEsDinero() {
        #expect(!WalletNotice.mentionsMoney("Oxxo Roble Mty 50ht1"))
    }
}
