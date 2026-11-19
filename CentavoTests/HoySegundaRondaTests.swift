import CentavoCore
import XCTest
@testable import Centavo

/// «Hoy», second round (2026-11-18): the empty screen's Wallet card never asks to connect what
/// already delivered payments, «Anotar otra vez» from out of sight says the copy is today's, and
/// a fixed expense due with the app open wakes it.
@MainActor
final class HoySegundaRondaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Wallet card on the empty screen

    func testPaymentsThatCameAndWereDeletedDontAskToConnect() {
        // Every expense deleted, the arrival remembered: `.recent`, `.first` or `.quiet`.
        let healths: [CaptureHealth] = [.recent(now), .first(now), .quiet(days: 5)]
        for health in healths {
            let card = WalletCard(health)
            XCTAssertNotNil(card)
            XCTAssertNotEqual(card?.title, "Conectar Wallet", "\(health) volvió a pedir conectar Wallet")
        }
        XCTAssertEqual(WalletCard(.recent(now))?.title, "Wallet conectado")
        XCTAssertEqual(WalletCard(.quiet(days: 5))?.title, "Sin pagos de Wallet desde hace 5 días")
        XCTAssertTrue(WalletCard(.first(now))?.detail.hasPrefix("Último pago ") ?? false)
    }

    func testNeverConnectedStillAsksToConnect() {
        XCTAssertEqual(WalletCard(.never)?.title, "Conectar Wallet")
        XCTAssertEqual(WalletCard(.waiting)?.title, "Esperando tu primer pago")
    }

    func testAPendingPaymentHidesWhatWouldContradictIt() {
        // A payment came, unread: Wallet is connected, the notice above already says what to do.
        XCTAssertNil(WalletCard(.never, pending: true))
        XCTAssertNil(WalletCard(.waiting, pending: true))
        XCTAssertNotNil(WalletCard(.silent(days: 4), pending: true))
        XCTAssertEqual(WalletCard(.recent(now), pending: true)?.title, "Wallet conectado")
    }

    // MARK: «Anotar otra vez»

    func testACopyOutOfSightSaysItIsDatedToday() {
        let expense = Expense(amount: 45, currencyMarker: "$", merchant: "Café", date: now)
        let here = CopiedExpense(expense: expense, name: "Café")
        XCTAssertEqual(here.text, "Anotaste otra vez Café")
        XCTAssertEqual(here.spoken, "Anotaste otra vez Café. Puedes deshacerlo.")
        let away = CopiedExpense(expense: expense, name: "Café", dated: true)
        XCTAssertEqual(away.text, "Anotaste otra vez Café con fecha de hoy")
        XCTAssertEqual(away.spoken, "Anotaste otra vez Café con fecha de hoy. Puedes deshacerlo.")
    }

    // MARK: A fixed expense due with the app open

    func testWakesForTheSoonestChargeStillToCome() {
        let rent = now.addingTimeInterval(3 * 3600)
        let netflix = now.addingTimeInterval(26 * 3600)
        XCTAssertEqual(FixedWake.next([netflix, nil, rent], after: now), rent)
    }

    func testNothingToComeMeansNoWake() {
        XCTAssertNil(FixedWake.next([nil, now, now.addingTimeInterval(-60)], after: now))
        XCTAssertNil(FixedWake.next([], after: now))
    }
}
