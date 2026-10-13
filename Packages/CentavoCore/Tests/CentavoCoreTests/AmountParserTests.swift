import Foundation
import Testing
@testable import CentavoCore

@Suite struct AmountParserTests {
    @Test(arguments: [
        ("$1,234.56", "1234.56", "$"),
        ("MX$89.00", "89", "MX$"),
        ("$ 45", "45", "$"),
        ("12,50 €", "12.5", "€"),
        ("1.234,56 €", "1234.56", "€"),
        ("USD 1,000", "1000", "USD"),
        ("$1,000", "1000", "$"),
        ("0.5", "0.5", nil),
    ] as [(String, String, String?)])
    func parsesWalletAmounts(raw: String, expected: String, marker: String?) throws {
        let parsed = try #require(AmountParser.parse(raw))
        #expect(parsed.value == Decimal(string: expected))
        #expect(parsed.currencyMarker == marker)
    }

    @Test func negativeAmountsAreRefunds() throws {
        #expect(try #require(AmountParser.parse("-$20.00")).value == -20)
        #expect(try #require(AmountParser.parse("($20.00)")).value == -20)
        #expect(try #require(AmountParser.parse("$-20.00")).value == -20)
        #expect(try #require(AmountParser.parse("−$20.00")).value == -20)
        #expect(try #require(AmountParser.parse("-1.234,56 €")).value == Decimal(string: "-1234.56"))
    }

    @Test func aRefundKeepsItsCurrency() throws {
        #expect(try #require(AmountParser.parse("-MX$20.00")).currencyMarker == "MX$")
        #expect(try #require(AmountParser.parse("($20.00)")).currencyMarker == "$")
    }

    @Test func rejectsTextWithoutDigits() {
        #expect(AmountParser.parse("") == nil)
        #expect(AmountParser.parse("$") == nil)
    }

    @Test func absurdlyLargeAmountsAreRejectedNotRounded() {
        #expect(AmountParser.parse("999999999999") != nil)              // 12 digits: fine
        #expect(AmountParser.parse("1000000000000") == nil)             // 13: not an amount
        #expect(AmountParser.parse(String(repeating: "9", count: 42)) == nil)
        #expect(AmountParser.parse(String(repeating: "9", count: 400)) == nil)
    }

    @Test func aTailThatIsNeitherCentsNorAGroupIsNotMoney() {
        #expect(AmountParser.parse("0.0001") == nil)
        #expect(AmountParser.parse("1.23456") == nil)
        #expect(AmountParser.parse("1,000")?.value == 1000)             // a group of three
        #expect(AmountParser.parse("1,00")?.value == 1)                 // cents
    }

    @Test func swissApostropheGroupingDoesNotLeakIntoTheCurrency() throws {
        let parsed = try #require(AmountParser.parse("CHF 1'234.56"))
        #expect(parsed.value == Decimal(string: "1234.56"))
        #expect(parsed.currencyMarker == "CHF")
        #expect(AmountParser.parse("1’234.56")?.currencyMarker == nil)  // typographic apostrophe
    }

    @Test func invisibleDirectionMarksAreIgnored() throws {
        let parsed = try #require(AmountParser.parse("\u{200F}\u{202B}$89.00\u{202C}\u{200E}"))
        #expect(parsed.value == 89)
        #expect(parsed.currencyMarker == "$")
    }

    @Test func digitsFromOtherScriptsAreNotMisread() {
        #expect(AmountParser.parse("٣٤") == nil)
        #expect(AmountParser.parse("１２３") == nil)
        #expect(AmountParser.parse("½") == nil)
    }

    @Test func neverCrashesOrReturnsNonsenseOnRandomJunk() {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("0123456789.,-−()$€ MXUSD'’\u{00A0}\u{200F}abc٣½e+*/")
        for _ in 0..<5_000 {
            let length = Int.random(in: 0...60, using: &generator)
            let text = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            if let parsed = AmountParser.parse(text) {
                #expect(parsed.value.isFinite)
                #expect(parsed.value.magnitude < 1_000_000_000_000)
            }
        }
    }
}
