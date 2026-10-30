import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// What the payment notice and Siri say about the month, against an in-memory store.
final class MonthStatusTests: XCTestCase {
    private var context: ModelContext!
    /// Mid-month, so last month and next month are easy to reach.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15,
                                                                 hour: 12))!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func add(_ amount: Decimal, _ marker: String = "$", daysAgo: Int = 0) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        context.insert(Expense(amount: amount, currencyMarker: marker, merchant: "Oxxo", date: date))
    }

    private func budgetLine(_ budget: Decimal?) throws -> String? {
        try MonthStatus.budgetSentence(in: context, budget: budget, now: now, primary: "USD")
    }

    private func total(_ budget: Decimal?) throws -> String {
        try MonthStatus.totalSentence(in: context, budget: budget, now: now, primary: "USD")
    }

    func testWithoutABudgetThereIsNothingToSay() throws {
        add(100)
        XCTAssertNil(try budgetLine(nil))
        XCTAssertNil(try budgetLine(0))
    }

    func testSaysWhatIsLeft() throws {
        add(100)
        add(50)
        let line = try XCTUnwrap(budgetLine(500))
        XCTAssertTrue(line.hasPrefix("Te quedan"), line)
        XCTAssertTrue(line.contains("350.00"), line)
        XCTAssertTrue(line.contains("Hoy puedes gastar"), "No dice cuánto hoy: \(line)")
    }

    /// Every day so far gives its share and what was spent comes off it whole, today's too
    /// (owner's decision, 2026-10-22).
    func testCarriesEveryDayOverWhole() throws {
        add(100, daysAgo: 1)
        // October 15th: 1,800 × 15 / 31 = 870.97, minus the 100 of yesterday and the 30 of today.
        add(30)
        let line = try XCTUnwrap(budgetLine(1800))
        XCTAssertTrue(line.contains("1,670.00 del presupuesto"), line)
        XCTAssertTrue(line.hasSuffix("Hoy puedes gastar $740."), line)
    }

    /// «¿Cuánto puedo gastar hoy?»: only the day's figure, the same as the budget line's end.
    func testTodayIsJustTheDaysFigure() throws {
        add(100, daysAgo: 1)
        add(30)
        let today = try MonthStatus.todaySentence(in: context, budget: 1800, now: now, primary: "USD")
        XCTAssertEqual(today, "Hoy puedes gastar $740.")
        XCTAssertTrue(try MonthStatus.todaySentence(in: context, budget: nil, now: now, primary: "USD")
            .hasPrefix("Aún no tienes presupuesto"))
        add(2_000)
        XCTAssertTrue(try MonthStatus.todaySentence(in: context, budget: 1800, now: now, primary: "USD")
            .hasPrefix("Te pasaste del presupuesto por"))
    }

    /// Past today's share, Siri says by how much instead of a negative figure.
    func testSaysWhenTodayWentPastItsShare() throws {
        // 310 a month is 10 a day: 150 by the 15th, and today spent 200.
        add(200)
        let line = try XCTUnwrap(budgetLine(310))
        XCTAssertTrue(line.hasSuffix("Hoy ya te pasaste por $50."), line)
    }

    /// «Te quedan» says what is free once the fixed ones still to come are set apart, and
    /// names those, so it squares with «Hoy puedes gastar» (audit 2026-10-22, #4).
    func testSaysWhatIsFreeAndWhatIsSetApartForFixedOnes() throws {
        let rent = Expense(amount: 600, currencyMarker: "$", merchant: "Renta",
                           date: Calendar.current.date(byAdding: .day, value: -20, to: now)!)
        rent.repeatsMonthly = true  // Next charge: October 25th, still to come.
        context.insert(rent)
        add(100, daysAgo: 1)
        let line = try XCTUnwrap(budgetLine(2300))
        XCTAssertTrue(line.contains("1,600.00 libres"), line)
        XCTAssertTrue(line.contains("600.00 apartados para fijos"), line)
        // (2,300 − 600) × 15 / 31 = 822.58, minus the 100 of yesterday.
        XCTAssertTrue(line.hasSuffix("722."), line)
    }

    func testSaysByHowMuchTheBudgetWasBlown() throws {
        add(730)
        let line = try XCTUnwrap(budgetLine(500))
        XCTAssertTrue(line.hasPrefix("Te pasaste"), line)
        XCTAssertTrue(line.contains("230.00"), line)
    }

    func testOnlyThisMonthCounts() throws {
        add(100)
        add(400, daysAgo: 31)  // September
        let line = try XCTUnwrap(budgetLine(500))
        XCTAssertTrue(line.contains("400.00"), "Contó otro mes: \(line)")
    }

    func testRefundsGiveMoneyBack() throws {
        add(300)
        add(-100)
        XCTAssertTrue(try XCTUnwrap(budgetLine(500)).contains("300.00"))
    }

    func testTheTotalKeepsOtherCurrenciesApart() throws {
        add(100)
        add(20, "EUR")
        let sentence = try total(500)
        XCTAssertTrue(sentence.hasPrefix("Llevas"), sentence)
        XCTAssertTrue(sentence.contains("100.00"), sentence)
        XCTAssertTrue(sentence.contains("EUR 20.00 en otra moneda"), sentence)
        XCTAssertTrue(sentence.contains("Te quedan"), sentence)
        XCTAssertTrue(sentence.contains("400.00"), "El euro se sumó al presupuesto: \(sentence)")
    }

    func testAnEmptyMonthStillAnswers() throws {
        let sentence = try total(nil)
        XCTAssertTrue(sentence.hasPrefix("Llevas"), sentence)
        XCTAssertTrue(sentence.contains("0.00"), sentence)
        XCTAssertFalse(sentence.contains("presupuesto"), sentence)
    }

    // MARK: «No cuenta»

    @discardableResult
    private func addUncounted(_ amount: Decimal, category: String? = nil) -> Expense {
        let expense = Expense(amount: amount, currencyMarker: "$", merchant: "Uber", date: now, category: category)
        expense.markUncounted(.reimbursed)
        context.insert(expense)
        return expense
    }

    /// What the main screen adds up, built the way it builds it (`ExpenseListView`).
    private func screenSummary() throws -> MonthSummary {
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        return MonthSummarizer.summarize(expenses.map(\.asAmount), inMonthOf: now, primary: "USD")
    }

    func testSiriLeavesOutWhatDoesNotCount() throws {
        add(300)
        addUncounted(230)
        let line = try XCTUnwrap(budgetLine(1000))
        XCTAssertTrue(line.contains("700.00"), "Contó lo que no cuenta: \(line)")
        let sentence = try total(nil)
        XCTAssertTrue(sentence.contains("300.00"), sentence)
    }

    func testTheScreenAndSiriSayTheSame() throws {
        add(300)
        add(-50)
        add(20, "EUR")
        addUncounted(230, category: "Transporte")
        addUncounted(-80)
        let screen = try screenSummary()
        XCTAssertEqual(screen.primary.amount, 250)
        XCTAssertEqual(screen.outside, 150)
        let spoken = formatMoney(screen.primary.amount, isoCode: "USD", label: "USD")
        let sentence = try total(nil)
        XCTAssertTrue(sentence.contains("Llevas \(spoken)"), sentence)
        let left = formatMoney(1000 - screen.primary.amount, isoCode: "USD", label: "USD")
        let line = try XCTUnwrap(budgetLine(1000))
        XCTAssertTrue(line.contains(left), line)
    }

    func testACategoryOfOnlyWhatDoesNotCountHasNothing() throws {
        addUncounted(230, category: "Transporte")
        XCTAssertEqual(try MonthStatus.categorySentence("Transporte", in: context, now: now, primary: "USD"),
                       "Este mes no llevas nada en Transporte.")
    }

    func testCountingAgainAddsItBack() throws {
        add(300)
        let trip = addUncounted(230)
        trip.markCounted()
        XCTAssertTrue(try XCTUnwrap(budgetLine(1000)).contains("470.00"))
    }

    func testSaysWhatACategoryAddsUpTo() throws {
        context.insert(Expense(amount: 65, currencyMarker: "$", merchant: "Starbucks", date: now, category: "Café"))
        context.insert(Expense(amount: 45, currencyMarker: "$", merchant: "La Ceiba", date: now, category: "cafe"))
        context.insert(Expense(amount: 300, currencyMarker: "$", merchant: "Oxxo", date: now, category: "Despensa"))
        let line = try MonthStatus.categorySentence("café", in: context, now: now, primary: "USD")
        XCTAssertTrue(line.hasPrefix("Llevas"), line)
        XCTAssertTrue(line.contains("110.00"), line)
        XCTAssertEqual(try MonthStatus.categorySentence("Ropa", in: context, now: now, primary: "USD"),
                       "Este mes no llevas nada en Ropa.")
    }
}
