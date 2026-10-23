import Foundation
import Testing
@testable import CentavoCore

@Suite struct CategoryRulesTests {
    private static func day(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_760_000_000 + Double(day) * 86_400)
    }

    private func entry(_ merchant: String, _ category: String?, _ day: Int,
                       suggested: Bool = false) -> CategorizedExpense {
        CategorizedExpense(merchant: merchant, category: category, date: Self.day(day), isSuggested: suggested)
    }

    private func rules(_ choices: (String?, String)...) -> CategoryRules {
        var rules = CategoryRules()
        for (category, merchant) in choices { rules.learn(category, for: merchant) }
        return rules
    }

    // MARK: The key

    @Test(arguments: ["OXXO ROBLE", "oxxo roble", "  Oxxo   Roble ", "Óxxo\tRoble", "OXXO\nROBLE"])
    func caseAccentsAndSpacesMakeTheSameKey(spelling: String) {
        #expect(MerchantKey.normalized(spelling) == "oxxo roble")
    }

    @Test func numbersAndPunctuationStillMatter() {
        #expect(MerchantKey.normalized("OXXO 1234") != MerchantKey.normalized("OXXO 5678"))
        #expect(MerchantKey.normalized("Uber") != MerchantKey.normalized("Uber Eats"))
    }

    @Test func spacesInsideTheNameDoNotSplitTheMemory() {
        let history = [entry("OXXO  ROBLE", "Despensa", 1)]
        #expect(CategoryMemory.category(for: "Oxxo Roble", in: history) == "Despensa")
    }

    @Test func noMerchantIsNeverRemembered() {
        let history = [entry("Sin comercio", "Despensa", 1)]
        #expect(CategoryMemory.category(for: "Sin comercio", in: history) == nil)
        #expect(rules(("Despensa", "Sin comercio"), ("Casa", "  ")).entries.isEmpty)
    }

    // MARK: Learning

    @Test func theLatestChoiceWinsWhateverTheExpenseDate() {
        // Oxxo was filed under Despensa; this week's Oxxo got it from the memory. Correcting
        // last month's to Antojos is the newest decision, so the next one is Antojos.
        let history = [entry("Oxxo", "Antojos", 1), entry("Oxxo", "Despensa", 9)]
        let decided = rules(("Despensa", "Oxxo"), ("Antojos", "OXXO"))
        #expect(decided.choice(for: "oxxo") == .category("Antojos"))
        #expect(CategoryMemory.remembered(for: "Oxxo", rules: decided, history: history) == "Antojos")
        #expect(decided.entries.count == 1)
    }

    @Test func takingTheCategoryOffIsADecisionToo() {
        let decided = rules(("Despensa", "Oxxo"), (nil, "Oxxo"), ("  ", "Uber"))
        #expect(decided.choice(for: "Oxxo") == .uncategorized)
        #expect(decided.choice(for: "Uber") == .uncategorized)
        let history = [entry("Oxxo", "Despensa", 1)]
        #expect(CategoryMemory.remembered(for: "Oxxo", rules: decided, history: history) == nil)
        // Not even the catalog's guess: you said none.
        #expect(CategoryMemory.suggestion(for: "Oxxo", rules: decided, history: history) == nil)
    }

    @Test func withoutADecisionTheHistoryStillAnswers() {
        let history = [entry("Oxxo", "Despensa", 1), entry("Oxxo", "Casa", 5)]
        #expect(CategoryMemory.remembered(for: "Oxxo", rules: CategoryRules(), history: history) == "Casa")
        #expect(CategoryMemory.remembered(for: "Liverpool", rules: CategoryRules(), history: history) == nil)
    }

    @Test func aSuggestionIsNotAChoice() {
        let history = [entry("Taq Guero", "Comida", 1, suggested: true)]
        #expect(CategoryMemory.remembered(for: "Taq Guero", rules: CategoryRules(), history: history) == nil)
        #expect(CategoryMemory.latest(in: history).isEmpty)
    }

    @Test func oldChoicesAreForgottenPastTheLimit() {
        var many = CategoryRules()
        for index in 0...CategoryRules.limit { many.learn("Comida", for: "Lugar \(index)") }
        #expect(many.entries.count == CategoryRules.limit)
        #expect(many.choice(for: "Lugar 0") == nil)
        #expect(many.choice(for: "Lugar \(CategoryRules.limit)") == .category("Comida"))
    }

    @Test func choosingAgainMovesTheMerchantToTheNewestEnd() {
        var decided = rules(("Despensa", "Oxxo"), ("Transporte", "Uber"), ("Antojos", "Oxxo"))
        #expect(decided.entries.map(\.merchant) == ["uber", "oxxo"])
        decided.learn("Comida", for: "Rappi")
        #expect(decided.entries.last?.category == "Comida")
    }

    @Test func survivesBeingStored() {
        let decided = rules(("Despensa", "Oxxo"), (nil, "Uber"))
        #expect(CategoryRules(stored: decided.stored) == decided)
        #expect(CategoryRules(stored: "").entries.isEmpty)
        #expect(CategoryRules(stored: "not json").entries.isEmpty)
    }

    @Test func aRenamedCategoryKeepsItsMerchants() {
        var decided = rules(("Mascotas", "Petco"), ("Despensa", "Oxxo"))
        decided.renameCategory("mascotas", to: "Perrhijos")
        #expect(decided.choice(for: "Petco") == .category("Perrhijos"))
        #expect(decided.choice(for: "Oxxo") == .category("Despensa"))
    }

    // MARK: Hidden and deleted categories

    @Test func aHiddenOrDeletedCategoryIsNotFilledIn() {
        let decided = rules(("Mascotas", "Petco"))
        let history = [entry("Petco", "Mascotas", 1), entry("Bodega", "Mascotas", 2)]
        #expect(CategoryMemory.remembered(for: "Petco", rules: decided, history: history,
                                          hidden: ["mascotas "]) == nil)
        #expect(CategoryMemory.remembered(for: "Bodega", rules: decided, history: history,
                                          hidden: ["Mascotas"]) == nil)
        #expect(CategoryMemory.remembered(for: "Petco", rules: decided, history: history,
                                          hidden: ["Ropa"]) == "Mascotas")
    }

    @Test func aMerchantWhoseCategoryWasHiddenFallsBackToTheCatalog() {
        let decided = rules(("Mascotas", "Oxxo"))
        #expect(CategoryMemory.suggestion(for: "Oxxo", rules: decided, history: [],
                                          hidden: ["Mascotas"]) == "Despensa")
        #expect(CategoryMemory.suggestion(for: "Oxxo", rules: CategoryRules(), history: [],
                                          hidden: ["Despensa"]) == nil)
    }

    // MARK: Many at once (the importer)

    @Test func latestIndexesTheNewestChoicePerMerchant() {
        let history = [
            entry("Oxxo", "Despensa", 1), entry("OXXO", "Antojos", 9), entry("oxxo ", "Casa", 5),
            entry("Uber", nil, 3), entry("Rappi", "Comida", 2),
        ]
        let latest = CategoryMemory.latest(in: history)
        #expect(latest == ["oxxo": "Antojos", "rappi": "Comida"])
        #expect(CategoryMemory.remembered(for: "Óxxo", rules: CategoryRules(), latest: latest) == "Antojos")
        #expect(CategoryMemory.remembered(for: "Oxxo", rules: rules(("Casa", "Oxxo")), latest: latest) == "Casa")
        #expect(CategoryMemory.remembered(for: "Rappi", rules: CategoryRules(), latest: latest,
                                          hidden: ["Comida"]) == nil)
    }
}
