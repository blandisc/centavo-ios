import CentavoCore
import XCTest
@testable import Centavo

/// The payments the capture couldn't write down, as they are kept outside the store
/// (`UnreadNotice`), and what only this iPhone knows about the automation (`CaptureArrival`).
final class PendingPaymentsStoreTests: XCTestCase {
    private let suite = "PendingPaymentsStoreTests"
    private var defaults: UserDefaults!
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: H10 · a list, emptied only by the person

    func testUnPagoIlegibleSeguidoDeOtroSeQuedanLosDos() {
        UnreadNotice.note("Google", now: now.addingTimeInterval(-3600), defaults: defaults)
        UnreadNotice.note("Oxxo", now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).map(\.text), ["Oxxo", "Google"])
    }

    func testUnAvisoQueNoEsCargoNoSeGuarda() {
        UnreadNotice.note("Aeroméxico\nTu pase de abordar está listo", now: now, defaults: defaults)
        XCTAssertTrue(UnreadNotice.pending(now: now, defaults: defaults).isEmpty)
        UnreadNotice.note("American Express\nGoogle\nMXN 3I9.00", always: true, now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).count, 1)
    }

    func testDescartarUnoDejaLosDemasYDescartarTodosVaciaLaLista() throws {
        UnreadNotice.note("Google", now: now.addingTimeInterval(-60), defaults: defaults)
        UnreadNotice.noteUnsaved(amount: "$319", merchant: "Liverpool", card: nil, now: now, defaults: defaults)
        let first = try XCTUnwrap(UnreadNotice.pending(now: now, defaults: defaults).first)
        XCTAssertEqual(first.text, "$319 en Liverpool")
        UnreadNotice.remove(first.id, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).map(\.text), ["Google"])
        UnreadNotice.clear(defaults: defaults)
        XCTAssertTrue(UnreadNotice.pending(now: now, defaults: defaults).isEmpty)
        XCTAssertNil(defaults.string(forKey: UnreadNotice.listKey))
    }

    func testALosTreintaDiasYaNoSeMuestra() {
        UnreadNotice.note("Google", now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now.addingTimeInterval(29 * 86_400), defaults: defaults).count, 1)
        XCTAssertTrue(UnreadNotice.pending(now: now.addingTimeInterval(31 * 86_400), defaults: defaults).isEmpty)
    }

    // MARK: A name-only notice and the good payment it was

    func testUnAvisoConSoloElNombreSeQuitaConElPagoBuenoDeEseComercio() {
        UnreadNotice.note("Oxxo", now: now.addingTimeInterval(-60), defaults: defaults)
        UnreadNotice.note("Google", now: now.addingTimeInterval(-60), defaults: defaults)
        UnreadNotice.settle(savedIn: ["OXXO ROBLE MTY", ""], now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).map(\.text), ["Google"])
    }

    func testUnAvisoConSoloElNombreNoSeGuardaSiEsePagoAcabaDeAnotarse() {
        UnreadNotice.note("Oxxo", justSaved: ["Oxxo Roble"], now: now, defaults: defaults)
        XCTAssertTrue(UnreadNotice.pending(now: now, defaults: defaults).isEmpty)
        UnreadNotice.note("Oxxo", justSaved: ["Google"], now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).count, 1)
    }

    func testLoQueTraeCifraOMonedaOUnPagoSinGuardarNuncaSeQuitaSolo() {
        UnreadNotice.note("Oxxo 3I9.00", always: true, now: now, defaults: defaults)
        UnreadNotice.noteUnsaved(amount: "$89", merchant: "Oxxo", card: nil, now: now, defaults: defaults)
        UnreadNotice.settle(savedIn: ["Oxxo"], now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).count, 2)
        // Nor a name-only one once the two minutes have gone by.
        UnreadNotice.note("Oxxo", now: now, defaults: defaults)
        UnreadNotice.settle(savedIn: ["Oxxo"], now: now.addingTimeInterval(600), defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now.addingTimeInterval(600), defaults: defaults).count, 3)
    }

    // MARK: H9 · a payment the store couldn't take

    func testUnPagoQueNoSePudoGuardarQuedaConLoQueSeLeyo() throws {
        UnreadNotice.noteUnsaved(amount: "MXN 319.00", merchant: "Google", card: "American Express México",
                                 now: now, defaults: defaults)
        let kept = try XCTUnwrap(UnreadNotice.pending(now: now, defaults: defaults).first)
        XCTAssertEqual(kept.kind, .unsaved)
        XCTAssertEqual(kept.text, "MXN 319.00 en Google")
        XCTAssertEqual(kept.amount, "MXN 319.00")
        XCTAssertEqual(kept.merchant, "Google")
        XCTAssertEqual(kept.card, "American Express México")
        XCTAssertEqual(kept.date, now)
    }

    // MARK: The single notice of earlier versions

    func testElAvisoUnicoDeAntesPasaALaLista() {
        defaults.set("Google", forKey: UnreadNotice.textKey)
        defaults.set(now.addingTimeInterval(-3600).timeIntervalSinceReferenceDate, forKey: UnreadNotice.dateKey)
        UnreadNotice.carryOverSingleNotice(now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).map(\.text), ["Google"])
        XCTAssertNil(defaults.string(forKey: UnreadNotice.textKey))
        // Once: a second pass adds nothing.
        UnreadNotice.carryOverSingleNotice(now: now, defaults: defaults)
        XCTAssertEqual(UnreadNotice.pending(now: now, defaults: defaults).count, 1)
    }

    func testElAvisoUnicoQueYaNoSeMostrabaNoRevive() {
        defaults.set("Google", forKey: UnreadNotice.textKey)
        defaults.set(now.addingTimeInterval(-3 * 86_400).timeIntervalSinceReferenceDate, forKey: UnreadNotice.dateKey)
        UnreadNotice.carryOverSingleNotice(now: now, defaults: defaults)
        XCTAssertTrue(UnreadNotice.pending(now: now, defaults: defaults).isEmpty)
        XCTAssertNil(defaults.string(forKey: UnreadNotice.textKey))
    }

    // MARK: Neither travels in a backup nor is replaced by one

    func testLoPendienteYLaPruebaDeWalletNoViajanEnElRespaldo() {
        for key in [UnreadNotice.listKey, CaptureArrival.dateKey, CaptureArrival.textKey, CaptureArrival.sessionKey] {
            XCTAssertFalse(DailyBackup.Settings.isOurs(key), "«\(key)» viajaría en el respaldo y se reemplazaría al restaurar")
        }
    }

    // MARK: H1 · «Ya funciona» only with a payment that arrived here after opening the guide

    func testLaGuiaSoloDaPorBuenoUnPagoQueLlegoDespuesDeAbrirla() {
        // A payment arrived yesterday; the guide is opened today.
        CaptureArrival.note(amount: "$47.50", merchant: "Oxxo", now: now.addingTimeInterval(-86_400), defaults: defaults)
        CaptureArrival.openGuide(now: now, defaults: defaults)
        XCTAssertEqual(proof(at: now.addingTimeInterval(60)), .waiting(last: now.addingTimeInterval(-86_400)))
        // One arrives five minutes later.
        let arrival = now.addingTimeInterval(300)
        CaptureArrival.note(amount: "$89.00", merchant: "Starbucks", now: arrival, defaults: defaults)
        XCTAssertEqual(proof(at: arrival.addingTimeInterval(5)), .working(arrived: arrival))
        XCTAssertEqual(defaults.string(forKey: CaptureArrival.textKey), "$89.00 en Starbucks")
    }

    func testUnRespaldoRestauradoNoEsPrueba() {
        // Nothing arrived on this iPhone; the expenses brought a capture from a minute ago.
        CaptureArrival.openGuide(now: now, defaults: defaults)
        let restored = now.addingTimeInterval(240)
        XCTAssertEqual(proof(at: now.addingTimeInterval(300), lastKnown: restored), .waiting(last: restored))
    }

    func testVolverAAbrirLaGuiaEnElMismoRatoNoPierdeElPagoQueLlego() {
        CaptureArrival.openGuide(now: now, defaults: defaults)
        let arrival = now.addingTimeInterval(1_200)
        CaptureArrival.note(amount: "$47.50", merchant: "Oxxo", now: arrival, defaults: defaults)
        // The app was closed meanwhile; the guide is opened again two minutes after the payment.
        CaptureArrival.openGuide(now: arrival.addingTimeInterval(120), defaults: defaults)
        XCTAssertEqual(proof(at: arrival.addingTimeInterval(121)), .working(arrived: arrival))
    }

    func testVolverHorasDespuesDeUnaPruebaEmpiezaDeNuevo() {
        CaptureArrival.openGuide(now: now, defaults: defaults)
        let arrival = now.addingTimeInterval(600)
        CaptureArrival.note(amount: "$47.50", merchant: "Oxxo", now: arrival, defaults: defaults)
        let later = arrival.addingTimeInterval(5 * 3600)
        CaptureArrival.openGuide(now: later, defaults: defaults)
        XCTAssertEqual(proof(at: later.addingTimeInterval(1)), .waiting(last: arrival))
    }

    private func proof(at moment: Date, lastKnown: Date? = nil) -> CaptureProof {
        CaptureArrival.proof(session: defaults.double(forKey: CaptureArrival.sessionKey),
                             arrived: defaults.double(forKey: CaptureArrival.dateKey),
                             lastKnown: lastKnown, now: moment)
    }
}
