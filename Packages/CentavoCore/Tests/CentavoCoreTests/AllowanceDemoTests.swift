import CentavoCore
import Foundation
import Testing

@Suite("El dibujito de acumular y repartir")
struct AllowanceDemoTests {
    @Test("Se acumula: lo que sobra o falta pasa completo al día siguiente")
    func carry() {
        let demo = AllowanceDemo(mode: .carry)
        #expect(demo.days.map(\.allowance) == [100, 140, 110, 120, 180, 160, 160])
        #expect(demo.moves.first == .init(from: 0, to: [1], each: 40))
        #expect(demo.moves[1] == .init(from: 1, to: [2], each: 10))
        #expect(demo.moves.count == 6)
    }

    @Test("Se reparte: lo que sobra o falta se divide entre los días que quedan")
    func spread() {
        let demo = AllowanceDemo(mode: .spread)
        // $40 left over the first day, shared by 6 days: $7 each.
        #expect(demo.moves.first == .init(from: 0, to: [1, 2, 3, 4, 5, 6], each: 7))
        #expect(demo.days[1].allowance == 107)
        // The second day overspent $23, shared by 5: −$5 each.
        #expect(demo.moves[1].each == -5)
        #expect(demo.days[2].allowance == 102)
    }

    @Test("El último día no pasa nada a nadie")
    func lastDay() {
        #expect(AllowanceDemo(mode: .carry).moves.allSatisfy { $0.from < 6 })
        #expect(AllowanceDemo(mode: .spread).moves.allSatisfy { $0.from < 6 })
    }
}
