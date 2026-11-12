import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// «Lo que recuerdo», end to end against a throwaway in-memory store: a corrected payment
/// comes back with its name and category by every Wallet capture, and the expenses already
/// saved change only when asked, and never over what was set by hand (owner, 2026-11-11).
final class MerchantRulesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var renames = MerchantRenames()
    private var rules = CategoryRules()

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func saved() throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    @discardableResult
    private func arrives(_ merchant: String, after seconds: TimeInterval = 0, notice: String? = nil,
                         hidden: [String] = []) throws -> Expense {
        _ = try ExpenseRecorder.record(amountText: "$120.00", merchant: merchant, card: "BBVA", rawNotice: notice,
                                       in: context, primary: "MXN", rules: rules, hidden: hidden,
                                       renames: renames, cardRenames: MerchantRenames(),
                                       now: now.addingTimeInterval(seconds))
        return try XCTUnwrap(saved().last)
    }

    /// What the expense sheet teaches on «Guardar».
    private func correct(_ sent: String, as name: String, _ category: String?, chose: Bool = true) {
        MerchantRules.learn(sent: sent, name: name, category: category, choseCategory: chose,
                            renames: &renames, categories: &rules)
    }

    // MARK: The owner's case

    func testACorrectedPaymentArrivesWithItsNameAndCategoryFromThenOn() throws {
        correct("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        // No history at all: the rule alone decides, by either automation.
        let plain = try arrives("xyz*1234  cdmx", after: 3_600)
        XCTAssertEqual(plain.merchant, "Tacos Pepe")
        XCTAssertEqual(plain.shownName, "Tacos Pepe")
        XCTAssertEqual(plain.category, "Comida")
        XCTAssertFalse(plain.hasSuggestedCategory)
        let fromNotice = try arrives("XYZ*1234 CDMX", after: 7_200, notice: "BBVA\n$120.00\nXYZ*1234 CDMX")
        XCTAssertEqual(fromNotice.shownName, "Tacos Pepe")
        XCTAssertEqual(fromNotice.category, "Comida")
    }

    func testTheRuleDoesNotDependOnTheHistoryOfAYear() throws {
        correct("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        // The only expense from there is older than the memory looks back.
        context.insert(Expense(amount: 80, merchant: "Tacos Pepe",
                               date: now.addingTimeInterval(-86_400 * 500), category: "Comida"))
        try context.save()
        XCTAssertEqual(try arrives("XYZ*1234 CDMX").category, "Comida")
    }

    func testAnotherTerminalIsAnotherPlace() throws {
        correct("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        let other = try arrives("XYZ*5678 CDMX")
        XCTAssertEqual(other.merchant, "XYZ*5678 CDMX")
        XCTAssertNil(other.category)
    }

    func testOnlyTheCategoryCorrectedKeepsTheNameThatArrives() throws {
        correct("OXXO ROBLE 1234", as: "OXXO ROBLE 1234", "Antojos")
        let next = try arrives("OXXO ROBLE 1234")
        XCTAssertEqual(next.merchant, "OXXO ROBLE 1234")
        // Its own choice, not the catalog's «Despensa» for an Oxxo.
        XCTAssertEqual(next.category, "Antojos")
    }

    func testTheLastChoiceWinsAndAForgottenRuleStopsApplying() throws {
        correct("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        correct("Tacos Pepe", as: "Tacos Pepe", "Salidas")
        XCTAssertEqual(try arrives("XYZ*1234 CDMX").category, "Salidas")

        let rule = try XCTUnwrap(MerchantRules.list(renames: renames, categories: rules).first)
        MerchantRules.remove(rule, renames: &renames, categories: &rules)
        let after = try arrives("XYZ*1234 CDMX", after: 3_600)
        XCTAssertEqual(after.merchant, "XYZ*1234 CDMX")
        XCTAssertNil(after.category)
        // What was written down with the rule stays as it was.
        XCTAssertEqual(try saved().first?.merchant, "Tacos Pepe")
        XCTAssertEqual(try saved().first?.category, "Salidas")
    }

    func testAHiddenCategoryIsNotPutByTheRule() throws {
        correct("XYZ*1234 CDMX", as: "Tacos Pepe", "Comida")
        let next = try arrives("XYZ*1234 CDMX", hidden: ["comida"])
        XCTAssertEqual(next.merchant, "Tacos Pepe")
        XCTAssertNil(next.category)
    }

    // MARK: The expenses that were already there

    private func insert(_ merchant: String, _ category: String?, suggested: Bool = false,
                        fixed: Bool = false) -> Expense {
        let expense = Expense(amount: 50, currencyMarker: "MXN", merchant: merchant,
                              date: now.addingTimeInterval(-86_400), category: category, rawAmount: "$50.00")
        expense.displayName = MerchantName.readable(merchant)
        if suggested { expense.categorySource = Expense.suggestedCategory }
        if fixed { expense.repeatsMonthly = true }
        context.insert(expense)
        return expense
    }

    func testApplyingARuleChangesOnlyWhatWasNotSetByHand() throws {
        let plain = insert("XYZ*1234 CDMX", nil)
        let guessed = insert("xyz*1234 cdmx", "Despensa", suggested: true)
        let before = insert("XYZ*1234 CDMX", "Otros")
        let byHand = insert("XYZ*1234 CDMX", "Regalos")
        let elsewhere = insert("XYZ*5678 CDMX", nil)
        let renamedByHand = insert("Tacos de la oficina", nil)
        let rent = insert("XYZ*1234 CDMX", nil, fixed: true)
        try context.save()

        let backfill = MerchantBackfill(texts: ["XYZ*1234 CDMX"], name: "Tacos Pepe", category: "Comida",
                                        replacing: "Otros")
        let pending = backfill.pending(in: try saved())
        XCTAssertEqual(pending.count, 4)
        for item in pending { MerchantBackfill.apply(item.change, to: item.expense) }
        try context.save()

        for expense in [plain, guessed, before] {
            XCTAssertEqual(expense.merchant, "Tacos Pepe")
            XCTAssertEqual(expense.shownName, "Tacos Pepe")
            XCTAssertEqual(expense.category, "Comida")
            XCTAssertFalse(expense.hasSuggestedCategory)
            // The amount as Wallet sent it is still there.
            XCTAssertEqual(expense.rawAmount, "$50.00")
        }
        // Its category was the owner's: only the name follows.
        XCTAssertEqual(byHand.merchant, "Tacos Pepe")
        XCTAssertEqual(byHand.category, "Regalos")
        XCTAssertEqual(elsewhere.merchant, "XYZ*5678 CDMX")
        XCTAssertEqual(renamedByHand.merchant, "Tacos de la oficina")
        XCTAssertNil(renamedByHand.category)
        XCTAssertEqual(rent.merchant, "XYZ*1234 CDMX")
        // Done: nothing left to offer.
        XCTAssertTrue(backfill.pending(in: try saved()).isEmpty)
    }

    func testARolledBackSaveLeavesEveryExpenseAsItWas() throws {
        let one = insert("XYZ*1234 CDMX", nil)
        let two = insert("XYZ*1234 CDMX", "Otros")
        try context.save()
        let backfill = MerchantBackfill(texts: ["XYZ*1234 CDMX"], name: "Tacos Pepe", category: "Comida",
                                        replacing: "Otros")
        for item in backfill.pending(in: [one, two]) { MerchantBackfill.apply(item.change, to: item.expense) }
        // What the sheets do when the save fails.
        context.rollback()
        XCTAssertEqual(one.merchant, "XYZ*1234 CDMX")
        XCTAssertNil(one.category)
        XCTAssertEqual(two.merchant, "XYZ*1234 CDMX")
        XCTAssertEqual(two.category, "Otros")
    }

    // MARK: The words on the screen

    func testEachRuleSaysWhatItDoes() {
        XCTAssertEqual(MerchantRule(sent: "xyz*1234 cdmx", name: "Tacos Pepe", category: "Comida").summary,
                       "Se anota como Tacos Pepe · Comida")
        XCTAssertEqual(MerchantRule(sent: "xyz*1234 cdmx", name: "Tacos Pepe").summary, "Se anota como Tacos Pepe")
        XCTAssertEqual(MerchantRule(sent: "xyz*1234 cdmx", name: "Tacos Pepe", goesUncategorized: true).summary,
                       "Se anota como Tacos Pepe · sin categoría")
        XCTAssertEqual(MerchantRule(sent: "oxxo roble", category: "Antojos").summary, "Va a Antojos")
        XCTAssertEqual(MerchantRule(sent: "uber *trip", goesUncategorized: true).summary, "Se queda sin categoría")
        XCTAssertEqual(MerchantRule(sent: "xyz*1234 cdmx").arrivesAs, "XYZ*1234 CDMX")
    }

    func testTheOfferCountsTheOtherExpenses() {
        XCTAssertEqual(MerchantBackfill.offer(1), "Cambiar también el otro gasto")
        XCTAssertEqual(MerchantBackfill.offer(6), "Cambiar también los otros 6 gastos")
    }
}
