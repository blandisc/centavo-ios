import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// The search asks the store first (`HomeModel.searchCandidates`): it must never leave out
/// what the full search would find, with accents and capitals ignored.
@MainActor
final class SearchCandidatesTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try ModelContainer(for: Expense.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = ModelContext(container)
        let cafe = Expense(amount: 62, currencyMarker: "MXN", merchant: "STARBUCKS 123", card: "Nu", category: "Café")
        cafe.displayName = "Starbucks"
        context.insert(cafe)
        context.insert(Expense(amount: 89, currencyMarker: "MXN", merchant: "Oxxo", card: "BBVA Azul", category: "Despensa"))
        context.insert(Expense(amount: 300, currencyMarker: "MXN", merchant: "Uber", date: .now.addingTimeInterval(-40 * 86_400)))
        try context.save()
    }

    private func names(_ query: SearchQuery) throws -> Set<String> {
        Set(try context.fetch(HomeModel.searchCandidates(for: query)).map(\.merchant))
    }

    func testAWordMatchesMerchantNameCategoryAndCardIgnoringAccents() throws {
        XCTAssertEqual(try names(SearchQuery(words: ["starbucks"])), ["STARBUCKS 123"])
        XCTAssertEqual(try names(SearchQuery(words: ["cafe"])), ["STARBUCKS 123"])
        XCTAssertEqual(try names(SearchQuery(words: ["azul"])), ["Oxxo"])
    }

    func testAMonthBringsItsDaysAndNamesWithIt() throws {
        let interval = DateInterval(start: .now.addingTimeInterval(-86_400), end: .now.addingTimeInterval(86_400))
        var query = SearchQuery(interval: interval)
        query.monthWord = "despensa"
        let found = try names(query)
        XCTAssertTrue(found.isSuperset(of: ["STARBUCKS 123", "Oxxo"]))
        XCTAssertFalse(found.contains("Uber"))
    }
}
