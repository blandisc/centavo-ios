import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// «Se repite» as the expense sheet saves it on a fixed expense (2026-11-18).
@MainActor
final class EditorRepeatsTests: XCTestCase {
    private var context: ModelContext!
    private let calendar = Calendar.current

    override func setUp() async throws {
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func at(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9))!
    }

    /// Rent «día 31» started in November: its first charge is on the 30th, the day asked is 31.
    private func addRent() throws -> Expense {
        let rent = Expense(amount: 8_000, currencyMarker: "MXN", merchant: "Renta", date: at(11, 30))
        rent.repeatsMonthly = true
        rent.fixedID = UUID().uuidString
        rent.repeatsThrough = rent.date
        rent.repeatDay = 31
        context.insert(rent)
        try context.save()
        return rent
    }

    func testSavingWithTheSameDateKeepsTheDayAsked() throws {
        let rent = try addRent()
        ExpenseEditorView.setRepeats(rent, repeats: true, rule: .monthly, date: rent.date, dateUnchanged: true)
        XCTAssertEqual(rent.repeatDay, 31, "Cambiar solo el monto no debe mover la renta al día 30")
        XCTAssertEqual(rent.repeatsMonthly, true)
    }

    func testMovingTheDateTakesTheNewDay() throws {
        let rent = try addRent()
        ExpenseEditorView.setRepeats(rent, repeats: true, rule: .monthly, date: at(11, 15), dateUnchanged: false)
        XCTAssertEqual(rent.repeatDay, 15)
    }

    func testTurningItOffOnARunningOneKeepsItFixed() throws {
        let rent = try addRent()
        let id = rent.fixedID
        ExpenseEditorView.setRepeats(rent, repeats: false, rule: .monthly, date: rent.date, dateUnchanged: true)
        XCTAssertTrue(rent.isFixed, "Apagar «Se repite» no debe volverlo un gasto del día")
        XCTAssertNil(rent.repeatsMonthly, "Ya no se repite")
        XCTAssertEqual(rent.isRepeat, true)
        XCTAssertEqual(rent.fixedOf, id)
        XCTAssertNil(rent.repeatDay)
    }

    func testTurningItOffOnAPlainOneLeavesItPlain() throws {
        let coffee = Expense(amount: 45, currencyMarker: "MXN", merchant: "Café", date: at(11, 10))
        context.insert(coffee)
        ExpenseEditorView.setRepeats(coffee, repeats: false, rule: .monthly, date: coffee.date)
        XCTAssertFalse(coffee.isFixed)
        XCTAssertNil(coffee.isRepeat)
    }
}
