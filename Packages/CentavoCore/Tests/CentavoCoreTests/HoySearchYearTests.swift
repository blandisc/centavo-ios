import Foundation
import Testing
@testable import CentavoCore

/// The search reads a year (2026-11-18): «uber octubre 2024» is October of 2024, «2024» alone the
/// whole year, and words that ask for nothing ask for nothing.
@Suite struct HoySearchYearTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, month: Int, year: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static let now = day(18, month: 11, year: 2026)

    private func query(_ text: String) -> SearchQuery {
        ExpenseSearch.query(from: text, now: Self.now, calendar: Self.calendar)
    }

    private let expenses = [
        SearchableExpense(merchant: "UBER *TRIP", readableName: "Uber", amount: 250, date: day(12, month: 10, year: 2026)),
        SearchableExpense(merchant: "UBER *TRIP", readableName: "Uber", amount: 120, date: day(3, month: 10, year: 2025)),
        SearchableExpense(merchant: "UBER *TRIP", readableName: "Uber", amount: 300, date: day(20, month: 10, year: 2024)),
        SearchableExpense(merchant: "UBER *TRIP", readableName: "Uber", amount: 80, date: day(2, month: 3, year: 2024)),
        SearchableExpense(merchant: "Liverpool", amount: 2024, date: day(5, month: 6, year: 2026)),
    ]

    private func found(_ text: String) -> [Decimal] {
        let wanted = query(text)
        return expenses.filter { ExpenseSearch.matches($0, wanted) }.map(\.amount)
    }

    @Test func aMonthWithItsYearIsThatMonth() {
        let wanted = query("uber octubre 2024")
        #expect(wanted.words == ["uber"])
        #expect(wanted.year == 2024)
        #expect(wanted.interval == Self.calendar.dateInterval(of: .month, for: Self.day(1, month: 10, year: 2024)))
        #expect(found("uber octubre 2024") == [300])
        #expect(found("uber de octubre de 2025") == [120])
    }

    @Test func aYearAloneIsTheWholeYear() {
        let wanted = query("uber 2024")
        #expect(wanted.words == ["uber"])
        #expect(wanted.interval == Self.calendar.dateInterval(of: .year, for: Self.day(1, month: 1, year: 2024)))
        #expect(found("uber 2024") == [300, 80])
    }

    @Test func aYearStillFindsThatAmount() {
        // «2024» is the year, and the $2,024.00 one too, like «Don Julio» for «julio».
        #expect(found("2024") == [300, 80, 2024])
        // Written as an amount, or after «más de», it is only an amount.
        #expect(query("2,024").year == nil)
        #expect(query("más de 2024").year == nil)
        #expect(query("más de 2024").minAmount == 2024)
    }

    @Test func withoutAYearAMonthIsStillTheLastOneThatCame() {
        #expect(found("uber octubre") == [250])
    }

    @Test func wordsThatAskForNothingAreAnEmptySearch() {
        #expect(query("el").isEmpty)
        #expect(query("de").isEmpty)
        #expect(query("el de la").isEmpty)
    }
}
