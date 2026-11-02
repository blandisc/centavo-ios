import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

@MainActor
final class MoneyOnboardingTests: XCTestCase {
    func testAnExchangeRateWithThreeDecimalsIsNotThousands() {
        var draft = MoneyRowDraft(subtype: .account, currency: "USD")
        draft.name = "Dólares"
        draft.amount = "2,000"
        draft.exchangeText = "18.125"
        XCTAssertEqual(draft.exchange, Decimal(string: "18.125"))
        XCTAssertEqual(draft.balance, 2_000)
        XCTAssertTrue(draft.isComplete(mainCurrency: "MXN"))
        draft.exchangeText = "17.2534"
        XCTAssertTrue(draft.isComplete(mainCurrency: "MXN"))
    }

    func testARowNeedsAName_AnAmount_AndTheRateIfForeign() {
        var draft = MoneyRowDraft(subtype: .card, currency: "MXN")
        XCTAssertFalse(draft.hasContent)
        draft.name = "Amex"
        XCTAssertTrue(draft.hasContent)
        XCTAssertFalse(draft.isComplete(mainCurrency: "MXN"))
        draft.amount = "6420"
        XCTAssertTrue(draft.isComplete(mainCurrency: "MXN"))
        draft.rate = "abc"
        XCTAssertFalse(draft.isComplete(mainCurrency: "MXN"), "Una tasa que no se lee no se guarda en silencio")
        draft.rate = "45.5"
        XCTAssertEqual(draft.yearlyRate, Decimal(string: "45.5"))
        draft.currency = "USD"
        XCTAssertFalse(draft.isComplete(mainCurrency: "MXN"), "En dólares pide el tipo de cambio")
    }

    func testOldLinesGetTheSubtypeOfTheirKind() {
        XCTAssertEqual(MoneySubtype.of(MoneyAccount(name: "a", kind: .debt, currency: "MXN")), .card)
        XCTAssertEqual(MoneySubtype.of(MoneyAccount(name: "b", kind: .receivable, currency: "MXN")), .lent)
        let loan = MoneyAccount(name: "c", kind: .debt, currency: "MXN")
        loan.subtype = MoneySubtype.loan.rawValue
        XCTAssertEqual(MoneySubtype.of(loan), .loan)
    }

    func testUpdatingChangesTheBalanceAndTheRate() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let dollars = MoneyAccount(name: "Dólares", kind: .account, currency: "USD")
        try MoneyStore.add(dollars, balance: 100, rate: 20, in: context, mainCurrency: "MXN")
        try MoneyStore.update(dollars, balance: 150, rate: Decimal(string: "18.125"), in: context)
        let cut = try XCTUnwrap(MoneyStore.latestCut(in: context))
        XCTAssertEqual(cut.entry(for: dollars)?.balance, 150)
        XCTAssertEqual(cut.netWorth.total, Decimal(string: "2718.75"))
    }

    func testRemovingDeletesANewLineButArchivesOneWithHistory() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let typo = MoneyAccount(name: "Error", kind: .account, currency: "MXN")
        try MoneyStore.add(typo, balance: 5, rate: nil, in: context, mainCurrency: "MXN")
        try MoneyStore.remove(typo, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MoneyAccount>()).isEmpty)

        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        try MoneyStore.add(nu, balance: 1_000, rate: nil, in: context, mainCurrency: "MXN")
        // A second month: now it has a history.
        let next = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
        let draft = try MoneyStore.draftForThisMonth(in: context, now: next, mainCurrency: "MXN")
        try MoneyStore.finish(draft, in: context, now: next)
        try MoneyStore.remove(nu, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MoneyAccount>()).first?.archived, true)
        XCTAssertEqual(try context.fetch(MoneyCut.finished).count, 2)
    }
}
