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

    // MARK: Audit 2026-11-02

    private func monthAgo(_ months: Int, from date: Date = .now) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: date)!
    }

    func testAnAccountAddedWhileACutIsBeingWrittenIsInTheCut() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        try MoneyStore.add(nu, balance: 1_000, rate: nil, in: context, mainCurrency: "MXN")
        let draft = try MoneyStore.draftForThisMonth(in: context, mainCurrency: "MXN")
        let bbva = MoneyAccount(name: "BBVA", kind: .account, currency: "MXN")
        try MoneyStore.add(bbva, balance: 2_500, rate: nil, in: context, mainCurrency: "MXN")
        XCTAssertEqual(draft.entry(for: bbva)?.balance, 2_500)
        XCTAssertEqual(draft.entry(for: bbva)?.reviewed, true)
        draft.entry(for: nu)?.reviewed = true
        try MoneyStore.finish(draft, replacing: true, in: context)
        // Replacing this month's cut used to delete BBVA's only balance with it.
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.netWorth.total, 3_500)
    }

    func testReplacingKeepsLinesTheDraftDidNotHave() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        try MoneyStore.add(nu, balance: 1_000, rate: nil, in: context, mainCurrency: "MXN")
        let draft = try MoneyStore.draftForThisMonth(in: context, mainCurrency: "MXN")
        // An account that reached the old cut and not the draft (as before this fix).
        let gbm = MoneyAccount(name: "GBM", kind: .investment, currency: "MXN")
        context.insert(gbm)
        let line = MoneyEntry(balance: 700, account: gbm, reviewed: true)
        context.insert(line)
        line.cut = MoneyStore.latestCut(in: context)
        try context.save()
        try MoneyStore.finish(draft, replacing: true, in: context)
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.entry(for: gbm)?.balance, 700)
    }

    func testADraftPicksUpNewAccountsAndDropsArchivedOnes() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        let old = MoneyAccount(name: "Vieja", kind: .account, currency: "MXN")
        try MoneyStore.add(nu, balance: 1_000, rate: nil, in: context, mainCurrency: "MXN")
        try MoneyStore.add(old, balance: 10, rate: nil, in: context, mainCurrency: "MXN")
        let draft = try MoneyStore.draftForThisMonth(in: context, mainCurrency: "MXN")
        let added = MoneyAccount(name: "Nueva", kind: .account, currency: "MXN")
        context.insert(added)
        old.archived = true
        try context.save()
        let again = try XCTUnwrap(MoneyStore.openDraft(in: context))
        XCTAssertEqual(again.id, draft.id)
        XCTAssertNotNil(again.entry(for: added))
        XCTAssertNil(again.entry(for: old))
    }

    func testALeftoverDraftOfLastMonthIsOfferedNotOrphaned() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        let october = monthAgo(-1)
        try MoneyStore.add(nu, balance: 1_000, rate: nil, in: context, mainCurrency: "MXN", now: october)
        let draft = try MoneyStore.draftForThisMonth(in: context, now: october, mainCurrency: "MXN")
        XCTAssertEqual(try MoneyStore.openDraft(in: context)?.id, draft.id, "El corte a medias de octubre se ofrece")
    }

    func testARateWrittenTodayNeverRewritesAPastCut() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let past = monthAgo(-2)
        let dollars = MoneyAccount(name: "Dólares", kind: .account, currency: "USD")
        try MoneyStore.add(dollars, balance: 100, rate: 17, in: context, mainCurrency: "MXN", now: past)
        try MoneyStore.update(dollars, balance: 120, rate: 20, in: context)
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.rateTable["USD"], 17)
        let euros = MoneyAccount(name: "Euros", kind: .account, currency: "EUR")
        try MoneyStore.add(euros, balance: 10, rate: 21, in: context, mainCurrency: "MXN")
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.rateTable["EUR"], 21, "Una moneda que no tenía tipo sí lo recibe")
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.rateTable["USD"], 17)
    }

    func testTheMonthSuggestedForACut() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let early = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        XCTAssertEqual(MoneyStore.suggestedMonths(now: early, calendar: calendar), ["2026-10", "2026-11"])
        XCTAssertEqual(MoneyStore.suggestedMonths(now: late, calendar: calendar), ["2026-11", "2026-10"])
    }

    func testAMoneyAmountReadsThePointAsDecimal() {
        XCTAssertEqual(MoneyAmount.read("15,000.50"), Decimal(string: "15000.50"))
        XCTAssertNil(MoneyAmount.read("15000.125"), "Más de dos decimales se pregunta")
        XCTAssertNil(MoneyAmount.read("25 mil"))
        XCTAssertEqual(MoneyAmount.read("2,000"), 2_000)
    }

    func testAnArchivedAccountNoLongerAddsUpToday() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        let amex = MoneyAccount(name: "Amex", kind: .debt, currency: "MXN")
        try MoneyStore.add(nu, balance: 1_000, rate: nil, in: context, mainCurrency: "MXN")
        try MoneyStore.add(amex, balance: 300, rate: nil, in: context, mainCurrency: "MXN")
        amex.archived = true
        let cut = try XCTUnwrap(MoneyStore.latestCut(in: context))
        XCTAssertEqual(cut.activeNetWorth.total, 1_000)
        XCTAssertEqual(cut.netWorth.total, 700, "El corte como se hizo no cambia")
    }
}
