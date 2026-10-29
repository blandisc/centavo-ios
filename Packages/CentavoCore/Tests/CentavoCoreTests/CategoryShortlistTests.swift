import Testing
@testable import CentavoCore

@Suite struct CategoryShortlistTests {
    private let offered = ["Despensa", "Comida", "Café", "Transporte", "Servicios", "Ropa", "Salud", "Mascotas"]

    @Test func theSuggestionGoesFirstThenTheMostUsed() {
        let split = CategoryShortlist.split(offered: offered, mostUsed: ["Ropa", "Café", "Despensa"],
                                            pinned: ["Salud"], count: 3)
        #expect(split.shown == ["Salud", "Ropa", "Café", "Despensa"])
        #expect(split.rest == ["Comida", "Transporte", "Servicios", "Mascotas"])
    }

    @Test func withLittleHistoryTheUsualOnesFillIn() {
        let split = CategoryShortlist.split(offered: offered, mostUsed: [], pinned: [], count: 5)
        #expect(split.shown == ["Despensa", "Comida", "Café", "Transporte", "Servicios"])
        #expect(split.rest == ["Ropa", "Salud", "Mascotas"])
    }

    @Test func aPinnedOneIsNotRepeatedAmongTheMostUsed() {
        let split = CategoryShortlist.split(offered: offered, mostUsed: ["ropa", "Café"],
                                            pinned: ["Ropa", ""], count: 2)
        #expect(split.shown == ["Ropa", "Café", "Despensa"])
    }

    @Test func aHiddenCategoryIsNeverShown() {
        let split = CategoryShortlist.split(offered: ["Despensa", "Comida"], mostUsed: ["Café"],
                                            pinned: ["Café"], count: 5)
        #expect(split.shown == ["Despensa", "Comida"])
        #expect(split.rest.isEmpty)
    }
}
