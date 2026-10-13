import Foundation
import Testing
@testable import CentavoCore

@Suite struct BudgetPaceTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makePace(budget: Decimal?, spent: Decimal, on date: Date) -> BudgetPace? {
        BudgetPace(budget: budget, spent: spent, on: date, calendar: Self.calendar)
    }

    @Test func spreadsTheBudgetEvenlyOverTheDaysOfTheMonth() throws {
        // October has 31 days; by the 12th an even spend has reached 12/31 of 8,000.
        let pace = try #require(makePace(budget: 8000, spent: Decimal(string: "1093.50")!,
                                     on: Self.day(2026, 10, 12)))
        #expect(pace.expectedToDate == Decimal(string: "3096.77"))
        #expect(pace.remaining == Decimal(string: "6906.50"))
        #expect(abs(pace.paceFraction - 12.0 / 31.0) < 0.0001)
        #expect(abs(pace.spentFraction - 1093.5 / 8000.0) < 0.0001)
        #expect(!pace.isOverBudget)
    }

    @Test func theLastDayExpectsTheWholeBudget() throws {
        let pace = try #require(makePace(budget: 8000, spent: 0, on: Self.day(2026, 10, 31)))
        #expect(pace.expectedToDate == 8000)
        #expect(pace.paceFraction == 1)
    }

    @Test func februaryHasItsOwnLength() throws {
        let leap = try #require(makePace(budget: 2900, spent: 0, on: Self.day(2028, 2, 10)))
        #expect(leap.expectedToDate == 1000)
        let common = try #require(makePace(budget: 2800, spent: 0, on: Self.day(2027, 2, 10)))
        #expect(common.expectedToDate == 1000)
    }

    @Test func overspendingPassesTheBudgetAndHoldsTheBarAtFull() throws {
        let pace = try #require(makePace(budget: 1000, spent: 1250, on: Self.day(2026, 10, 20)))
        #expect(pace.isOverBudget)
        #expect(pace.remaining == -250)
        #expect(pace.spentFraction == 1)
    }

    @Test func refundsThatOutweighTheMonthNeverMakeTheBarNegative() throws {
        let pace = try #require(makePace(budget: 1000, spent: -200, on: Self.day(2026, 10, 20)))
        #expect(pace.spentFraction == 0)
        #expect(pace.remaining == 1200)
        #expect(!pace.isOverBudget)
    }

    @Test func noBudgetMeansNothingToMeasure() {
        #expect(makePace(budget: nil, spent: 100, on: Self.day(2026, 10, 12)) == nil)
        #expect(makePace(budget: 0, spent: 100, on: Self.day(2026, 10, 12)) == nil)
        #expect(makePace(budget: -500, spent: 100, on: Self.day(2026, 10, 12)) == nil)
    }
}
