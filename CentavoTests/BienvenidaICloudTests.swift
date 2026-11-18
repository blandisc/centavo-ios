import Foundation
import XCTest
@testable import Centavo

/// A welcome closed halfway comes back on the next launch (2026-11-18): the currency this same
/// phone put in iCloud is not someone's setup on another iPhone.
final class BienvenidaICloudTests: XCTestCase {
    private func isSetUp(_ cloud: [String: String]) -> Bool {
        BudgetSync.isSetUp { cloud[$0] }
    }

    func testOnlyTheCurrencyIsNotASetup() {
        XCTAssertFalse(isSetUp([CurrencyPreference.key: "MXN"]), "Con solo la moneda, la bienvenida no volvía")
        XCTAssertFalse(isSetUp([:]))
    }

    func testTheWelcomeDoneOrABudgetIsASetup() {
        XCTAssertTrue(isSetUp(["onboarded": "1"]))
        XCTAssertTrue(isSetUp([CurrencyPreference.key: "USD", BudgetStore.key: "8000"]))
        XCTAssertTrue(isSetUp([FixedPlan.key: "[]x"]))
    }

    func testAnEmptyValueIsNothing() {
        XCTAssertFalse(isSetUp([BudgetStore.key: "", "onboarded": "0"]))
    }
}
