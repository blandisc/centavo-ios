import CentavoCore
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

    /// Another phone on the same iCloud already logged October before this one heard of it.
    func testACopyFromAnotherDeviceIsNotRepeated() throws {
        _ = addNetflix()
        let fromOtherPhone = Expense(amount: 219, currencyMarker: "MXN", merchant: "Netflix", date: at(10, 24))
        fromOtherPhone.isRepeat = true
        context.insert(fromOtherPhone)
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(10, 30)), 1, "Solo septiembre")
        XCTAssertEqual(try all().filter { $0.isRepeat == true }.count, 2)
    }

    /// Asked for the 31st, started on the 30th: October still lands on the 31st.
    func testTheDayAskedForIsKept() throws {
        let rent = Expense(amount: 9500, currencyMarker: "MXN", merchant: "Renta", date: at(9, 30))
        rent.repeatsMonthly = true
        rent.repeatsThrough = rent.date
        rent.repeatDay = 31
        context.insert(rent)
        try RecurringExpenses.logDue(in: context, now: at(10, 31).addingTimeInterval(3600))
        XCTAssertEqual(try all().last?.date, at(10, 31))
    }

    // MARK: Other rules

    private func addCleaning(rule: RepeatRule = .weeks(1)) -> Expense {
        // Monday 5 October 2026.
        let cleaning = Expense(amount: 500, currencyMarker: "MXN", merchant: "Limpieza", date: at(10, 5))
        cleaning.repeatsMonthly = true
        cleaning.repeatsThrough = cleaning.date
        cleaning.repeatRule = rule.stored
        context.insert(cleaning)
        return cleaning
    }

    func testAWeeklyOneLogsEveryMondayThatCame() throws {
        _ = addCleaning()
        // Monday the 19th at 8:00: the 9:00 one has not come yet.
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8))!
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: now), 1)
        XCTAssertEqual(try all().filter { $0.isRepeat == true }.map(\.date), [at(10, 12)])
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(10, 19)), 1, "Llegó el de las 9:00")
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(10, 19)), 0)
    }

    func testTwoWeeklyChargesInOneMonthAreTwoCopies() throws {
        _ = addCleaning()
        try RecurringExpenses.logDue(in: context, now: at(10, 31))
        XCTAssertEqual(try all().filter { $0.isRepeat == true }.count, 3, "12, 19 y 26 de octubre")
    }

    func testWhatIsComingThisMonthIsSetApart() throws {
        let cleaning = addCleaning()
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!
        try RecurringExpenses.logDue(in: context, now: now)
        let reserved = FixedOutlook.reserved(originals: [cleaning], plans: [], primary: "MXN", now: now)
        XCTAssertEqual(reserved, 500, "Solo falta el lunes 26")
    }

    func testAFixedExpenseThatStartsLaterLogsNothingUntilItsDay() throws {
        let plan = FixedPlan(merchant: "Gimnasio", amount: "650", currency: "MXN", rule: RepeatRule.monthly.stored,
                             firstDate: at(11, 3))
        UserDefaults.standard.set(FixedPlan.encode([plan]), forKey: FixedPlan.key)
        defer { UserDefaults.standard.removeObject(forKey: FixedPlan.key) }
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(10, 30)), 0)
        XCTAssertTrue(try all().isEmpty, "Nada con fecha futura")
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(11, 3)), 1)
        let original = try XCTUnwrap(all().first)
        XCTAssertEqual(original.repeatsMonthly, true)
        XCTAssertEqual(original.date, at(11, 3))
        XCTAssertTrue(FixedPlan.saved.isEmpty, "El plan ya empezó")
    }
}
