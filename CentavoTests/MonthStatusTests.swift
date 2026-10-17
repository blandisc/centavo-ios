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
        XCTAssertTrue(sentence.contains("EUR 20.00 aparte"), sentence)
        XCTAssertTrue(sentence.contains("Te quedan"), sentence)
        XCTAssertTrue(sentence.contains("400.00"), "El euro se sumó al presupuesto: \(sentence)")
    }

    func testAnEmptyMonthStillAnswers() throws {
        let sentence = try total(nil)
        XCTAssertTrue(sentence.hasPrefix("Llevas"), sentence)
        XCTAssertTrue(sentence.contains("0.00"), sentence)
        XCTAssertFalse(sentence.contains("presupuesto"), sentence)
    }
}
