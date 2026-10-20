import Foundation
import Testing
@testable import CentavoCore

@Suite struct ExpenseSearchTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, month: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static let now = day(19, month: 10)

    private func query(_ text: String) -> SearchQuery {
        ExpenseSearch.query(from: text, now: Self.now, calendar: Self.calendar)
    }

    private let expenses = [
        SearchableExpense(merchant: "UBER *TRIP", readableName: "Uber", category: "Transporte",
                          card: "Nu", amount: 250, date: day(12, month: 10)),
        SearchableExpense(merchant: "UBER *TRIP", readableName: "Uber", category: "Transporte",
                          card: "Nu", amount: 120, date: day(3, month: 10)),
        SearchableExpense(merchant: "UBER *TRIP", readableName: "Uber", category: "Transporte",
                          card: "Nu", amount: 300, date: day(20, month: 9)),
        SearchableExpense(merchant: "Starbucks", category: "Café", amount: 65, date: day(18, month: 10)),
        SearchableExpense(merchant: "Taquería Don Julio", category: "Comida", amount: 180, date: day(5, month: 10)),
    ]

    private func found(_ text: String) -> [Decimal] {
        let wanted = query(text)
        return expenses.filter { ExpenseSearch.matches($0, wanted) }.map(\.amount)
    }

    @Test func readsTheExampleFromThePitch() {
        let wanted = query("uber de octubre arriba de 200")
        #expect(wanted.words == ["uber"])
        #expect(wanted.minAmount == 200)
        #expect(wanted.interval == Self.calendar.dateInterval(of: .month, for: Self.day(1, month: 10)))
        #expect(found("uber de octubre arriba de 200") == [250])
    }

    @Test func searchesNamesCategoriesAndCards() {
        #expect(found("uber") == [250, 120, 300])
        #expect(found("uber de octubre") == [250, 120])
        #expect(found("café") == [65])
        #expect(found("transporte septiembre") == [300])
        #expect(found("nu menos de 200") == [120])
        #expect(found("rappi").isEmpty)
        #expect(found("250") == [250])
        #expect(found("desde 250") == [250, 300])
        #expect(found("hasta 120") == [120, 65])
        #expect(found("don julio") == [180])
        #expect(query("1,250").words == ["1250"])
    }

    @Test func aMonthStillToComeIsLastYears() {
        let wanted = query("diciembre")
        #expect(wanted.interval == Self.calendar.dateInterval(of: .month, for: Self.day(1, month: 12, year: 2025)))
    }

    @Test func aCategoryTheModelPickedFiltersByIt() {
        var wanted = query("cafecitos")
        #expect(found("cafecitos").isEmpty)
        wanted.category = "Café"
        #expect(expenses.filter { ExpenseSearch.matches($0, wanted) }.map(\.amount) == [65])
    }
}

@Suite struct WalletNoticeRescueTests {
    private let notice = "Banco Azteca\nCompra aprobada en FARMACIA SAN JORGE por MXN 245.00"

    @Test func trustsWhatIsLiterallyInTheNotice() throws {
        let rescued = try #require(WalletNotice.rescue(notice, merchant: "FARMACIA SAN JORGE",
                                                       card: "Banco Azteca", amountFragment: "MXN 245.00"))
        #expect(rescued.amount == ParsedAmount(value: 245, currencyMarker: "MXN"))
        #expect(rescued.merchant == "FARMACIA SAN JORGE")
        #expect(rescued.card == "Banco Azteca")
    }

    @Test func rejectsWhatIsNotThere() {
        #expect(WalletNotice.rescue(notice, merchant: "FARMACIA SAN JORGE", card: nil, amountFragment: "MXN 254.00") == nil)
        #expect(WalletNotice.rescue(notice, merchant: "Farmacias Guadalajara", card: nil, amountFragment: "MXN 245.00") == nil)
        #expect(WalletNotice.rescue(notice, merchant: "FARMACIA SAN JORGE", card: nil, amountFragment: "245") == nil)
        #expect(WalletNotice.rescue(notice, merchant: "FARMACIA SAN JORGE", card: nil, amountFragment: "MXN 24") == nil)
        // The card named as the shop is the old mix-up.
        #expect(WalletNotice.rescue(notice, merchant: "Banco Azteca", card: "Banco Azteca", amountFragment: "MXN 245.00") == nil)
        let incoming = "Recibiste MXN 500.00 de Ana López"
        #expect(WalletNotice.rescue(incoming, merchant: "Ana López", card: nil, amountFragment: "MXN 500.00") == nil)
    }

    @Test func aRefundSubtracts() throws {
        let refund = "Reembolso de MXN 245.00 en FARMACIA SAN JORGE"
        let rescued = try #require(WalletNotice.rescue(refund, merchant: "FARMACIA SAN JORGE", card: "Tarjeta X",
                                                       amountFragment: "MXN 245.00"))
        #expect(rescued.amount.value == -245)
        #expect(rescued.amountText == "-MXN 245.00")
        #expect(rescued.card == nil)
    }
}
