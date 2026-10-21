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

    /// A space may group thousands; it used to cut the figure at "MXN 1".
    @Test func digitsGroupedWithSpaces() throws {
        let notice = try #require(WalletNotice.parse("Google\nMXN 1 234,56"))
        #expect(notice.amount.value == Decimal(string: "1234.56"))
        #expect(notice.amountText == "MXN 1 234,56")
        #expect(notice.merchant == "Google")
        #expect(notice.card == nil)
    }

    @Test func aRefundSubtracts() throws {
        let notice = try #require(WalletNotice.parse("BBVA\nReembolso de Liverpool\nMXN 230.00"))
        #expect(notice.amount.value == -230)
        #expect(notice.amountText == "-MXN 230.00")
        #expect(notice.merchant == "Liverpool")
        #expect(notice.card == "BBVA")
        // The intent re-reads this text: the sign has to survive.
        #expect(CaptureText.amount(in: notice.amountText)?.value == -230)
    }

    @Test(arguments: ["Apple Cash\nRecibiste $200.00 de Ana", "Te enviaron MXN 500.00"])
    func moneyThatCameInIsNotSpending(text: String) {
        #expect(WalletNotice.parse(text) == nil)
    }

    /// Atajos can hand over the app's name first: the bank must stay the card, and the
    /// concept above the amount the merchant (the owner's first notice saved the bank).
    @Test func anExtraFirstLineDoesNotShiftTheMerchant() throws {
        let notice = try #require(WalletNotice.parse("Wallet\nAmerican Express México\nGoogle\nMXN 319.00"))
        #expect(notice.merchant == "Google")
        #expect(notice.card == "American Express México")
        #expect(notice.amount.value == 319)
    }

    @Test func anyLinesAboveTheCardAreIgnored() throws {
        let notice = try #require(WalletNotice.parse("Ahora\nBBVA\nOxxo Roble\n$47.50"))
        #expect(notice.merchant == "Oxxo Roble")
        #expect(notice.card == "BBVA")
    }

    @Test func theConceptAfterTheAmountStillCounts() throws {
        let notice = try #require(WalletNotice.parse("MXN 99.00\nSpotify"))
        #expect(notice.merchant == "Spotify")
        #expect(notice.card == nil)
    }

    @Test func aConceptThatLooksLikeMoneyIsNotTheAmount() throws {
        let notice = try #require(WalletNotice.parse("BBVA\nOXXO 123 MTY\nMXN 47.50"))
        #expect(notice.amount.value == Decimal(string: "47.5"))
        #expect(notice.merchant == "OXXO 123 MTY")
        #expect(notice.card == "BBVA")
    }

    /// The owner's real notices: the bank, the amount, then the merchant. Reading upward from
    /// the amount took the bank (saved as «American Express México», card empty).
    @Test func bankThenAmountThenMerchant() throws {
        let notice = try #require(WalletNotice.parse("American Express México\nMXN 1,060.00\nLa Docena"))
        #expect(notice.merchant == "La Docena")
        #expect(notice.card == "American Express México")
        #expect(notice.amount.value == 1060)
        let hsbc = try #require(WalletNotice.parse("HSBC México\nMXN 20.00\nOxxo Roble"))
        #expect(hsbc.merchant == "Oxxo Roble")
        #expect(hsbc.card == "HSBC México")
    }

    @Test(arguments: ["American Express México\nMXN 1,060.00 en La Docena",
                      "American Express México\nMXN 1,060.00\nen La Docena",
                      "American Express México\nCompra en La Docena\nMXN 1,060.00"])
    func onlyThePlaceIsTheMerchant(text: String) throws {
        let notice = try #require(WalletNotice.parse(text))
        #expect(notice.merchant == "La Docena")
        #expect(notice.card == "American Express México")
    }

    /// Still the bank as the merchant after two fixes: any extra line above the card (when the
    /// notice came, the app's name) pushed the card down into the merchant's place. The bank
    /// is now known by its name, wherever it sits.
    @Test(arguments: ["Ahora\nAmerican Express México\nMXN 1,060.00\nLa Docena",
                      "10:32\nAmerican Express México\nMXN 1,060.00\nLa Docena",
                      "hace 2 min\nWallet\nAmerican Express México\nMXN 1,060.00\nLa Docena",
                      "American Express México\u{200B}\n\u{200B}\nMXN 1,060.00\nLa Docena",
                      "American Express México\nLa Docena\nMXN 1,060.00",
                      "La Docena\nAmerican Express México\nMXN 1,060.00",
                      "MXN 1,060.00\nLa Docena\nAmerican Express México"])
    func theBankIsNeverTheMerchant(text: String) throws {
        let notice = try #require(WalletNotice.parse(text))
        #expect(notice.merchant == "La Docena")
        #expect(notice.card == "American Express México")
        #expect(notice.amount.value == 1060)
    }

    @Test func aCardThePersonAlreadyUsesIsTheCard() throws {
        let notice = try #require(WalletNotice.parse("Ahora\nMi negra\nMXN 20.00\nOxxo Roble",
                                                     knownCards: ["Mi Negra"]))
        #expect(notice.merchant == "Oxxo Roble")
        #expect(notice.card == "Mi negra")
    }

    @Test func cardWordsAndDigitsMarkTheCard() throws {
        let notice = try #require(WalletNotice.parse("Tarjeta de crédito •••• 1234\nGoogle\nMXN 319.00"))
        #expect(notice.merchant == "Google")
        #expect(notice.card == "Tarjeta de crédito •••• 1234")
    }

    @Test func onlyTheBankLeavesNoMerchant() throws {
        let notice = try #require(WalletNotice.parse("BBVA\nMXN 47.50"))
        #expect(notice.merchant == nil)
        #expect(notice.card == "BBVA")
    }

    @Test(arguments: ["Oxxo Roble", "Liverpool", "La Docena", "Uber Eats", "Google", "Spotify"])
    func shopsAreNotCards(name: String) {
        #expect(!WalletNotice.looksLikeCard(name))
    }

    @Test(arguments: ["American Express México", "BBVA México", "Nu", "HSBC", "Banorte",
                      "Mercado Pago", "Apple Card", "Visa •••• 4321"])
    func banksAreCards(name: String) {
        #expect(WalletNotice.looksLikeCard(name))
    }
}
