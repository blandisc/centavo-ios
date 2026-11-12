import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// 2026-11-11: los saldos iniciales son el punto de partida, no un corte hecho por la persona.
/// El primer «Hacer corte» de ese mes no pregunta por reemplazar, y se compara contra el inicio.
@MainActor
final class MoneyStartingPointTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "MoneyStartingPointTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func date(_ day: Int, month: Int = 11, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @discardableResult
    private func add(_ name: String, _ balance: Decimal, on day: Date, kind: MoneyKind = .account,
                     in context: ModelContext) throws -> MoneyAccount {
        let account = MoneyAccount(name: name, kind: kind, currency: "MXN")
        account.createdAt = day
        try MoneyStore.add(account, balance: balance, rate: nil, in: context, mainCurrency: "MXN", now: day, defaults: defaults)
        return account
    }

    /// Un corte de `month` con estos saldos, terminado en `day`.
    private func cut(_ month: String, on day: Date, _ balances: [(MoneyAccount, Decimal)], replacing: Bool = false,
                     in context: ModelContext) throws {
        let draft = try MoneyStore.draft(for: month, in: context, now: day, mainCurrency: "MXN", defaults: defaults)
        for (account, balance) in balances { draft.entry(for: account)?.balance = balance }
        for entry in draft.entries ?? [] { entry.reviewed = true }
        try MoneyStore.finish(draft, replacing: replacing, in: context, now: day, defaults: defaults)
    }

    // MARK: El hueco

    func testTheFirstCutOfTheStartMonthDoesNotAskToReplace_AndIsComparedWithTheStart() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = try add("Nu", 10_000, on: date(3), in: context)
        let amex = try add("Amex", 2_000, on: date(3, hour: 13), kind: .debt, in: context)
        let cuts = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(MoneyStore.start(among: cuts)?.id, cuts.first?.id, "El corte que hizo la primera cuenta es el inicio")
        XCTAssertEqual(MoneyStore.cutsMade(among: cuts), 0, "El inicio no es un corte hecho")

        // «Hacer corte» ese mismo mes: nunca hubo un corte que reemplazar.
        XCTAssertNoThrow(try cut("2026-11", on: date(20), [(nu, 14_000), (amex, 1_800)], in: context))

        let after = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(after.count, 2, "El inicio se conserva junto al corte del mes")
        let start = try XCTUnwrap(MoneyStore.start(among: after))
        let latest = try XCTUnwrap(MoneyStore.latestCut(in: context))
        XCTAssertEqual(after.first?.id, start.id)
        XCTAssertEqual(after.last?.id, latest.id)
        XCTAssertNotEqual(latest.id, start.id)
        XCTAssertEqual(start.netWorth.total, 8_000, "El punto de partida no cambia")
        XCTAssertEqual(latest.netWorth.total, 12_200)
        XCTAssertEqual(latest.change(since: start), 4_200, "+$4,200 desde el inicio")
        XCTAssertEqual(MoneyStore.cutsMade(among: after), 1, "Corte N.º 001")
        XCTAssertEqual(latest.worthToday([nu, amex]).total, 12_200, "El patrimonio de hoy es el del corte")
    }

    func testASecondCutOfTheSameMonthAsksAndReplacesOnlyTheOneMadeByHand() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = try add("Nu", 10_000, on: date(3), in: context)
        try cut("2026-11", on: date(20), [(nu, 14_000)], in: context)
        let made = try XCTUnwrap(MoneyStore.latestCut(in: context)).date

        XCTAssertThrowsError(try cut("2026-11", on: date(25), [(nu, 15_000)], in: context)) { error in
            XCTAssertEqual(error as? MoneyStore.CutProblem, .monthHasCut(made), "Pregunta por el corte hecho a mano, con su fecha")
        }
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.netWorth.total, 14_000, "Nada cambió sin preguntar")
        // El borrador quedó esperando; con el sí de la persona, reemplaza.
        let draft = try XCTUnwrap(MoneyStore.openDraft(in: context))
        try MoneyStore.finish(draft, replacing: true, in: context, now: date(25), defaults: defaults)

        let cuts = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(cuts.count, 2, "El inicio y un solo corte del mes")
        let start = try XCTUnwrap(MoneyStore.start(among: cuts))
        XCTAssertEqual(start.netWorth.total, 10_000, "Reemplazar el corte nunca borra el inicio")
        XCTAssertEqual(cuts.last?.netWorth.total, 15_000)
        XCTAssertEqual(cuts.last?.change(since: start), 5_000)
    }

    func testAnAccountAddedAfterTheStartInTheSameMonthStartsFromItsFirstBalance() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = try add("Nu", 10_000, on: date(3), in: context)
        let bbva = try add("BBVA", 2_500, on: date(10), in: context)
        let cuts = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(cuts.count, 1)
        XCTAssertNotNil(MoneyStore.start(among: cuts), "Con una cuenta agregada después sigue siendo el inicio")
        XCTAssertEqual(cuts[0].worthToday([nu, bbva]).total, 12_500)

        XCTAssertNoThrow(try cut("2026-11", on: date(20), [(nu, 14_000), (bbva, 2_700)], in: context))
        let after = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(after[1].change(since: after[0]), 4_200, "BBVA cuenta desde su saldo inicial, no como ahorro")

        // Otra más, ya con el corte hecho: entra al corte y no cambia «desde el inicio».
        let fondo = try add("Fondo", 50_000, on: date(22), kind: .investment, in: context)
        let latest = try XCTUnwrap(MoneyStore.latestCut(in: context))
        XCTAssertEqual(latest.id, after[1].id)
        XCTAssertEqual(latest.entry(for: fondo)?.balance, 50_000)
        XCTAssertEqual(latest.change(since: after[0]), 4_200)
        XCTAssertEqual(latest.worthToday([nu, bbva, fondo]).total, 66_700)
    }

    func testNextMonthIsComparedWithTheCutOfTheMonth_NotWithTheStart() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = try add("Nu", 10_000, on: date(3), in: context)
        try cut("2026-11", on: date(20), [(nu, 14_000)], in: context)
        // Diciembre parte del corte de noviembre, no del inicio.
        let december = try MoneyStore.draft(for: "2026-12", in: context, now: date(20, month: 12), mainCurrency: "MXN", defaults: defaults)
        XCTAssertEqual(december.entry(for: nu)?.balance, 14_000)
        XCTAssertEqual(MoneyStore.cut(before: "2026-12", in: context)?.netWorth.total, 14_000)
        december.entry(for: nu)?.balance = 15_000
        december.entry(for: nu)?.reviewed = true
        try MoneyStore.finish(december, in: context, now: date(20, month: 12), defaults: defaults)

        let cuts = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(cuts.map(\.month), ["2026-11", "2026-11", "2026-12"])
        XCTAssertEqual(cuts[2].change(since: cuts[1]), 1_000, "+$1,000 desde nov")
        XCTAssertNotEqual(cuts[1].id, MoneyStore.start(among: cuts)?.id)
        XCTAssertEqual(MoneyStore.cutsMade(among: cuts), 2)
        XCTAssertEqual(cuts[2].shownEntry(for: nu)?.balance, 15_000)
    }

    func testWithoutACutInTheStartMonthNextMonthIsComparedWithTheStart() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = try add("Nu", 10_000, on: date(20), in: context)
        // El 3 de diciembre hace el corte de noviembre: tampoco pregunta.
        XCTAssertNoThrow(try cut("2026-11", on: date(3, month: 12), [(nu, 11_000)], in: context))
        XCTAssertNoThrow(try cut("2026-12", on: date(28, month: 12), [(nu, 12_500)], in: context))
        let cuts = try context.fetch(MoneyCut.finished)
        XCTAssertEqual(cuts.count, 3)
        XCTAssertEqual(cuts[1].change(since: cuts[0]), 1_000, "Noviembre contra el inicio")
        XCTAssertEqual(cuts[2].change(since: cuts[1]), 1_500, "Diciembre contra noviembre")
    }

    func testACutMadeByHandInAnotherMonthStillAsks() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = try add("Nu", 10_000, on: date(3), in: context)
        try cut("2026-12", on: date(20, month: 12), [(nu, 11_000)], in: context)
        XCTAssertThrowsError(try cut("2026-12", on: date(22, month: 12), [(nu, 12_000)], in: context)) { error in
            guard case MoneyStore.CutProblem.monthHasCut = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.netWorth.total, 11_000)
    }

    /// Datos de antes de este cambio: el inicio ya se reemplazó por un corte hecho a mano.
    func testAFirstCutMadeByHandIsNotTakenForTheStart() throws {
        let context = ModelContext(try MoneyStore.inMemory())
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        nu.createdAt = date(3)
        context.insert(nu)
        let made = MoneyCut(month: "2026-11", date: date(20), mainCurrency: "MXN", isDraft: false)
        context.insert(made)
        let line = MoneyEntry(balance: 14_000, account: nu, reviewed: true)
        context.insert(line)
        line.cut = made
        try context.save()
        XCTAssertNil(MoneyStore.start(among: try context.fetch(MoneyCut.finished)))
        XCTAssertThrowsError(try cut("2026-11", on: date(25), [(nu, 15_000)], in: context)) { error in
            XCTAssertEqual(error as? MoneyStore.CutProblem, .monthHasCut(date(20)))
        }
    }

    // MARK: Respaldo

    func testTheStartAndTheCutOfItsMonthTravelInTheBackupAndComeBackTheSame() throws {
        let money = try MoneyStore.inMemory()
        let context = ModelContext(money)
        let nu = try add("Nu", 10_000, on: date(3), in: context)
        try add("BBVA", 2_500, on: date(10), in: context)
        try cut("2026-11", on: date(20), [(nu, 14_000)], in: context)

        let snapshot = try XCTUnwrap(DailyBackup.moneySnapshot(money))
        XCTAssertEqual(snapshot.cuts.count, 2)
        let elsewhere = try MoneyStore.inMemory()
        try DailyBackup.restoreMoney(snapshot, into: elsewhere)
        XCTAssertEqual(try XCTUnwrap(DailyBackup.moneySnapshot(elsewhere)).cuts.map(\.id), snapshot.cuts.map(\.id),
                       "Los dos cortes del mes vuelven, el inicio primero")

        let back = ModelContext(elsewhere)
        let cuts = try back.fetch(MoneyCut.finished)
        let start = try XCTUnwrap(MoneyStore.start(among: cuts), "Restaurado, el inicio sigue siendo el inicio")
        let latest = try XCTUnwrap(MoneyStore.latestCut(in: back))
        XCTAssertEqual(start.netWorth.total, 12_500)
        XCTAssertEqual(latest.netWorth.total, 16_500)
        XCTAssertEqual(latest.change(since: start), 4_000)
        // Y otro corte ese mes pregunta, como antes de restaurar.
        let draft = try MoneyStore.draft(for: "2026-11", in: back, now: date(25), mainCurrency: "MXN", defaults: defaults)
        for entry in draft.entries ?? [] { entry.reviewed = true }
        XCTAssertThrowsError(try MoneyStore.finish(draft, in: back, now: date(25), defaults: defaults))
    }

    func testRestoringABackupWithOnlyTheStartStillDoesNotAsk() throws {
        let money = try MoneyStore.inMemory()
        try add("Nu", 10_000, on: date(3), in: ModelContext(money))
        let snapshot = try XCTUnwrap(DailyBackup.moneySnapshot(money))
        let elsewhere = try MoneyStore.inMemory()
        try DailyBackup.restoreMoney(snapshot, into: elsewhere)
        let back = ModelContext(elsewhere)
        let draft = try MoneyStore.draft(for: "2026-11", in: back, now: date(20), mainCurrency: "MXN", defaults: defaults)
        for entry in draft.entries ?? [] { entry.reviewed = true }
        XCTAssertNoThrow(try MoneyStore.finish(draft, in: back, now: date(20), defaults: defaults))
        XCTAssertEqual(try back.fetch(MoneyCut.finished).count, 2)
    }
}
