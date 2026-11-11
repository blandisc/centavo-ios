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

    /// The edit sheet compares what it loaded with what the field shows: grouping what is
    /// already grouped must change nothing, or an untouched amount reads as typed again.
    @Test(arguments: ["1234.13", "1234567.89", "999.00", "0.50", "1000.00"])
    func groupingTwiceChangesNothing(text: String) {
        let once = AmountTyping.grouped(text)
        #expect(AmountTyping.grouped(once) == once)
    }

    /// An amount put into a field by the app (editing an expense, the budget) is written with
    /// a point whatever the region: with a comma it showed a hundred times bigger.
    @Test func anAmountLoadedIntoAFieldIsTheSameInARegionWithDecimalComma() {
        let amount = Decimal(string: "1234.5")!
        let text = amount.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(AmountTyping.written))
        #expect(text == "1234.50")
        #expect(AmountTyping.grouped(text) == "1,234.50")
        // What the region's own format would have given, and why it can't be used.
        let spanish = amount.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "es_ES")))
        #expect(AmountTyping.grouped(spanish) != "1,234.50")
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
