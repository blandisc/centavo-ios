import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// «Llegó tu primer pago solo» (2026-11-18), through the same steps the Wallet intents take:
/// `ExpenseRecorder.record` marks the payment as arrived (`WalletWatch`), and only then
/// `CaptureArrival.note` runs. Asked there, the first payment never counted as the first.
final class CapturaPrimerPagoTests: XCTestCase {
    private let suite = "CapturaPrimerPagoTests"
    private var defaults: UserDefaults!
    private var context: ModelContext!
    private var container: ModelContainer!
    /// `WalletWatch` writes to the standard defaults: what was there goes back after each test.
    private var arrivalBefore: Any?
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        arrivalBefore = UserDefaults.standard.object(forKey: WalletWatch.lastArrivalKey)
        UserDefaults.standard.removeObject(forKey: WalletWatch.lastArrivalKey)
        container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        if let arrivalBefore {
            UserDefaults.standard.set(arrivalBefore, forKey: WalletWatch.lastArrivalKey)
        } else {
            UserDefaults.standard.removeObject(forKey: WalletWatch.lastArrivalKey)
        }
    }

    /// The intent's order: asked first, then saved, then noted.
    private func capture(_ amount: String, _ merchant: String, at moment: Date) throws {
        let arrivedBefore = CaptureArrival.walletKnown()
        let outcome = try ExpenseRecorder.record(amountText: amount, merchant: merchant, card: "BBVA",
                                                 in: context, primary: "MXN", rules: CategoryRules(),
                                                 hidden: [], renames: MerchantRenames(),
                                                 cardRenames: MerchantRenames(), now: moment)
        XCTAssertEqual(outcome, .saved(merchant: merchant))
        CaptureArrival.note(amount: CaptureText.shown(amount), merchant: merchant,
                            arrivedBefore: arrivedBefore, now: moment, defaults: defaults)
    }

    func testElPrimerPagoQuePasaPorElGuardadoCuentaComoPrimero() throws {
        try capture("$47.50", "Oxxo", at: now)
        XCTAssertEqual(defaults.double(forKey: CaptureArrival.firstKey), now.timeIntervalSinceReferenceDate,
                       "El primer pago no quedó como primero: «Llegó tu primer pago solo» no saldría")
        XCTAssertEqual(defaults.string(forKey: CaptureArrival.firstTextKey), "$47.50 en Oxxo")
    }

    func testLosPagosSiguientesNoCambianElPrimero() throws {
        try capture("$47.50", "Oxxo", at: now)
        try capture("-$230.00", "Liverpool", at: now.addingTimeInterval(600))
        XCTAssertEqual(defaults.double(forKey: CaptureArrival.firstKey), now.timeIntervalSinceReferenceDate)
        XCTAssertEqual(defaults.string(forKey: CaptureArrival.firstTextKey), "$47.50 en Oxxo",
                       "El primer pago se dice con el último (aquí, una devolución)")
        XCTAssertEqual(defaults.string(forKey: CaptureArrival.textKey), "-$230.00 en Liverpool")
    }

    func testQuienYaRecibiaPagosNoVePrimerPago() throws {
        // Payments arrived before `firstKey` existed: only `WalletWatch` knew.
        UserDefaults.standard.set(now.addingTimeInterval(-86_400).timeIntervalSinceReferenceDate,
                                  forKey: WalletWatch.lastArrivalKey)
        try capture("$47.50", "Oxxo", at: now)
        XCTAssertEqual(defaults.double(forKey: CaptureArrival.firstKey), 0)
        XCTAssertNil(defaults.string(forKey: CaptureArrival.firstTextKey))
    }

    /// The whole payment connected instead of its «Importe»: the guide and «Hoy» say only the
    /// figure that was read.
    func testElPagoCompletoNoRepiteElComercioEnLaPrueba() throws {
        try capture("ALL 2 GO MXN 300.00", "ALL 2 GO", at: now)
        let text = try XCTUnwrap(defaults.string(forKey: CaptureArrival.textKey))
        XCTAssertEqual(text, "MXN 300.00 en ALL 2 GO")
        XCTAssertFalse(text.hasPrefix("ALL 2 GO"))
    }

    func testOlvidarBorraTambienElTextoDelPrimero() throws {
        try capture("$47.50", "Oxxo", at: now)
        CaptureArrival.forget(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: CaptureArrival.firstTextKey))
        XCTAssertFalse(DailyBackup.Settings.isOurs(CaptureArrival.firstTextKey),
                       "El texto del primer pago viajaría en el respaldo")
    }

    /// A store that failed once is tried again by any intent, and an open one is handed back
    /// as it is (`Store.forIntent`, 2026-11-18).
    func testElAlmacenDeLosIntentsEsElMismoQueElAbierto() throws {
        let opened = try Store.opened.get()
        XCTAssertTrue(Store.forIntent === opened)
    }
}
