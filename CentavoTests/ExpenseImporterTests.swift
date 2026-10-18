import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

final class ExpenseImporterTests: XCTestCase {
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

    func testAnExportComesBackWhole() throws {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let csv = CSVExporter.csv(from: [
            ExpenseRecord(date: date, merchant: "Boru Oum", amount: 175, currency: "MXN",
                          card: "American Express México", category: "Comida"),
        ])
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context),
                       .init(added: 1, alreadyThere: 0, unreadable: 0))
        let expense = try XCTUnwrap(all().first)
        XCTAssertEqual(expense.merchant, "Boru Oum")
        XCTAssertEqual(expense.amount, 175)
        XCTAssertEqual(expense.currencyMarker, "MXN")
        XCTAssertEqual(expense.card, "American Express México")
        XCTAssertEqual(expense.category, "Comida")
        XCTAssertEqual(expense.date, date)
    }

    func testImportingTwiceDoesNotDuplicate() throws {
        let csv = CSVExporter.csv(from: [
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_000_000), merchant: "Oxxo",
                          amount: 89, currency: "MXN"),
        ])
        _ = try ExpenseImporter.importCSV(csv, into: context)
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context),
                       .init(added: 0, alreadyThere: 1, unreadable: 0))
        XCTAssertEqual(try all().count, 1)
    }
}
