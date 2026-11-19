import CentavoCore
import XCTest
@testable import Centavo

/// Round 3 of the personas (2026-11-19): a Wallet payment takes one name-only notice at most,
/// so a second purchase at the same shop whose amount didn't arrive stays pending; and money
/// said in English goes by its name, with the figure written the app's way.
final class VozFraseTests: XCTestCase {
    private let suite = "VozFraseTests"
    private var defaults: UserDefaults!
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// The payment came first, then its notice; a second purchase brought only its notice.
    func testElSegundoAvisoDelMismoComercioSeQueda() {
        UnreadNotice.note("Oxxo", always: true, justSaved: [["Oxxo"]], now: now, defaults: defaults)
        XCTAssertTrue(UnreadNotice.pending(now: now, defaults: defaults).isEmpty)
        UnreadNotice.note("Oxxo", always: true, justSaved: [["Oxxo"]], now: now.addingTimeInterval(40), defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).map(\.text), ["Oxxo"])
    }

    /// The notice came first and went with its payment: that payment takes no other.
    func testUnPagoQueYaQuitoUnAvisoNoQuitaOtro() {
        UnreadNotice.note("Oxxo", always: true, now: now.addingTimeInterval(-20), defaults: defaults)
        UnreadNotice.settle(savedIn: ["Oxxo", ""], now: now, defaults: defaults)
        XCTAssertTrue(UnreadNotice.pending(now: now, defaults: defaults).isEmpty)
        UnreadNotice.note("Oxxo", always: true, justSaved: [["Oxxo"]], now: now.addingTimeInterval(30), defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).count, 1)
    }

    func testDosPagosQuitanDosAvisos() {
        UnreadNotice.note("Oxxo", always: true, justSaved: [["Oxxo"], ["Oxxo"]], now: now, defaults: defaults)
        UnreadNotice.note("Oxxo", always: true, justSaved: [["Oxxo"], ["Oxxo"]], now: now.addingTimeInterval(10), defaults: defaults)
        XCTAssertTrue(UnreadNotice.pending(now: now, defaults: defaults).isEmpty)
    }

    func testUnPagoBuenoQuitaUnSoloAvisoDeLosQueEsperan() {
        UnreadNotice.note("Oxxo", always: true, now: now.addingTimeInterval(-90), defaults: defaults)
        UnreadNotice.note("Oxxo", always: true, now: now.addingTimeInterval(-30), defaults: defaults)
        UnreadNotice.settle(savedIn: ["Oxxo"], now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).count, 1)
    }

    /// In English the figure is written the app's way, whatever the region (India grouped it).
    func testElMontoDichoEnInglesSeEscribeComoEnLaApp() {
        let said = Decimal(string: "123456.5")!.formatted(spokenStyle("MXN"))
        XCTAssertTrue(said.contains("123,456.50"), said)
        XCTAssertFalse(said.contains("$"), said)
    }

    /// Siri's «más USD 24.99 en otra moneda»: as always in Spanish, by its name in English.
    func testOtraMonedaDichaPorSuNombreEnIngles() {
        XCTAssertEqual(MonthStatus.otherMoney(Decimal(string: "24.99")!, isoCode: "USD", label: "USD", asWritten: true),
                       "USD 24.99")
        let english = MonthStatus.otherMoney(Decimal(string: "24.99")!, isoCode: "USD", label: "USD", asWritten: false)
        XCTAssertTrue(english.contains("24.99"), english)
        XCTAssertFalse(english.hasPrefix("USD"), english)
        let euros = MonthStatus.otherMoney(10, isoCode: "EUR", label: "EUR", asWritten: false)
        XCTAssertTrue(euros.contains("10.00"), euros)
        XCTAssertTrue(euros.lowercased().contains("euro"), euros)
    }
}
