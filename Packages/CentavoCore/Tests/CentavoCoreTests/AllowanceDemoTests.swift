import CentavoCore
import Foundation
import Testing

@Suite("El dibujito de acumular y repartir")
struct AllowanceDemoTests {
    @Test("Se acumula: lo que sobra o falta pasa completo al día siguiente")
    func carry() {
        let demo = AllowanceDemo(mode: .carry)
        #expect(demo.days.map(\.allowance) == [100, 130, 90, 120, 160, 130, 130])
        #expect(demo.moves.first == .init(from: 0, to: [1], each: 30))
        #expect(demo.moves[1] == .init(from: 1, to: [2], each: -10))
        #expect(demo.moves.count == 6)
    }

    @Test("Se reparte: lo que sobra o falta se divide entre los días que quedan")
    func spread() {
        let demo = AllowanceDemo(mode: .spread)
        // $30 left over the first day, shared by 6 days: $5 each.
        #expect(demo.moves.first == .init(from: 0, to: [1, 2, 3, 4, 5, 6], each: 5))
        // The second day overspent $35, shared by 5: −$7 each.
        #expect(demo.moves[1].each == -7)
        #expect(demo.days.map(\.allowance) == [100, 105, 98, 105, 120, 115, 130])
    }

    @Test("Lo que se mueve suma justo lo que sobró, en pesos enteros", arguments: [AllowanceMode.carry, .spread])
    func exact(mode: AllowanceMode) {
        let demo = AllowanceDemo(mode: mode)
        for move in demo.moves {
            #expect(move.each * Decimal(move.to.count) == demo.days[move.from].left)
            #expect(move.each == move.each.rounded(0))
        }
        // The week ends with what the budget left: nothing appears or vanishes on the way.
        #expect(demo.days.last?.left == demo.budget - demo.spent)
    }

    @Test("Con «Se reparte», cada día puede lo que queda entre los días que faltan")
    func spreadMatchesTheRealRule() {
        let demo = AllowanceDemo(mode: .spread)
        var left = demo.budget
        for (index, day) in demo.days.enumerated() {
            #expect(day.allowance == left / Decimal(demo.days.count - index))
            left -= day.spent
        }
    }

    @Test("El último día no pasa nada a nadie")
    func lastDay() {
        #expect(AllowanceDemo(mode: .carry).moves.allSatisfy { $0.from < 6 })
        #expect(AllowanceDemo(mode: .spread).moves.allSatisfy { $0.from < 6 })
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var input = self
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }
}
