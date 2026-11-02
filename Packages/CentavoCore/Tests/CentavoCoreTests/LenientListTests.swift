import Foundation
import Testing
@testable import CentavoCore

@Suite struct LenientListTests {
    struct Plan: Codable, Equatable { var name: String; var amount: String }

    @Test func oneItemThatDoesNotReadLeavesTheRest() {
        let stored = #"[{"name":"Renta","amount":"9000"},{"name":"Raro"},{"name":"Gym","amount":"500"}]"#
        let read = LenientList.decode(Plan.self, from: stored)
        #expect(read.items == [Plan(name: "Renta", amount: "9000"), Plan(name: "Gym", amount: "500")])
        #expect(read.unread.count == 1)
    }

    @Test func savingAgainKeepsWhatDidNotRead() {
        let stored = #"[{"name":"Renta","amount":"9000"},{"name":"Raro"}]"#
        let items = LenientList.decode(Plan.self, from: stored).items.filter { $0.name != "Renta" }
        let written = LenientList.encode(items, keepingUnreadFrom: stored)
        #expect(LenientList.decode(Plan.self, from: written).items.isEmpty)
        #expect(LenientList.decode(Plan.self, from: written).unread.count == 1, "El renglón ilegible no se pierde")
    }

    @Test func nothingStoredIsAnEmptyList() {
        #expect(LenientList.decode(Plan.self, from: "").items.isEmpty)
        #expect(LenientList.decode([String].self, from: "basura").items.isEmpty)
    }

    @Test func namesReadToo() {
        #expect(LenientList.decode(String.self, from: #"["Comida", 3, "Ropa"]"#).items == ["Comida", "Ropa"])
    }
}
