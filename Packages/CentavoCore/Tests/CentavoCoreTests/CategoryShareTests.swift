import Foundation
import Testing
@testable import CentavoCore

@Suite struct CategoryShareTests {
    @Test func theBiggestThreeAsShares() {
        let shares = CategoryShare.top([
            CategoryTotal(category: "Despensa", amount: 500),
            CategoryTotal(category: "Ropa", amount: 300),
            CategoryTotal(category: nil, amount: 100),
            CategoryTotal(category: "Café", amount: 100),
        ])
        #expect(shares.map(\.category) == ["Despensa", "Ropa", nil])
        #expect(shares.map(\.share) == [0.5, 0.3, 0.1])
    }

    @Test func refundsDoNotBreakTheShares() {
        let shares = CategoryShare.top([
            CategoryTotal(category: "Despensa", amount: 300),
            CategoryTotal(category: "Ropa", amount: -230),
        ])
        #expect(shares == [CategoryShare(category: "Despensa", share: 1)])
    }

    @Test func nothingFiledSaysNothing() {
        #expect(CategoryShare.top([CategoryTotal(category: nil, amount: 400)]).isEmpty)
        #expect(CategoryShare.top([]).isEmpty)
    }
}
