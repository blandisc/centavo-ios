import Foundation
import Testing
@testable import CentavoCore

@Suite struct MonthNavigatorTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    private let now = MonthNavigatorTests.date(2026, 10, 13)

    private func offset(oldest: Date?) -> Int {
        MonthNavigator.earliestOffset(oldest: oldest, now: now, calendar: Self.calendar)
    }

    @Test func withNothingOlderYouStayOnThisMonth() {
        #expect(offset(oldest: nil) == 0)
        #expect(offset(oldest: Self.date(2026, 10, 1, 0, 0)) == 0)
        #expect(offset(oldest: Self.date(2026, 10, 13)) == 0)
    }

    @Test func youCanGoBackAsFarAsTheOldestExpense() {
        #expect(offset(oldest: Self.date(2026, 9, 30, 23, 59)) == -1)
        #expect(offset(oldest: Self.date(2026, 7, 4)) == -3)
        #expect(offset(oldest: Self.date(2025, 10, 13)) == -12)
    }

    @Test func crossingAYearBoundaryCountsMonthsNotYears() {
        let january = MonthNavigatorTests.date(2027, 1, 20)
        #expect(MonthNavigator.earliestOffset(oldest: Self.date(2026, 11, 5), now: january,
                                              calendar: Self.calendar) == -2)
    }

    @Test func anExpenseDatedInTheFutureNeverPushesTheLimitForward() {
        #expect(offset(oldest: Self.date(2027, 3, 1)) == 0)
    }

    @Test func stepsBackAcrossTheStartOfTheYear() {
        let january = Self.date(2027, 1, 15)
        let december = MonthNavigator.month(offsetBy: -1, from: january, calendar: Self.calendar)
        #expect(Self.calendar.component(.month, from: december) == 12)
        #expect(Self.calendar.component(.year, from: december) == 2026)
    }

    @Test func stepsBackFromTheEndOfALongMonthIntoAShortOne() {
        // 31 Oct minus a month has no 31 Sep: it must land inside September, not skip to October.
        let back = MonthNavigator.month(offsetBy: -1, from: Self.date(2026, 10, 31),
                                        calendar: Self.calendar)
        #expect(Self.calendar.component(.month, from: back) == 9)
    }

    @Test func theClosingMomentIsTheLastSecondOfTheMonth() {
        let closing = MonthNavigator.closingMoment(of: Self.date(2026, 9, 10), calendar: Self.calendar)
        #expect(closing == Self.date(2026, 9, 30, 23, 59, 59))
        let february = MonthNavigator.closingMoment(of: Self.date(2028, 2, 3), calendar: Self.calendar)
        #expect(Self.calendar.component(.day, from: february) == 29)
        let december = MonthNavigator.closingMoment(of: Self.date(2026, 12, 1), calendar: Self.calendar)
        #expect(december == Self.date(2026, 12, 31, 23, 59, 59))
    }

    @Test func aBudgetMeasuredAtTheClosingMomentExpectsAllOfIt() throws {
        let closing = MonthNavigator.closingMoment(of: Self.date(2026, 9, 10), calendar: Self.calendar)
        let pace = try #require(BudgetPace(budget: 8000, spent: 6420, on: closing,
                                           calendar: Self.calendar))
        #expect(pace.expectedToDate == 8000)
        #expect(pace.paceFraction == 1)
        #expect(pace.remaining == 1580)
    }

    @Test func sameMonthIsByMonthAndYearNotJustMonth() {
        #expect(MonthNavigator.isSameMonth(Self.date(2026, 10, 1), as: Self.date(2026, 10, 31),
                                           calendar: Self.calendar))
        #expect(!MonthNavigator.isSameMonth(Self.date(2025, 10, 13), as: Self.date(2026, 10, 13),
                                            calendar: Self.calendar))
    }
}
