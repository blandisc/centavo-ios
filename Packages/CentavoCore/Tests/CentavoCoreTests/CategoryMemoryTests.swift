import Foundation
import Testing
@testable import CentavoCore

@Suite struct CategoryMemoryTests {
    private static func day(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_760_000_000 + Double(day) * 86_400)
    }

    private func entry(_ merchant: String, _ category: String?, _ day: Int) -> CategorizedExpense {
        CategorizedExpense(merchant: merchant, category: category, date: Self.day(day))
    }

    @Test func remembersTheCategoryYouGaveTheMerchant() {
        let history = [entry("Oxxo", "Despensa", 1)]
        #expect(CategoryMemory.category(for: "Oxxo", in: history) == "Despensa")
    }

    @Test func aMerchantYouHaveNeverFiledGetsNothing() {
        let history = [entry("Oxxo", "Despensa", 1)]
        #expect(CategoryMemory.category(for: "Liverpool", in: history) == nil)
        #expect(CategoryMemory.category(for: "", in: history) == nil)
        #expect(CategoryMemory.category(for: "Oxxo", in: []) == nil)
    }

    @Test func theMostRecentChoiceWins() {
        let history = [
            entry("Oxxo", "Despensa", 1),
            entry("Oxxo", "Antojos", 9),
            entry("Oxxo", "Casa", 5),
        ]
        #expect(CategoryMemory.category(for: "Oxxo", in: history) == "Antojos")
    }

    @Test func theAnswerDoesNotDependOnFetchOrder() {
        let entries = [
            entry("Oxxo", "Despensa", 1),
            entry("Oxxo", "Antojos", 9),
            entry("Oxxo", "Casa", 5),
        ]
        #expect(CategoryMemory.category(for: "Oxxo", in: entries.reversed()) == "Antojos")
    }

    @Test func uncategorizedPastExpensesAreSkippedNotTreatedAsAnAnswer() {
        let history = [
            entry("Oxxo", "Despensa", 1),
            entry("Oxxo", nil, 9),
        ]
        #expect(CategoryMemory.category(for: "Oxxo", in: history) == "Despensa")
    }

    @Test(arguments: ["OXXO", "oxxo", "  Oxxo  ", "Óxxo"])
    func caseAccentsAndPaddingDoNotMakeADifferentMerchant(spelling: String) {
        let history = [entry("Oxxo", "Despensa", 1)]
        #expect(CategoryMemory.category(for: spelling, in: history) == "Despensa")
    }

    @Test func differentStoreNumbersAreDifferentMerchants() {
        // Guessing that these are one place would be wrong often enough to hurt.
        let history = [entry("OXXO 1234", "Despensa", 1)]
        #expect(CategoryMemory.category(for: "OXXO 5678", in: history) == nil)
    }

    @Test func knownCategoriesComeBackMostUsedFirst() {
        let history = [
            entry("Oxxo", "Despensa", 1),
            entry("Soriana", "Despensa", 2),
            entry("Netflix", "Suscripciones", 3),
            entry("Uber", nil, 4),
            entry("Rappi", "  ", 5),
            entry("Bodega", "despensa", 6),
        ]
        #expect(CategoryMemory.known(in: history) == ["despensa", "Suscripciones"])
    }

    @Test func noHistoryMeansNoKnownCategories() {
        #expect(CategoryMemory.known(in: []).isEmpty)
        #expect(CategoryMemory.known(in: [entry("Uber", nil, 1)]).isEmpty)
    }
}
