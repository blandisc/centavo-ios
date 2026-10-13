import Foundation
import Testing
@testable import CentavoCore

@Suite struct CaptureGuardTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func check(_ amount: Decimal, _ merchant: String = "Oxxo", card: String? = "BBVA",
                       recent: [RecentCapture] = []) -> CaptureGuard.Verdict {
        CaptureGuard.check(amount: amount, merchant: merchant, card: card, at: now, recent: recent)
    }

    @Test func aNormalPaymentIsSaved() {
        #expect(check(89) == .save)
    }

    @Test func aZeroAmountIsAWalletGlitch() {
        #expect(check(0) == .empty)
    }

    @Test func refundsAreNotMistakenForGlitches() {
        #expect(check(-89) == .save)
    }

    @Test func theSameTapTwiceWithinMinutesIsOnePayment() {
        let recent = [RecentCapture(amount: 89, merchant: "OXXO ", card: "bbva",
                                    date: now.addingTimeInterval(-120))]
        #expect(check(89, recent: recent) == .duplicate)
    }

    @Test func theSamePurchaseLaterIsANewPayment() {
        let recent = [RecentCapture(amount: 89, merchant: "Oxxo", card: "BBVA",
                                    date: now.addingTimeInterval(-10 * 60))]
        #expect(check(89, recent: recent) == .save)
    }

    @Test func anythingDifferentIsANewPayment() {
        let recent = [RecentCapture(amount: 89, merchant: "Oxxo", card: "BBVA",
                                    date: now.addingTimeInterval(-60))]
        #expect(check(90, recent: recent) == .save)
        #expect(check(89, "Seven", recent: recent) == .save)
        #expect(check(89, card: "Nu", recent: recent) == .save)
    }
}
