import XCTest
@testable import Centavo

final class WalletWatchTests: XCTestCase {
    func testDeletingTheWalletPaymentsDoesNotDisconnectIt() {
        let arrived = Date(timeIntervalSinceReferenceDate: 783_000_000)
        // Every payment from Wallet was deleted: the store has none, the memory still knows.
        XCTAssertEqual(WalletWatch.lastCapture(stored: arrived.timeIntervalSinceReferenceDate, newestInStore: nil), arrived)
    }

    func testTheLaterOfTheTwoWins() {
        let older = Date(timeIntervalSinceReferenceDate: 783_000_000)
        let newer = older.addingTimeInterval(3_600)
        XCTAssertEqual(WalletWatch.lastCapture(stored: older.timeIntervalSinceReferenceDate, newestInStore: newer), newer)
        XCTAssertEqual(WalletWatch.lastCapture(stored: newer.timeIntervalSinceReferenceDate, newestInStore: older), newer)
    }

    func testNeverConnectedStaysNever() {
        XCTAssertNil(WalletWatch.lastCapture(stored: 0, newestInStore: nil))
    }
}
