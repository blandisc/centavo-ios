import XCTest
@testable import Centavo

/// The currency the welcome saves (2026-11-18): a currency iCloud brought while the welcome was
/// open is kept unless a tile was tapped there, or pesos would go up and change the other phone.
@MainActor
final class BienvenidaTests: XCTestCase {
    func testACurrencyBroughtByICloudIsNotOverwritten() {
        // Adopted «USD» during the welcome, no tile tapped: the save leaves it alone.
        XCTAssertNil(OnboardingView.currencyToSave("USD", picked: false, stored: "USD"))
        XCTAssertNil(OnboardingView.currencyToSave("MXN", picked: false, stored: "USD"),
                     "Los pesos de la bienvenida pisaron los dólares de iCloud")
    }

    func testAChosenCurrencyIsSaved() {
        XCTAssertEqual(OnboardingView.currencyToSave("EUR", picked: true, stored: "USD"), "EUR")
    }

    func testWithNothingSavedTheShownOneIsSaved() {
        XCTAssertEqual(OnboardingView.currencyToSave("MXN", picked: false, stored: ""), "MXN")
        XCTAssertEqual(OnboardingView.currencyToSave("MXN", picked: false, stored: "XYZ"), "MXN")
    }
}
