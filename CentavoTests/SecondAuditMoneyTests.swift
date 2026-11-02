import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// Segunda auditoría (2026-11-02): «Mi dinero» y los cálculos de «Hoy», contra un almacén en
/// memoria.
@MainActor
final class SecondAuditMoneyTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SecondAuditMoneyTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Septiembre con Nu 10,000 y Caja 5,000; octubre con Nu 11,000 y Caja 5,000.
    private func twoMonths(_ context: ModelContext) throws -> (nu: MoneyAccount, caja: MoneyAccount) {
        let sep = date(2026, 9, 30), oct = date(2026, 10, 31)
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        nu.createdAt = sep
        let caja = MoneyAccount(name: "Caja", kind: .account, currency: "MXN")
        caja.createdAt = sep
        try MoneyStore.add(nu, balance: 10_000, rate: nil, in: context, mainCurrency: "MXN", now: sep, defaults: defaults)
        try MoneyStore.add(caja, balance: 5_000, rate: nil, in: context, mainCurrency: "MXN", now: sep, defaults: defaults)
        let draft = try MoneyStore.draft(for: "2026-10", in: context, now: oct, mainCurrency: "MXN", defaults: defaults)
        draft.entry(for: nu)?.balance = 11_000
        for entry in draft.entries ?? [] { entry.reviewed = true }
        try MoneyStore.finish(draft, in: context, now: oct)
        return (nu, caja)
    }

    // MARK: #2 Archivar no es pérdida

    func testArchivingAnAccountIsNotALossSinceLastCut() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let (_, caja) = try twoMonths(context)
        caja.archived = true
        try context.save()
        let cuts = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(cuts.count, 2)
        XCTAssertEqual(cuts[1].change(since: cuts[0]), 1_000)
    }

    // MARK: #3 Una cuenta nueva no es ahorro, y su tipo de cambio no se pierde

    func testANewAccountIsNotSavedMoney() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        _ = try twoMonths(context)
        let fondo = MoneyAccount(name: "Fondo", kind: .investment, currency: "MXN")
        fondo.createdAt = date(2026, 11, 15)
        try MoneyStore.add(fondo, balance: 100_000, rate: nil, in: context, mainCurrency: "MXN",
                           now: date(2026, 11, 15), defaults: defaults)
        let cuts = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(cuts[1].change(since: cuts[0]), 1_000, "El fondo nuevo no sale como «+$100,000 desde sep»")
    }

    func testARateTypedForAPastCutWaitsForTheNextOne() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let usd = MoneyAccount(name: "Dólares", kind: .account, currency: "USD")
        usd.createdAt = date(2026, 10, 10)
        try MoneyStore.add(usd, balance: 100, rate: 18, in: context, mainCurrency: "MXN", now: date(2026, 10, 10), defaults: defaults)
        let more = MoneyAccount(name: "Más dólares", kind: .account, currency: "USD")
        more.createdAt = date(2026, 11, 15)
        XCTAssertTrue(MoneyStore.rateWaits(for: "USD", in: context, now: date(2026, 11, 15)))
        try MoneyStore.add(more, balance: 50, rate: 20, in: context, mainCurrency: "MXN", now: date(2026, 11, 15), defaults: defaults)
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.rateTable["USD"], 18, "Un corte pasado conserva su tipo de cambio")
        XCTAssertEqual(MoneyStore.pendingRates(defaults)["USD"], 20)
        let draft = try MoneyStore.draft(for: "2026-11", in: context, now: date(2026, 11, 30), mainCurrency: "MXN", defaults: defaults)
        XCTAssertEqual(draft.rateTable["USD"], 20, "El próximo corte empieza con el que se escribió")
        XCTAssertTrue(MoneyStore.pendingRates(defaults).isEmpty)
    }

    // MARK: #6 Meses del corte

    func testACutForAPastMonthLeavesOutAccountsCreatedLater_AndKeepsThem() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        nu.createdAt = date(2026, 9, 20)
        try MoneyStore.add(nu, balance: 10_000, rate: nil, in: context, mainCurrency: "MXN", now: date(2026, 9, 20), defaults: defaults)
        let fondo = MoneyAccount(name: "Fondo", kind: .investment, currency: "MXN")
        fondo.createdAt = date(2026, 11, 1)
        try MoneyStore.add(fondo, balance: 50_000, rate: nil, in: context, mainCurrency: "MXN", now: date(2026, 11, 1), defaults: defaults)
        XCTAssertEqual(MoneyStore.suggestedMonths(now: date(2026, 11, 2), latest: "2026-09"), ["2026-10", "2026-11"])
        let october = try MoneyStore.draft(for: "2026-10", in: context, now: date(2026, 11, 2), mainCurrency: "MXN", defaults: defaults)
        XCTAssertNil(october.entry(for: fondo), "Octubre no pide un fondo creado en noviembre")
        for entry in october.entries ?? [] { entry.reviewed = true }
        try MoneyStore.finish(october, in: context, now: date(2026, 11, 2))
        let latest = try XCTUnwrap(MoneyStore.latestCut(in: context))
        XCTAssertEqual(latest.month, "2026-10")
        XCTAssertEqual(latest.entry(for: fondo)?.balance, 50_000, "No se cae del patrimonio")
        XCTAssertEqual(MoneyStore.suggestedMonths(now: date(2026, 11, 2), latest: "2026-11"), ["2026-11"])
    }

    // MARK: #16, #17, #20 Siri y la hoja del presupuesto

    private func expenses() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Expense.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
    }

    func testSiriSaysTheFixedPassTheBudgetInsteadOfOverspent() throws {
        let context = try expenses()
        let now = date(2026, 10, 1)
        let rent = Expense(amount: 13_000, currencyMarker: "$", merchant: "Renta", date: date(2026, 9, 25))
        rent.repeatsMonthly = true  // Next charge: October 25th, still to come.
        context.insert(rent)
        let today = try MonthStatus.todaySentence(in: context, budget: 10_000, now: now, primary: "USD")
        XCTAssertEqual(today, "Tus fijos pasan el presupuesto por $3,000.")
        let line = try XCTUnwrap(MonthStatus.budgetSentence(in: context, budget: 10_000, now: now, primary: "USD"))
        XCTAssertFalse(line.contains("pasaste"), line)
    }

    func testSiriNeverPromisesMoreThanIsLeft() throws {
        let context = try expenses()
        let now = date(2026, 10, 20)
        let rent = Expense(amount: 5_000, currencyMarker: "$", merchant: "Renta", date: date(2026, 9, 25))
        rent.repeatsMonthly = true
        context.insert(rent)
        context.insert(Expense(amount: 6_000, currencyMarker: "$", merchant: "Super", date: date(2026, 10, 5)))
        let line = try XCTUnwrap(MonthStatus.budgetSentence(in: context, budget: 10_000, now: now, primary: "USD"))
        XCTAssertTrue(line.hasPrefix("Te quedan $4,000.00 y faltan $5,000.00 de fijos."), line)
    }

    func testSpentExactlyTheBudgetIsNotMoreThanIt() throws {
        let pace = BudgetPace(budget: 1_000, spent: 1_000, on: date(2026, 10, 20))
        XCTAssertEqual(BudgetStore.dailyPreview(pace, currency: "MXN"), "Este mes ya gastaste justo eso.")
    }
}
