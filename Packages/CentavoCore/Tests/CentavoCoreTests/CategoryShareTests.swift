import Foundation
import Testing
@testable import CentavoCore

@Suite struct CategoryShareTests {
    @Test func everyCategoryAsAShareWhileTheyFit() {
        let shares = CategoryShare.top([
            CategoryTotal(category: "Despensa", amount: 500),
            CategoryTotal(category: "Ropa", amount: 300),
            CategoryTotal(category: nil, amount: 100),
            CategoryTotal(category: "Café", amount: 100),
        ])
        #expect(shares.map(\.category) == ["Despensa", "Ropa", nil, "Café"])
        #expect(shares.map(\.share) == [0.5, 0.3, 0.1, 0.1])
        #expect(shares.map(\.amount) == [500, 300, 100, 100])
        let gathered = shares.contains { $0.isRest }
        #expect(!gathered)
    }

    /// The list grows with the categories, up to the limit; past it, the smallest go together.
    @Test func pastTheLimitTheSmallestAreGathered() throws {
        let totals = (1...8).map { CategoryTotal(category: "C\($0)", amount: Decimal(100 - $0)) }
        let shares = CategoryShare.top(totals, limit: 6)
        #expect(shares.count == 6)
        #expect(shares.prefix(5).map(\.category) == ["C1", "C2", "C3", "C4", "C5"])
        let rest = try #require(shares.last)
        #expect(rest.isRest && rest.restCount == 3 && rest.category == nil)
        #expect(rest.contains("c7") && !rest.contains("C1"))
        #expect(shares[0].contains("c1") && !shares[0].contains("C2"))
        #expect(rest.amount == Decimal(94 + 93 + 92))
        #expect(abs(shares.map(\.share).reduce(0, +) - 1) < 0.000_001)
    }

    @Test func exactlyTheLimitNeedsNoRest() {
        let totals = (1...6).map { CategoryTotal(category: "C\($0)", amount: 10) }
        let gathered = CategoryShare.top(totals, limit: 6).contains { $0.isRest }
        #expect(!gathered)
    }

    @Test func fourColorsThenOtras() {
        let totals = (1...6).map { CategoryTotal(category: "C\($0)", amount: Decimal(100 - $0)) }
        let shares = CategoryShare.top(totals)
        #expect(shares.count == CategoryShare.colored + 1)
        #expect(shares.last?.restCount == 2)
    }

    @Test func refundsDoNotBreakTheShares() {
        let shares = CategoryShare.top([
            CategoryTotal(category: "Despensa", amount: 300),
            CategoryTotal(category: "Ropa", amount: -230),
        ])
        #expect(shares == [CategoryShare(category: "Despensa", share: 1, amount: 300)])
    }

    @Test func nothingFiledSaysNothing() {
        #expect(CategoryShare.top([CategoryTotal(category: nil, amount: 400)]).isEmpty)
        #expect(CategoryShare.top([]).isEmpty)
    }
}
