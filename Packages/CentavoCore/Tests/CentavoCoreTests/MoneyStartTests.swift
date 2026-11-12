import Foundation
import Testing
@testable import CentavoCore

/// 2026-11-11: los saldos iniciales son el punto de partida, no un corte hecho por la persona.
@Suite struct MoneyStartTests {
    private let day = Date(timeIntervalSince1970: 1_794_000_000)

    private func cut(_ id: String, _ month: String, at date: Date, accounts: [Date]) -> MoneyStart.Cut<String> {
        MoneyStart.Cut(id: id, month: month, date: date, accountsCreated: accounts)
    }

    @Test func theCutMadeWithTheFirstAccountIsTheStart() {
        // La cuenta se crea un instante antes del corte que la recibe.
        #expect(MoneyStart.isStart(cutDate: day, accountsCreated: [day.addingTimeInterval(-0.01)]))
        // Las que se agregan después, ese mes o el siguiente, son más nuevas que el corte.
        #expect(MoneyStart.isStart(cutDate: day, accountsCreated: [day, day.addingTimeInterval(86_400 * 20)]))
    }

    @Test func aCutMadeByHandIsNotTheStart() {
        // Se terminó minutos después de escribir sus cuentas.
        #expect(!MoneyStart.isStart(cutDate: day, accountsCreated: [day.addingTimeInterval(-600), day.addingTimeInterval(-300)]))
        // Aunque después reciba una cuenta nueva.
        #expect(!MoneyStart.isStart(cutDate: day, accountsCreated: [day.addingTimeInterval(-600), day.addingTimeInterval(900)]))
    }

    @Test func onlyTheFirstCutCanBeTheStart() {
        let start = cut("inicio", "2026-11", at: day, accounts: [day])
        let made = cut("corte", "2026-11", at: day.addingTimeInterval(3_600), accounts: [day])
        let december = cut("dic", "2026-12", at: day.addingTimeInterval(86_400 * 30), accounts: [day])
        #expect(MoneyStart.start(among: [december, made, start]) == "inicio")
        // Sin el inicio (se reemplazó antes de este cambio), ninguno lo es.
        #expect(MoneyStart.start(among: [december, made]) == nil)
        #expect(MoneyStart.start(among: [MoneyStart.Cut<String>]()) == nil)
    }

    @Test func theFirstCutOfTheStartMonthReplacesNothing() {
        let start = cut("inicio", "2026-11", at: day, accounts: [day])
        #expect(MoneyStart.replaced(byACutOf: "2026-11", among: [start]).isEmpty)
    }

    @Test func aSecondCutOfTheSameMonthReplacesTheOneMadeByHand_NeverTheStart() {
        let start = cut("inicio", "2026-11", at: day, accounts: [day])
        let made = cut("corte", "2026-11", at: day.addingTimeInterval(3_600), accounts: [day])
        #expect(MoneyStart.replaced(byACutOf: "2026-11", among: [start, made]).map(\.id) == ["corte"])
        #expect(MoneyStart.replaced(byACutOf: "2026-12", among: [start, made]).isEmpty)
    }

    @Test func aCutMadeByHandInAnotherMonthStillAsks() {
        let start = cut("inicio", "2026-11", at: day, accounts: [day])
        let december = cut("dic", "2026-12", at: day.addingTimeInterval(86_400 * 30), accounts: [day])
        #expect(MoneyStart.replaced(byACutOf: "2026-12", among: [start, december]).map(\.id) == ["dic"])
    }

    @Test func aFirstCutMadeByHandAsksAsBefore() {
        // Datos de antes: el inicio ya se reemplazó por un corte hecho a mano.
        let made = cut("corte", "2026-10", at: day, accounts: [day.addingTimeInterval(-86_400)])
        #expect(MoneyStart.replaced(byACutOf: "2026-10", among: [made]).map(\.id) == ["corte"])
    }

    @Test func theStartIsNotCountedAsACut() {
        let start = cut("inicio", "2026-11", at: day, accounts: [day])
        let made = cut("corte", "2026-11", at: day.addingTimeInterval(3_600), accounts: [day])
        #expect(MoneyStart.cutsMade(among: [start]) == 0)
        #expect(MoneyStart.cutsMade(among: [start, made]) == 1)
        #expect(MoneyStart.cutsMade(among: [made]) == 1)
    }

    /// «Desde el inicio»: lo que cambió entre los saldos iniciales y el primer corte, con una
    /// cuenta agregada después del inicio en el mismo mes (su saldo inicial es su punto de partida).
    @Test func theFirstCutIsComparedWithTheStart() {
        func mxn(_ value: Decimal) -> MoneyLine { MoneyLine(kind: .account, currency: "MXN", balance: value) }
        let start = MoneyChange.Cut(lines: ["nu": mxn(10_000), "bbva": mxn(2_500)], main: "MXN", rates: [:])
        let made = MoneyChange.Cut(lines: ["nu": mxn(14_000), "bbva": mxn(2_700)], main: "MXN", rates: [:])
        #expect(MoneyChange.since(previous: start, latest: made, counting: ["nu", "bbva"]) == 4_200)
    }
}
