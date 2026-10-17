import SwiftData
import XCTest
@testable import Centavo

/// Fixed expenses logging themselves, against an in-memory store.
final class RecurringExpensesTests: XCTestCase {
    private var context: ModelContext!
    private let calendar = Calendar.current

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func at(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9))!
    }

    private func all() throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    private func addNetflix() -> Expense {
        let netflix = Expense(amount: 219, currencyMarker: "MXN", merchant: "Netflix",
                              date: at(8, 24), category: "Suscripciones")
        netflix.repeatsMonthly = true
        netflix.repeatsThrough = netflix.date
        context.insert(netflix)
        return netflix
    }

    func testLogsEachMonthThatCameWithEverythingCopied() throws {
        _ = addNetflix()
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(10, 30)), 2)
        let copies = try all().filter { $0.isRepeat == true }
        XCTAssertEqual(copies.map(\.date), [at(9, 24), at(10, 24)])
        XCTAssertEqual(copies.first?.amount, 219)
        XCTAssertEqual(copies.first?.category, "Suscripciones")
        XCTAssertEqual(copies.first?.currencyMarker, "MXN")
        XCTAssertNil(copies.first?.repeatsMonthly, "Una copia no debe generar más copias")
    }

    func testRunningAgainLogsNothingNew() throws {
        _ = addNetflix()
        try RecurringExpenses.logDue(in: context, now: at(10, 30))
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(10, 30)), 0)
        XCTAssertEqual(try all().count, 3)
    }

    func testADeletedCopyStaysDeleted() throws {
        _ = addNetflix()
        try RecurringExpenses.logDue(in: context, now: at(10, 30))
        let october = try XCTUnwrap(all().last)
        context.delete(october)
        try context.save()
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(10, 31)), 0)
        XCTAssertEqual(try all().count, 2)
    }

    func testStoppingItStopsTheCopies() throws {
        let netflix = addNetflix()
        netflix.repeatsMonthly = nil
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(12, 31)), 0)
    }
}
