import Foundation
import Testing
@testable import CentavoCore

@Suite struct WalletNoticeTests {
    /// The notification exactly as the owner's iPhone showed it.
    @Test func readsCardMerchantAndAmount() throws {
        let notice = try #require(WalletNotice.parse("American Express México\nGoogle\nMXN 319.00"))
        #expect(notice.card == "American Express México")
        #expect(notice.merchant == "Google")
        #expect(notice.amount.value == 319)
        #expect(notice.amount.currencyMarker == "MXN")
        #expect(notice.amountText == "MXN 319.00")
    }

    @Test func worksWithoutTheTitle() throws {
        let notice = try #require(WalletNotice.parse("Oxxo Roble\n$47.50"))
        #expect(notice.card == nil)
        #expect(notice.merchant == "Oxxo Roble")
        #expect(notice.amount.value == Decimal(string: "47.5"))
    }

    @Test func merchantAndAmountOnOneLine() throws {
        let notice = try #require(WalletNotice.parse("BBVA\nGoogle MXN 1,319.00"))
        #expect(notice.card == "BBVA")
        #expect(notice.merchant == "Google")
        #expect(notice.amount.value == 1319)
    }

    @Test func spacesAndBlankLinesDoNotMatter() throws {
        let notice = try #require(WalletNotice.parse("  Nu  \n\n  Uber Eats \n  USD 12.30 \n"))
        #expect(notice.card == "Nu")
        #expect(notice.merchant == "Uber Eats")
        #expect(notice.amount.currencyMarker == "USD")
    }

    @Test(arguments: ["Tu pase de abordar está listo\nVuelo 123", "Apple Cash\nTarjeta 1234", ""])
    func aNoticeWithoutACharge(text: String) {
        #expect(WalletNotice.parse(text) == nil)
    }
}
