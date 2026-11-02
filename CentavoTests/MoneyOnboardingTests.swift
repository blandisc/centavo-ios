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

    func testAnImportIsSavedInOneGo_WithRatesPerCurrencyAndIncomesApart() throws {
        let container = try MoneyStore.inMemory()
        let context = ModelContext(container)
        let lines = [
            MoneyLineToSave(subtype: .account, name: "Cajita", institution: "Nu", currency: "MXN", amount: 185_000, yearlyRate: Decimal(string: "10.5")),
            MoneyLineToSave(subtype: .account, name: "Dólares", institution: "BBVA", currency: "USD", amount: 2_000, yearlyRate: nil),
            MoneyLineToSave(subtype: .account, name: "Euros", institution: "Wise", currency: "EUR", amount: 500, yearlyRate: nil),
            MoneyLineToSave(subtype: .loan, name: "Auto", institution: "BBVA", currency: "MXN", amount: 120_000, yearlyRate: 12),
            MoneyLineToSave(subtype: .income, name: "Sueldo", institution: "Arca", currency: "MXN", amount: 60_000, yearlyRate: nil),
        ]
        try MoneyStore.addAll(lines, rates: ["USD": Decimal(string: "18.5")!, "EUR": 20], in: context, mainCurrency: "MXN")
        let cut = try XCTUnwrap(MoneyStore.latestCut(in: context))
        XCTAssertEqual(cut.rateTable, ["USD": Decimal(string: "18.5")!, "EUR": 20])
        // 185,000 + 2,000×18.5 + 500×20 − 120,000
        XCTAssertEqual(cut.netWorth.total, 112_000)
        let accounts = try context.fetch(MoneyStore.activeAccounts)
        XCTAssertEqual(accounts.map(\.name), ["Cajita", "Dólares", "Euros", "Auto"])
        XCTAssertEqual(accounts.last?.subtype, "prestamo")
        XCTAssertEqual(accounts.first?.institution, "Nu")
        let incomes = try context.fetch(MoneyStore.activeIncomes)
        XCTAssertEqual(incomes.map(\.amount), [60_000])
    }

    func testAnImportedRowWithAProblemWaitsUntilReviewed() {
        let line = MoneyImport.parse("tipo,nombre,monto\nalcancia,Cochinito,100", main: "MXN").lines[0]
        var row = MoneyImportRow(line: line, main: "MXN", existing: [])
        XCTAssertFalse(row.isReady(main: "MXN"))
        row.reviewed = true
        XCTAssertTrue(row.isReady(main: "MXN"))
    }

    func testALineAlreadyThereIsOfferedButLeftOut() {
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        let line = MoneyImport.parse("tipo,nombre,institucion,monto\ncuenta,Cajita,Nu,100", main: "MXN").lines[0]
        let row = MoneyImportRow(line: line, main: "MXN", existing: [nu])
        XCTAssertEqual(row.duplicateOf, "Nu")
        XCTAssertFalse(row.include)
    }

    func testAnImportKeepsAnOlderCutsRatesAndMakesNoCutForIncomesAlone() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        try MoneyStore.addAll([MoneyLineToSave(subtype: .income, name: "Sueldo", institution: nil, currency: "MXN",
                                               amount: 60_000, yearlyRate: nil)],
                              rates: [:], in: context, mainCurrency: "MXN")
        XCTAssertNil(MoneyStore.latestCut(in: context), "Solo ingresos: no hace un corte vacío")

        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        try MoneyStore.add(MoneyAccount(name: "Dólares", kind: .account, currency: "USD"), balance: 100, rate: 20,
                           in: context, mainCurrency: "MXN", now: lastMonth)
        try MoneyStore.addAll([MoneyLineToSave(subtype: .account, name: "Euros", institution: nil, currency: "EUR",
                                               amount: 10, yearlyRate: nil)],
                              rates: ["USD": 17, "EUR": 21], in: context, mainCurrency: "MXN")
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.rateTable, ["USD": 20, "EUR": 21],
                       "El corte de otro mes conserva su tipo de cambio")
    }

    func testAnIncomeIsOnlyTheSameAsAnIncome() {
        let account = MoneyAccount(name: "Nómina", kind: .account, currency: "MXN")
        let income = MoneyIncome(name: "Sueldo", institution: nil, amount: 1, currency: "MXN")
        let lines = MoneyImport.parse("tipo,nombre,monto,repite\ningreso,Nómina,60000,si\ningreso,Sueldo,60000,si", main: "MXN").lines
        XCTAssertNil(MoneyImportRow(line: lines[0], main: "MXN", existing: [account], incomes: [income]).duplicateOf)
        XCTAssertEqual(MoneyImportRow(line: lines[1], main: "MXN", existing: [account], incomes: [income]).duplicateOf, "Sueldo")
    }

    func testARowStaysInItsGroupWhileEdited() {
        let line = MoneyImport.parse("tipo,nombre,monto\ncuenta,Nu,100", main: "MXN").lines[0]
        var row = MoneyImportRow(line: line, main: "MXN", existing: [])
        row.place(main: "MXN")
        XCTAssertEqual(row.placed, .have)
        row.draft.amount = ""
        row.draft.subtype = .card
        XCTAssertEqual(row.placed, .have, "Mientras se escribe, no brinca de grupo")
        row.draft.amount = "50"
        row.place(main: "MXN")
        XCTAssertEqual(row.placed, .owe)
    }
}
