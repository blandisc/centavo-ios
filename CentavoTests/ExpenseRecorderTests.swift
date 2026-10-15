import SwiftData
import XCTest
@testable import Centavo

/// The Wallet capture, end to end, against a throwaway in-memory store.
final class ExpenseRecorderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func saved() throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    @discardableResult
    private func record(_ amount: String, _ merchant: String? = "Oxxo", card: String? = "BBVA",
                        at date: Date? = nil) throws -> CaptureOutcome {
        try ExpenseRecorder.record(amountText: amount, merchant: merchant, card: card,
                                   in: context, now: date ?? now)
    }

    func testSavesAWalletPaymentWithEverythingItCame() throws {
        XCTAssertEqual(try record("$89.00"), .saved(merchant: "Oxxo"))
        let expense = try XCTUnwrap(saved().first)
        XCTAssertEqual(expense.amount, 89)
        XCTAssertEqual(expense.currencyMarker, "$")
        XCTAssertEqual(expense.merchant, "Oxxo")
        XCTAssertEqual(expense.card, "BBVA")
        XCTAssertEqual(expense.rawAmount, "$89.00")
        XCTAssertEqual(expense.date, now)
    }

    func testABlankMerchantBecomesSinComercio() throws {
        XCTAssertEqual(try record("$10", "   "), .saved(merchant: "Sin comercio"))
        XCTAssertEqual(try record("$11", nil, at: now.addingTimeInterval(3_600)),
                       .saved(merchant: "Sin comercio"))
    }

    func testACardThatIsOnlySpacesIsNoCard() throws {
        try record("$10", card: "   ")
        XCTAssertNil(try saved().first?.card)
        try record("$20", "Seven", card: " Nu ", at: now.addingTimeInterval(3_600))
        XCTAssertEqual(try saved().last?.card, "Nu")
    }

    func testAnAbsurdlyLongMerchantIsCut() throws {
        try record("$10", String(repeating: "X", count: 5_000))
        XCTAssertEqual(try saved().first?.merchant.count, ExpenseRecorder.maxMerchantLength)
    }

    func testAZeroPaymentIsAWalletGlitchAndSavesNothing() throws {
        XCTAssertEqual(try record("$0.00", ""), .empty)
        XCTAssertEqual(try saved().count, 0)
    }

    /// Connecting «Entrada del atajo» instead of «Importe» hands over the whole payment.
    func testTheWholePaymentStillSavesTheRightAmount() throws {
        XCTAssertEqual(try record("Oxxo\n$89.00\nBBVA •••• 1234", nil), .saved(merchant: "Sin comercio"))
        XCTAssertEqual(try saved().first?.amount, 89)
    }

    func testACardNumberIsNeverReadAsTheAmount() throws {
        XCTAssertEqual(try record("Oxxo BBVA 1234"), .unreadable)
        XCTAssertEqual(try saved().count, 0)
    }

    func testUnreadableAmountsSaveNothing() throws {
        for junk in ["", "abc", "$", "1234567890123", "1.23456"] {
            XCTAssertEqual(try record(junk), .unreadable, "«\(junk)» debía ser ilegible")
        }
        XCTAssertEqual(try saved().count, 0)
    }

    func testTheSameTapTwiceWithinMinutesIsOnePayment() throws {
        XCTAssertEqual(try record("$89.00"), .saved(merchant: "Oxxo"))
        XCTAssertEqual(try record("$89.00", "OXXO ", card: "bbva", at: now.addingTimeInterval(90)),
                       .duplicate(merchant: "OXXO"))
        XCTAssertEqual(try saved().count, 1)
    }

    func testTheSamePurchaseLaterIsANewPayment() throws {
        try record("$89.00")
        XCTAssertEqual(try record("$89.00", at: now.addingTimeInterval(10 * 60)),
                       .saved(merchant: "Oxxo"))
        XCTAssertEqual(try saved().count, 2)
    }

    func testARefundIsSavedNegative() throws {
        try record("-$230.00", "Liverpool")
        XCTAssertEqual(try saved().first?.amount, -230)
    }

    func testAForeignCurrencyKeepsItsMarker() throws {
        try record("USD 24.99", "Steam")
        let expense = try XCTUnwrap(saved().first)
        XCTAssertEqual(expense.amount, Decimal(string: "24.99"))
        XCTAssertEqual(expense.currencyMarker, "USD")
    }

    func testAPaymentLandsInTheCategoryTheMerchantWasLastFiledUnder() throws {
        context.insert(Expense(amount: 50, currencyMarker: "$", merchant: "Oxxo",
                               date: now.addingTimeInterval(-86_400), category: "Despensa"))
        try context.save()
        try record("$89.00", "OXXO")
        let capture = try XCTUnwrap(saved().last)
        XCTAssertEqual(capture.category, "Despensa")
    }

    func testAMerchantNeverSeenBeforeHasNoCategory() throws {
        try record("$89.00", "Un lugar nuevo")
        XCTAssertNil(try saved().first?.category)
    }
}
