import Foundation
import Testing
@testable import CentavoCore

@Suite struct AmountTypingTests {
    @Test(arguments: [
        ("8000", "8,000"), ("12000.5", "12,000.5"), ("1234567.89", "1,234,567.89"),
        ("999", "999"), ("", ""), (".", "0."), ("0.5", "0.5"), ("007", "7"),
        ("8,000", "8,000"), ("12.345", "12.34"), ("1.2.3", "1.23"),
    ])
    func groupsAsYouType(typed: String, shown: String) {
        #expect(AmountTyping.grouped(typed) == shown)
    }

    /// A region whose decimal pad has a "," key: that comma is the decimal point.
    @Test func aCommaKeyIsTheDecimalPoint() {
        #expect(AmountTyping.grouped("8000,5", decimalSeparator: ",") == "8,000.5")
    }

    @Test func stopsAtTheMostDigitsAnAmountCanHave() {
        #expect(AmountTyping.grouped("1234567890123") == "123,456,789,012")
    }

    @Test func whatIsShownReadsBackTheSame() {
        #expect(AmountParser.parse(AmountTyping.grouped("1234567.89"))?.value == Decimal(string: "1234567.89"))
    }
}

@Suite struct MerchantSuggestionsTests {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)
    private func entry(_ merchant: String, _ minutes: Double = 0) -> CategorizedExpense {
        CategorizedExpense(merchant: merchant, category: nil, date: now.addingTimeInterval(minutes * 60))
    }

    @Test func mostVisitedFirstWhenNothingIsTyped() {
        let history = [entry("Oxxo"), entry("Oxxo"), entry("Starbucks"), entry("Oxxo"), entry("Uber"), entry("Uber")]
        #expect(MerchantSuggestions.matches(for: "", history: history) == ["Oxxo", "Uber", "Starbucks"])
    }

    @Test func typedTextFiltersAndPrefixesWin() {
        let history = [entry("Carnes Ramos"), entry("Ramos"), entry("Ramos"), entry("Farmacias del Ahorro")]
        #expect(MerchantSuggestions.matches(for: "ram", history: history) == ["Ramos", "Carnes Ramos"])
        #expect(MerchantSuggestions.matches(for: "Ramos", history: history) == ["Carnes Ramos"])
    }

    @Test func accentsAndCaseDoNotMatterAndTheNewestSpellingShows() {
        let history = [entry("CINEPOLIS", 0), entry("Cinépolis", 5)]
        #expect(MerchantSuggestions.matches(for: "cine", history: history) == ["Cinépolis"])
    }
}
