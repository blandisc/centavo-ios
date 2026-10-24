import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// «No cuenta» on the stored expense: what old expenses do, and the switch going back and forth.
final class UncountedExpenseTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func all() throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    func testAnExpenseFromBeforeCountsInFull() throws {
        // Saved without either field, as every expense from before this existed.
        context.insert(Expense(amount: 230, currencyMarker: "$", merchant: "Uber"))
        context.insert(Expense(amount: -50, currencyMarker: "$", merchant: "Liverpool"))
        try context.save()
        let expenses = try all()
        for expense in expenses {
            XCTAssertNil(expense.countedAmount)
            XCTAssertNil(expense.uncountedReason)
            XCTAssertFalse(expense.isUncounted)
            XCTAssertEqual(expense.counted, expense.amount)
            XCTAssertEqual(expense.asAmount.value, expense.amount)
            XCTAssertEqual(expense.asAmount.excluded, 0)
        }
    }

    func testTheSwitchGoesBackAndForthKeepingTheReason() throws {
        let trip = Expense(amount: 230, currencyMarker: "$", merchant: "SPEI Nu")
        context.insert(trip)
        trip.markUncounted(.betweenAccounts)
        try context.save()
        XCTAssertTrue(trip.isUncounted)
        XCTAssertEqual(trip.counted, 0)
        XCTAssertEqual(trip.amount, 230, "Perdió su monto real")
        XCTAssertEqual(trip.asAmount.excluded, 230)

        trip.markCounted()
        try context.save()
        XCTAssertFalse(trip.isUncounted)
        XCTAssertEqual(trip.counted, 230, "No volvió a contar")
        XCTAssertEqual(trip.asAmount.excluded, 0)
        XCTAssertEqual(trip.reason, .betweenAccounts, "Se perdió el motivo")

        // As the menu does it: the reason it had, or «Me lo reembolsan» the first time.
        trip.markUncounted(trip.reason ?? .reimbursed)
        XCTAssertEqual(trip.reason, .betweenAccounts)
        let fresh = Expense(amount: 89, merchant: "Oxxo")
        fresh.markUncounted(fresh.reason ?? .reimbursed)
        XCTAssertEqual(fresh.reason, .reimbursed)
    }

    func testAReasonNobodyKnowsIsNoReason() {
        let expense = Expense(amount: 89, merchant: "Oxxo")
        expense.countedAmount = 0
        expense.uncountedReason = "algo-nuevo"
        XCTAssertTrue(expense.isUncounted)
        XCTAssertNil(expense.reason)
    }

    func testTheCSVKeepsTheRealAmountAndBringsTheMarkBack() throws {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let trip = Expense(amount: 230, currencyMarker: "MXN", merchant: "Uber", date: date, category: "Transporte")
        trip.markUncounted(.reimbursed)
        let file = ExpensesCSVFile(expenses: [trip, Expense(amount: 89, currencyMarker: "MXN", merchant: "Oxxo",
                                                            date: date.addingTimeInterval(60))],
                                   primaryCurrency: "MXN")
        XCTAssertTrue(file.text.contains(",230.00,MXN,,Transporte,No,Me lo reembolsan"), file.text)

        XCTAssertEqual(try ExpenseImporter.importCSV(file.text, into: context).added, 2)
        let back = try all()
        XCTAssertEqual(back.map(\.isUncounted), [true, false])
        XCTAssertEqual(back.first?.reason, .reimbursed)
        XCTAssertEqual(back.first?.amount, 230)
    }

    func testAnOldCSVCountsEverything() throws {
        let csv = "Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría\r\n"
            + "2026-10-17T15:52:11-06:00,Uber,230.00,MXN,,Transporte\r\n"
        _ = try ExpenseImporter.importCSV(csv, into: context)
        let expense = try XCTUnwrap(all().first)
        XCTAssertFalse(expense.isUncounted)
        XCTAssertNil(expense.countedAmount)
    }

    func testTheMonthsNoteStillSeesADoubleChargeThatDoesNotCount() {
        let now = Date.now
        let first = Expense(amount: 650, currencyMarker: "MXN", merchant: "Uber", date: now.addingTimeInterval(-1_200))
        let second = Expense(amount: 650, currencyMarker: "MXN", merchant: "Uber", date: now.addingTimeInterval(-600))
        first.markUncounted(.reimbursed)
        second.markUncounted(.reimbursed)
        let facts = MonthNote.facts([second, first], now: now, primary: "MXN", budget: nil)
        XCTAssertTrue(facts.contains { $0.kind == .doubleCharge }, "Dejó de avisar del cobro doble")
    }
}
