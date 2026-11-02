import CentavoCore
import Foundation
import Testing

@Suite("El candado de «Mi dinero»")
struct MoneyPrivacyTests {
    @Test("Una respuesta de Face ID abre solo si nada bloqueó mientras tanto")
    func gate() {
        var gate = UnlockGate()
        let started = gate.generation
        #expect(gate.opens(granted: true, started: started, stillVisible: true))
        #expect(!gate.opens(granted: false, started: started, stillVisible: true))
        // Back to «Hoy» before the answer: it doesn't open.
        #expect(!gate.opens(granted: true, started: started, stillVisible: false))
        gate.lock()
        #expect(!gate.opens(granted: true, started: started, stillVisible: true))
        #expect(gate.opens(granted: true, started: gate.generation, stillVisible: true))
    }

    @Test("Dice cara, huella o código según el iPhone")
    func words() {
        #expect(UnlockMethod.faceID.title.contains("cara"))
        #expect(UnlockMethod.touchID.title.contains("huella"))
        #expect(UnlockMethod.passcode.title.contains("código"))
        #expect(!UnlockMethod.touchID.points.joined().contains("Face ID"))
        #expect(!UnlockMethod.passcode.points.joined().contains("cara"))
        #expect(UnlockMethod.none.points.joined().contains("sin pedir nada"))
        #expect(UnlockMethod.faceID.symbol == "faceid")
        #expect(UnlockMethod.touchID.symbol == "touchid")
    }

    @Test("Los renglones por revisar dicen que no se agregan, con su plural")
    func waiting() {
        #expect(MoneyWords.waitingLeftOut(0) == nil)
        #expect(MoneyWords.waitingLeftOut(1) == "1 por revisar no se agrega. Complétala antes de guardar o agrégala después a mano.")
        #expect(MoneyWords.waitingLeftOut(3) == "3 por revisar no se agregan. Complétalas antes de guardar o agrégalas después a mano.")
    }

    @Test("Los tipos de cambio revisados se guardan y se leen igual")
    func codes() {
        #expect(MoneyWords.encodeCodes(["USD", "EUR"]) == "EUR,USD")
        #expect(MoneyWords.decodeCodes("EUR,USD") == ["EUR", "USD"])
        #expect(MoneyWords.decodeCodes("") == [])
        #expect(MoneyWords.decodeCodes(nil) == [])
        #expect(MoneyWords.decodeCodes(MoneyWords.encodeCodes([])) == [])
    }
}

@Suite("Editar un ingreso de «Mi dinero»")
struct MoneyIncomeRuleTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test("Un aumento en otro mes empieza otra versión; en el mismo mes se corrige")
    func versions() {
        let since = day(2026, 9, 1)
        #expect(MoneyIncomeRule.startsNewVersion(oldAmount: 30000, oldCurrency: "MXN", since: since,
                                                 newAmount: 32000, newCurrency: "MXN", now: day(2026, 11, 2), calendar: calendar))
        #expect(!MoneyIncomeRule.startsNewVersion(oldAmount: 30000, oldCurrency: "MXN", since: day(2026, 11, 1),
                                                  newAmount: 32000, newCurrency: "MXN", now: day(2026, 11, 2), calendar: calendar))
        #expect(!MoneyIncomeRule.startsNewVersion(oldAmount: 30000, oldCurrency: "MXN", since: since,
                                                  newAmount: 30000, newCurrency: "MXN", now: day(2026, 11, 2), calendar: calendar))
        #expect(MoneyIncomeRule.startsNewVersion(oldAmount: 30000, oldCurrency: "MXN", since: since,
                                                 newAmount: 30000, newCurrency: "USD", now: day(2026, 11, 2), calendar: calendar))
    }
}
