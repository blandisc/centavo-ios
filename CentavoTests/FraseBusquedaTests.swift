import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// A search of only a year or only bounds («2026», «más de 500») asks the store for part of
/// the history, not all of it (2026-11-18), and still never leaves out what the full search
/// keeps: refunds by their size, and «2026» as an amount.
@MainActor
final class FraseBusquedaTests: XCTestCase {
    private var context: ModelContext!
    private let calendar = Calendar.current

    private func date(_ day: Int, _ month: Int, _ year: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Expense.self, configurations: configuration)
        context = ModelContext(container)
        let rows: [(Decimal, String, Date)] = [
            (89, "Oxxo", date(3, 3, 2026)),
            (89, "Farmacia", date(3, 3, 2025)),
            (2026, "Liverpool", date(3, 3, 2025)),
            (12026, "Palacio", date(3, 3, 2024)),
            (300, "Rifa 2026", date(3, 3, 2024)),
            (600, "Uber", date(3, 3, 2024)),
            (-600, "Devolución", date(3, 3, 2024)),
            (500, "Justo", date(3, 3, 2024)),
            (-40, "Reembolso chico", date(3, 3, 2024)),
        ]
        for (amount, merchant, day) in rows {
            context.insert(Expense(amount: amount, currencyMarker: "MXN", merchant: merchant, date: day))
        }
        try context.save()
    }

    /// What the store hands over, and what the full search keeps of every expense.
    private func compare(_ text: String) throws -> (asked: Set<String>, kept: Set<String>) {
        let query = ExpenseSearch.query(from: text, now: date(18, 11, 2026), calendar: calendar)
        let asked = try context.fetch(HomeModel.searchCandidates(for: query))
        let all = try context.fetch(FetchDescriptor<Expense>())
        let kept = all.filter { ExpenseSearch.matches($0.searchable, query) }
        return (Set(asked.map(\.merchant)), Set(kept.map(\.merchant)))
    }

    func testAYearAloneAsksForItsDaysItsNameAndItsAmount() throws {
        let found = try compare("2026")
        XCTAssertTrue(found.asked.isSuperset(of: found.kept))
        XCTAssertEqual(found.kept, ["Oxxo", "Liverpool", "Palacio", "Rifa 2026"])
        XCTAssertFalse(found.asked.contains("Farmacia"))
        XCTAssertFalse(found.asked.contains("Uber"))
    }

    func testBoundsAloneAskForThoseAmountsRefundsIncluded() throws {
        for text in ["más de 500", "desde 500", "menos de 500", "hasta 500", "more than 500", "under 500"] {
            let found = try compare(text)
            XCTAssertTrue(found.asked.isSuperset(of: found.kept), text)
            XCTAssertLessThan(found.asked.count, 9, text)
        }
        let over = try compare("más de 500")
        XCTAssertTrue(over.kept.isSuperset(of: ["Uber", "Devolución"]))
        XCTAssertFalse(over.asked.contains("Oxxo"))
        let under = try compare("menos de 500")
        XCTAssertTrue(under.kept.isSuperset(of: ["Oxxo", "Reembolso chico"]))
        XCTAssertFalse(under.asked.contains("Uber"))
    }
}
