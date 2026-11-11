import Foundation
import Testing
@testable import CentavoCore

/// Las copias de un gasto fijo ya detenido no cuentan como el cobro de otro fijo igual (2026-11-11).
@Suite("Copias de gastos fijos")
struct FixedCopiesTests {
    @Test("Un fijo detenido se reconoce porque es copia de sí mismo")
    func stoppedOnesAreCopiesOfThemselves() {
        let rows: [(fixedID: String?, fixedOf: String?)] = [
            (fixedID: "netflix-viejo", fixedOf: "netflix-viejo"),   // the stopped original
            (fixedID: "copia-1", fixedOf: "netflix-viejo"),         // one of its copies
            (fixedID: "copia-2", fixedOf: "renta"),                 // a copy of one that still repeats
            (fixedID: nil, fixedOf: nil),                           // from before ids
            (fixedID: "suelto", fixedOf: nil),
        ]
        #expect(FixedCopies.stoppedIDs(rows) == ["netflix-viejo"])
    }

    @Test("Las copias de un fijo detenido no se toman por el cobro de otro")
    func copiesOfAStoppedOneStandInForNothing() {
        let active: Set = ["renta"], stopped: Set = ["netflix-viejo"]
        #expect(FixedCopies.kind(fixedOf: "netflix-viejo", active: active, stopped: stopped) == .stopped)
        #expect(FixedCopies.kind(fixedOf: "renta", active: active, stopped: stopped) == .of("renta"))
    }

    @Test("Las copias de antes de los ids, y las de un id que nadie conoce aquí, se siguen comparando")
    func legacyCopiesStillMatch() {
        #expect(FixedCopies.kind(fixedOf: nil, active: ["renta"], stopped: []) == .legacy)
        // Two devices gave the same old original an id each and the other's won.
        #expect(FixedCopies.kind(fixedOf: "id-que-perdio", active: ["renta"], stopped: ["otro"]) == .legacy)
    }

    @Test("Si el original volvió a repetirse en otro dispositivo, sus copias cuentan")
    func anActiveIDWinsOverAStoppedOne() {
        #expect(FixedCopies.kind(fixedOf: "renta", active: ["renta"], stopped: ["renta"]) == .of("renta"))
    }
}
