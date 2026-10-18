import Testing
@testable import CentavoCore

@Suite struct CurrencySuggestionTests {
    private let offered = ["MXN", "USD", "EUR"]

    /// The owner's case: the main currency came out as dollars, the Wallet payments are pesos.
    @Test func pesosPaymentsUnderDollarsSuggestPesos() {
        #expect(CurrencySuggestion.switchTo(markers: ["MXN", "MXN", "USD"], primary: "USD", offered: offered) == "MXN")
    }

    @Test func alreadyRightSuggestsNothing() {
        #expect(CurrencySuggestion.switchTo(markers: ["MXN", "MXN"], primary: "MXN", offered: offered) == nil)
    }

    /// A bare "$" follows whatever is main, so it is no evidence either way.
    @Test func bareDollarSignsAreNoEvidence() {
        #expect(CurrencySuggestion.switchTo(markers: ["$", "$", nil, "MXN"], primary: "USD", offered: offered) == nil)
        #expect(CurrencySuggestion.dominant(markers: [], primary: "MXN", offered: offered) == nil)
    }

    @Test func aTripAbroadIsNotAMajority() {
        #expect(CurrencySuggestion.switchTo(markers: ["MXN", "MXN", "EUR", "EUR"], primary: "MXN", offered: offered) == nil)
    }

    @Test func currenciesNotOfferedAreIgnored() {
        #expect(CurrencySuggestion.dominant(markers: ["COP", "COP", "COP"], primary: "MXN", offered: offered) == nil)
    }
}
