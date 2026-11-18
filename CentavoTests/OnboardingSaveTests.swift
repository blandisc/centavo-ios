import Foundation
import XCTest
@testable import Centavo

/// The welcome's save, started over after the app closed before «Ver mi día» (2026-11-18): the
/// same fixed expense is never stored twice, or it would be charged twice a month.
@MainActor
final class OnboardingSaveTests: XCTestCase {
    private func plan(_ merchant: String, _ amount: String, day: Int) -> FixedPlan {
        FixedPlan(merchant: merchant, amount: amount, currency: "MXN", category: nil, rule: nil,
                  firstDate: Date(timeIntervalSince1970: 0), day: day)
    }

    func testAPlanAlreadySavedIsNotSavedAgain() {
        let saved = [plan("Renta", "9000", day: 28)]
        let again = [plan("Renta", "9000.00", day: 28), plan("Luz", "450", day: 20)]
        let fresh = OnboardingView.notSaved(again, in: saved)
        XCTAssertEqual(fresh.map(\.merchant), ["Luz"], "La renta quedó dos veces")
    }

    func testAnotherDayOrAmountIsAnotherFixedExpense() {
        let saved = [plan("Renta", "9000", day: 28)]
        let others = [plan("Renta", "9000", day: 1), plan("Renta", "9500", day: 28)]
        XCTAssertEqual(OnboardingView.notSaved(others, in: saved).count, 2)
        XCTAssertEqual(OnboardingView.notSaved(others, in: []).count, 2, "Sin nada guardado se guarda todo")
    }
}
