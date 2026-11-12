import Testing
@testable import CentavoCore

/// Owner's request (2026-11-11): «si llega un cargo que dice XYZ y tú lo cambias que diga Tacos
/// Pepe y le pones categoría de comida, que siempre que vuelva a llegar ese, lo mande a la
/// categoría con el nombre que tú escribiste».
@Suite struct MerchantRulesTests {
    private var renames = MerchantRenames()
    private var categories = CategoryRules()

    private mutating func learn(_ sent: String, as name: String, _ category: String?,
                                chose: Bool = true, theirs: Bool = true) {
        MerchantRules.learn(sent: sent, name: name, category: category, choseCategory: chose,
                            categoryIsTheirs: theirs, renames: &renames, categories: &categories)
    }

    private func applied(_ sent: String) -> MerchantRules.Applied {
        MerchantRules.applied(to: sent, renames: renames, categories: categories)
    }

    private var list: [MerchantRule] { MerchantRules.list(renames: renames, categories: categories) }

    // MARK: Which rule applies

    @Test mutating func aCorrectedPaymentComesBackWithItsNameAndCategory() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Pepe", choice: .category("Comida")))
    }

    @Test(arguments: ["xyz*1234 cdmx", "  XYZ*1234   CDMX ", "XÝZ*1234 CDMX", "Xyz*1234\tCdmx"])
    mutating func caseAccentsAndSpacesDoNotCount(spelling: String) {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        #expect(applied(spelling) == .init(name: "Tacos Pepe", choice: .category("Comida")))
    }

    @Test mutating func twoPlacesThatLookAlikeAreNotMixed() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        // Another terminal, another branch, a longer name: someone else until the owner says so.
        for other in ["XYZ*5678 CDMX", "XYZ*1234", "XYZ*1234 CDMX 2", "XYZ 1234 CDMX", "XYZ*1234 CDMX MX"] {
            #expect(applied(other) == .init(name: nil, choice: nil), "\(other)")
        }
    }

    @Test mutating func onlyTheCategoryIsARuleToo() {
        learn("OXXO ROBLE 1234", as: "OXXO ROBLE 1234", "Antojos")
        #expect(applied("oxxo roble 1234") == .init(name: nil, choice: .category("Antojos")))
    }

    @Test mutating func onlyTheNameKeepsTheCategoryItHad() {
        // Filed first, renamed another day without touching the category.
        learn("XYZ*1234 CDMX", as: "XYZ*1234 CDMX", "Comida")
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida", chose: false)
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Pepe", choice: .category("Comida")))
    }

    @Test mutating func renamingAnExpenseWithoutCategoryCarriesTheChoiceForItsOldText() {
        learn("XYZ*1234 CDMX", as: "XYZ*1234 CDMX", "Comida")
        // Another payment from there, still without a category, is the one renamed.
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", nil, chose: false)
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Pepe", choice: .category("Comida")))
    }

    @Test mutating func aSuggestionNobodyConfirmedIsNotLearnedWithTheName() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Despensa", chose: false, theirs: false)
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Pepe", choice: nil))
    }

    @Test mutating func theLastChoiceWins() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        learn("Tacos Pepe", as: "Tacos Pepe", "Salidas")
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Pepe", choice: .category("Salidas")))
        learn("Tacos Pepe", as: "Tacos Pepe", nil)
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Pepe", choice: .uncategorized))
    }

    @Test mutating func renamedTwiceLandsOnTheLastNameWithItsCategory() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        // The next payment arrived as «Tacos Pepe» and is corrected again.
        learn("Tacos Pepe", as: "Taquería Don Pepe", "Comida", chose: false)
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Taquería Don Pepe", choice: .category("Comida")))
        #expect(list.map(\.sent) == ["xyz*1234 cdmx"])
    }

    @Test mutating func renamingBackToWhatArrivesForgetsTheName() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        learn("Tacos Pepe", as: "XYZ*1234 CDMX", "Comida", chose: false)
        #expect(applied("XYZ*1234 CDMX") == .init(name: nil, choice: .category("Comida")))
    }

    // MARK: The list

    @Test mutating func theListShowsOneRulePerText() {
        learn("OXXO ROBLE 1234", as: "OXXO ROBLE 1234", "Antojos")
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        learn("UBER *TRIP", as: "UBER *TRIP", nil)
        #expect(list == [
            MerchantRule(sent: "xyz*1234 cdmx", name: "Tacos Pepe", category: "Comida", written: "XYZ*1234 CDMX"),
            MerchantRule(sent: "uber *trip", goesUncategorized: true, written: "UBER *TRIP"),
            MerchantRule(sent: "oxxo roble 1234", category: "Antojos", written: "OXXO ROBLE 1234"),
        ])
        #expect(list[0].arrivesAs == "XYZ*1234 CDMX")
    }

    @Test mutating func twoBranchesWithOneNameAreTwoRulesWithOneCategory() {
        learn("OXXO 1234", as: "Oxxo", "Despensa")
        learn("OXXO 5678", as: "Oxxo", "Despensa", chose: false)
        #expect(list == [
            MerchantRule(sent: "oxxo 5678", name: "Oxxo", category: "Despensa", written: "OXXO 5678"),
            MerchantRule(sent: "oxxo 1234", name: "Oxxo", category: "Despensa", written: "OXXO 1234"),
        ])
    }

    // MARK: Changing and deleting from the list

    @Test mutating func changingARuleChangesWhatComesNext() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        MerchantRules.change(list[0], name: "Tacos Don Pepe", choice: .category("Salidas"),
                             renames: &renames, categories: &categories)
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Don Pepe", choice: .category("Salidas")))
        // The old name's category does not stay behind as a rule of its own.
        #expect(list == [MerchantRule(sent: "xyz*1234 cdmx", name: "Tacos Don Pepe", category: "Salidas", written: "XYZ*1234 CDMX")])
    }

    @Test mutating func changingOnlyTheCategoryKeepsTheName() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        MerchantRules.change(list[0], name: "Tacos Pepe", choice: .uncategorized,
                             renames: &renames, categories: &categories)
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Pepe", choice: .uncategorized))
    }

    @Test mutating func aBlankNameGoesBackToTheOneThatArrives() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        MerchantRules.change(list[0], name: "  ", choice: .category("Comida"),
                             renames: &renames, categories: &categories)
        #expect(applied("XYZ*1234 CDMX") == .init(name: nil, choice: .category("Comida")))
        #expect(list == [MerchantRule(sent: "xyz*1234 cdmx", category: "Comida", written: "XYZ*1234 CDMX")])
    }

    @Test mutating func aRenamedTextKeepsItsAccentsThroughEveryChange() {
        learn("Cinépolis Peñón", as: "Cine del centro", "Salidas")
        #expect(list[0].arrivesAs == "Cinépolis Peñón")
        // Changed from the list, where only the key is known, and corrected again in the sheet.
        MerchantRules.change(list[0], name: "Cine", choice: .category("Salidas"),
                             renames: &renames, categories: &categories)
        learn("Cine", as: "El cine", "Salidas", chose: false)
        #expect(list.map(\.arrivesAs) == ["Cinépolis Peñón"])
        #expect(applied("CINEPOLIS PENON").name == "El cine")
        // A name kept before `written` existed still reads, in capitals.
        let old = MerchantRenames(stored: #"{"entries":[{"from":"cinepolis","to":"Cine"}]}"#)
        #expect(MerchantRules.list(renames: old, categories: CategoryRules())[0].arrivesAs == "CINEPOLIS")
    }

    @Test mutating func aNameWrittenWithAccentsReadsAsWritten() {
        learn("Cinépolis Peñón", as: "Cinépolis Peñón", "Salidas")
        #expect(list.map(\.sent) == ["cinepolis penon"])
        #expect(list[0].arrivesAs == "Cinépolis Peñón")
        // A choice kept before the list existed has only its key.
        #expect(MerchantRule(sent: "cinepolis penon").arrivesAs == "CINEPOLIS PENON")
    }

    @Test mutating func leavingTheCategoryToTheAppKeepsOnlyTheName() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        MerchantRules.change(list[0], name: "Tacos Pepe", choice: nil, renames: &renames, categories: &categories)
        #expect(applied("XYZ*1234 CDMX") == .init(name: "Tacos Pepe", choice: nil))
    }

    @Test mutating func aCategoryOnlyRuleCanGetAName() {
        learn("OXXO ROBLE 1234", as: "OXXO ROBLE 1234", "Antojos")
        MerchantRules.change(list[0], name: "Oxxo de la esquina", choice: .category("Antojos"),
                             renames: &renames, categories: &categories)
        #expect(list == [MerchantRule(sent: "oxxo roble 1234", name: "Oxxo de la esquina", category: "Antojos", written: "OXXO ROBLE 1234")])
    }

    @Test mutating func deletingARuleLeavesNothingBehind() {
        learn("XYZ*1234 CDMX", as: "XYZ*1234 CDMX", "Comida")
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida", chose: false)
        learn("OXXO ROBLE 1234", as: "OXXO ROBLE 1234", "Antojos")
        let rule = list.first { $0.sent == "xyz*1234 cdmx" }!
        MerchantRules.remove(rule, renames: &renames, categories: &categories)
        #expect(applied("XYZ*1234 CDMX") == .init(name: nil, choice: nil))
        #expect(applied("Tacos Pepe") == .init(name: nil, choice: nil))
        // The others stay.
        #expect(list == [MerchantRule(sent: "oxxo roble 1234", category: "Antojos", written: "OXXO ROBLE 1234")])
    }

    @Test mutating func deletingOneBranchKeepsTheOtherAndItsCategory() {
        learn("OXXO 1234", as: "Oxxo", "Despensa")
        learn("OXXO 5678", as: "Oxxo", "Despensa", chose: false)
        MerchantRules.remove(list[0], renames: &renames, categories: &categories)
        #expect(applied("OXXO 5678") == .init(name: nil, choice: nil))
        #expect(applied("OXXO 1234") == .init(name: "Oxxo", choice: .category("Despensa")))
    }

    @Test mutating func whatIsStoredReadsBackTheSame() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        MerchantRules.change(list[0], name: "", choice: .category("Comida"), renames: &renames, categories: &categories)
        #expect(MerchantRenames(stored: renames.stored) == renames)
        #expect(renames.entries.isEmpty)
    }

    // MARK: The expenses that were already there

    private func backfill(name: String? = "Tacos Pepe", category: String? = "Comida",
                          replacing previous: String? = nil) -> MerchantBackfill {
        MerchantBackfill(texts: ["XYZ*1234 CDMX"], name: name, category: category, replacing: previous)
    }

    @Test func earlierPaymentsWithTheSameTextTakeTheNameAndTheCategory() {
        let change = backfill().change(merchant: "xyz*1234  cdmx", category: nil, isSuggested: false)
        #expect(change == .init(name: "Tacos Pepe", category: "Comida"))
    }

    @Test func anotherPlaceIsLeftAlone() {
        #expect(backfill().change(merchant: "XYZ*5678 CDMX", category: nil, isSuggested: false) == nil)
        // One the owner renamed by hand to something else no longer has the text.
        #expect(backfill().change(merchant: "Tacos de la oficina", category: nil, isSuggested: false) == nil)
        #expect(backfill().change(merchant: "Sin comercio", category: nil, isSuggested: false) == nil)
    }

    @Test func aCategoryPutByHandStays() {
        let change = backfill(replacing: "Otros").change(merchant: "XYZ*1234 CDMX", category: "Regalos",
                                                         isSuggested: false)
        // Its name still follows the rule; its category is the owner's.
        #expect(change == .init(name: "Tacos Pepe", category: nil))
    }

    @Test func theCategoryTheRuleGaveBeforeIsReplaced() {
        let change = backfill(replacing: "Otros").change(merchant: "XYZ*1234 CDMX", category: "otros ",
                                                         isSuggested: false)
        #expect(change == .init(name: "Tacos Pepe", category: "Comida"))
    }

    @Test func aSuggestionNobodyConfirmedIsReplaced() {
        let change = backfill().change(merchant: "XYZ*1234 CDMX", category: "Despensa", isSuggested: true)
        #expect(change == .init(name: "Tacos Pepe", category: "Comida"))
    }

    @Test func whatAlreadyFollowsTheRuleDoesNotCount() {
        let same = MerchantBackfill(texts: ["XYZ*1234 CDMX", "Tacos Pepe"], name: "Tacos Pepe",
                                    category: "Comida", replacing: "Comida")
        #expect(same.change(merchant: "Tacos Pepe", category: "Comida", isSuggested: false) == nil)
    }

    @Test func aCategoryIsNeverTakenOffSavedExpenses() {
        let change = backfill(name: nil, category: nil, replacing: "Comida")
            .change(merchant: "XYZ*1234 CDMX", category: "Comida", isSuggested: false)
        #expect(change == nil)
    }

    @Test mutating func theListSplitsIntoNamedAndOnlyCategory() {
        learn("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        learn("Oxxo", as: "Oxxo", "Despensa")
        learn("CLIP*CAFE 02", as: "Café Río", "Café")
        learn("Farmacia", as: "Farmacia", "")
        let sections = MerchantRules.sections(MerchantRules.list(renames: renames, categories: categories))
        // Each group keeps the list's order: the newest first.
        #expect(sections.named.map(\.sent) == ["clip*cafe 02", "xyz*1234 cdmx"])
        #expect(sections.categoryOnly.map(\.sent) == ["farmacia", "oxxo"])
        #expect(!sections.isEmpty)
        #expect(MerchantRules.sections([]).isEmpty)
    }

    @Test(arguments: [("taq", ["clip*mx taq guero"]), ("GÜERO", ["clip*mx taq guero"]),
                      ("taqueria", ["clip*mx taq guero"]), ("  comida ", ["clip*mx taq guero", "fonda"]),
                      ("categoria", ["farmacia"]), ("nada de esto", []),
                      ("", ["clip*mx taq guero", "farmacia", "fonda"])])
    mutating func searchLooksAtTheTextTheNameAndTheCategory(query: String, found: [String]) {
        learn("CLIP*MX TAQ GUERO", as: "Taquería El Güero", "Comida")
        learn("Fonda", as: "Fonda", "Comida")
        learn("Farmacia", as: "Farmacia", "")
        let rules = MerchantRules.list(renames: renames, categories: categories)
        #expect(MerchantRules.matching(rules, query: query).map(\.sent).sorted() == found)
    }

    @Test mutating func theTextsOfAMerchantIncludeWhatIsRenamedToIt() {
        learn("OXXO 1234", as: "Oxxo", "Despensa")
        learn("OXXO 5678", as: "Oxxo", "Despensa", chose: false)
        #expect(Set(MerchantRules.texts(for: "Oxxo", renames: renames)) == ["oxxo", "oxxo 1234", "oxxo 5678"])
        #expect(MerchantRules.texts(for: "Sin comercio", renames: renames).isEmpty)
    }
}
