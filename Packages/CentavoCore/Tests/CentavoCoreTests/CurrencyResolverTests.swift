import Foundation
import Testing
@testable import CentavoCore

@Suite struct CurrencyResolverTests {
    @Test(arguments: [
        ("MX$", "MXN"),
        ("MXN", "MXN"),
        ("€", "EUR"),
        ("EUR", "EUR"),
        ("USD", "USD"),
        ("US$", "USD"),
        ("£", "GBP"),
        ("R$", "BRL"),
        ("eur", "EUR"),
        (" € ", "EUR"),
        ("COP", "COP"),
    ] as [(String, String)])
    func mapsMarkersToISOCodes(marker: String, expected: String) {
        #expect(CurrencyResolver.isoCode(for: marker, primary: "MXN") == expected)
    }

    @Test func bareDollarAndMissingMarkerUseThePrimaryCurrency() {
        #expect(CurrencyResolver.isoCode(for: "$", primary: "MXN") == "MXN")
        #expect(CurrencyResolver.isoCode(for: nil, primary: "MXN") == "MXN")
        #expect(CurrencyResolver.isoCode(for: "", primary: "MXN") == "MXN")
        // Same app, someone whose money is in euros.
        #expect(CurrencyResolver.isoCode(for: "$", primary: "EUR") == "EUR")
    }

    @Test func signsAndSpacingDoNotChangeTheCurrency() {
        #expect(CurrencyResolver.isoCode(for: "-$", primary: "MXN") == "MXN")
        #expect(CurrencyResolver.isoCode(for: "+MX$", primary: "MXN") == "MXN")
    }

    @Test func unknownMarkersAreNotGuessed() {
        #expect(CurrencyResolver.isoCode(for: "₱", primary: "MXN") == nil)
        #expect(CurrencyResolver.isoCode(for: "pesos", primary: "MXN") == nil)
    }

    @Test(arguments: ["$", "MX$", "€", "USD", "COP", "₱", "S/", "kr", "Rp"])
    func recognizesWhatLooksLikeACurrency(marker: String) {
        #expect(CurrencyResolver.recognizes(marker))
    }

    @Test(arguments: ["pesos", "dolares", "mxn pesos", "e", "gasto"])
    func doesNotMistakeWordsForCurrencies(marker: String) {
        #expect(!CurrencyResolver.recognizes(marker))
    }
}
