import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// Round 2 of the personas (2026-11-18): Siri in English, the shop-less placeholder, and the
/// texts the guide and «Hoy» put together when shown.
final class CapturaSiriTests: XCTestCase {
    private let suite = "CapturaSiriTests"
    private var defaults: UserDefaults!
    private var context: ModelContext!
    private var container: ModelContainer!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: «dollars» said to Siri

    func testDollarsEnInglesSonDolares() {
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("dollars", primary: "MXN"), "USD")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("Dollar", primary: "MXN"), "USD")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("USdollars", primary: "MXN"), "USD")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("bucks", primary: "MXN"), "USD")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("euros", primary: "MXN"), "EUR")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("pesos", primary: "USD"), "MXN")
        XCTAssertEqual(ExpenseRecorder.spokenCurrency("dólares", primary: "MXN"), "USD")
    }

    func testVeinteDollarsSeGuardanEnDolares() throws {
        let outcome = try ExpenseRecorder.recordByHand(amountText: "20 dollars", merchant: "Starbucks", in: context,
                                                       primary: "MXN", rules: CategoryRules(), hidden: [], now: now)
        XCTAssertEqual(outcome, .saved(merchant: "Starbucks"))
        let saved = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(saved.first?.currencyMarker, "USD", "«20 dollars» se guardó en la moneda principal")
    }

    // MARK: «Sin comercio»

    func testSinComercioSeGuardaEnEspanolYSeMuestraTraducido() throws {
        let outcome = try ExpenseRecorder.recordByHand(amountText: "89", merchant: "  ", in: context,
                                                       primary: "MXN", rules: CategoryRules(), hidden: [], now: now)
        XCTAssertEqual(outcome, .saved(merchant: "Sin comercio"))
        let expense = try XCTUnwrap(try context.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(expense.merchant, "Sin comercio", "Lo guardado sigue en español")
        XCTAssertEqual(expense.shownName, Expense.shownMerchant("Sin comercio"))
        XCTAssertNotNil(expense.searchable.readableName, "La búsqueda no encontraría «No merchant»")
        XCTAssertEqual(Expense.shownMerchant("Oxxo"), "Oxxo")
    }

    // MARK: Money said out loud

    func testElDineroDichoEnEspanolEsElDeLaPantalla() {
        let said = spokenMoney(45, isoCode: "MXN", label: "MXN", main: "MXN")
        if saysMoneyAsWritten {
            XCTAssertEqual(said, formatMoney(45, isoCode: "MXN", label: "MXN", main: "MXN"))
        } else {
            XCTAssertFalse(said.contains("$"), "En inglés «$» se lee «dollars»: \(said)")
        }
        XCTAssertEqual(spokenMoney(45, isoCode: nil, label: "Bs.", main: "MXN"),
                       formatMoney(45, isoCode: nil, label: "Bs.", main: "MXN"))
    }

    // MARK: The guide and «Hoy», put together when read

    func testElPagoQueLlegoSeArmaAlLeerlo() {
        CaptureArrival.note(amount: "$47.50", merchant: "Oxxo", arrivedBefore: false, now: now, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: CaptureArrival.amountKey), "$47.50")
        XCTAssertEqual(defaults.string(forKey: CaptureArrival.merchantKey), "Oxxo")
        XCTAssertEqual(CaptureArrival.latestText(defaults: defaults), PendingPayment.line(amount: "$47.50", merchant: "Oxxo"))
        XCTAssertEqual(CaptureArrival.firstText(defaults: defaults), PendingPayment.line(amount: "$47.50", merchant: "Oxxo"))
    }

    func testLoQueDejoUnaVersionAnteriorSeLeeComoQuedo() {
        defaults.set("$47.50 at Oxxo", forKey: CaptureArrival.textKey)
        XCTAssertEqual(CaptureArrival.latestText(defaults: defaults), "$47.50 at Oxxo")
        XCTAssertEqual(CaptureArrival.firstText(defaults: defaults), "")
    }

    func testOlvidarQuitaTambienLasPartes() {
        CaptureArrival.note(amount: "$47.50", merchant: "Oxxo", arrivedBefore: false, now: now, defaults: defaults)
        CaptureArrival.forget(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: CaptureArrival.amountKey))
        XCTAssertNil(defaults.string(forKey: CaptureArrival.firstMerchantKey))
        XCTAssertEqual(CaptureArrival.latestText(defaults: defaults), "")
    }
}
