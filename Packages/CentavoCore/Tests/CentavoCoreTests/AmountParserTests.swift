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
    }

    @Test func rejectsTextWithoutDigits() {
        #expect(AmountParser.parse("") == nil)
        #expect(AmountParser.parse("$") == nil)
    }
}
