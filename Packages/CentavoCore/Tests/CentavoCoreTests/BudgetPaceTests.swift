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

    @Test func theRestSpreadsOverTheDaysLeftTodayIncluded() throws {
        // October 12th: 20 days left (12…31). 6,906.50 / 20 = 345.33 → 345.
        let pace = try #require(makePace(budget: 8000, spent: Decimal(string: "1093.50")!,
                                         on: Self.day(2026, 10, 12)))
        #expect(pace.daysLeft == 20)
        #expect(pace.dailyAllowance == 345)
    }

    @Test func theLastDayGetsAllThatIsLeft() throws {
        let pace = try #require(makePace(budget: 1000, spent: 400, on: Self.day(2026, 10, 31)))
        #expect(pace.daysLeft == 1)
        #expect(pace.dailyAllowance == 600)
    }

    @Test func aBlownBudgetLeavesNothingPerDay() throws {
        let pace = try #require(makePace(budget: 1000, spent: 1500, on: Self.day(2026, 10, 5)))
        #expect(pace.dailyAllowance == 0)
    }
}

/// What today spent comes off today, not off the rest of the month (audit 2026-10-22, #3).
@Suite struct BudgetPaceTodayTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func pace(spent: Decimal, today: Decimal, reserved: Decimal = 0, on date: Date) -> BudgetPace? {
        BudgetPace(budget: 9300, spent: spent, spentToday: today, reserved: reserved,
                   on: date, calendar: Self.calendar)
    }

    @Test func theDayStartsWithItsShare() throws {
        // October 22nd: 10 days left. (9,300 − 3,000) / 10 = 630.
        let pace = try #require(pace(spent: 3000, today: 0, on: Self.day(22)))
        #expect(pace.daysLeft == 10)
        #expect(pace.dailyAllowance == 630)
    }

    @Test func spendingTodayComesOffToday() throws {
        // Spending all of it leaves nothing for today (it used to say $567).
        let spentIt = try #require(pace(spent: 3630, today: 630, on: Self.day(22)))
        #expect(spentIt.dailyAllowance == 0)
        let some = try #require(pace(spent: Decimal(string: "3047.50")!, today: Decimal(string: "47.50")!,
                                     on: Self.day(22)))
        #expect(some.dailyAllowance == 582)
        #expect(some.todayShare == 630)
    }

    @Test func spendingPastTodaysShareShowsZeroNotLess() throws {
        let pace = try #require(pace(spent: 4000, today: 1000, on: Self.day(22)))
        #expect(pace.dailyAllowance == 0)
        #expect(pace.remaining == 5300)
    }

    @Test func tomorrowStartsOverWithWhatWentBeforeIt() throws {
        // The 630 of the 22nd is now "before today": (9,300 − 3,630) / 9 = 630.
        let tomorrow = try #require(pace(spent: 3630, today: 0, on: Self.day(23, hour: 0)))
        #expect(tomorrow.daysLeft == 9)
        #expect(tomorrow.dailyAllowance == 630)
        // Spending 1,000 on the 22nd instead leaves less for each day after.
        let after = try #require(pace(spent: 4000, today: 0, on: Self.day(23)))
        #expect(after.dailyAllowance == 588)
    }

    @Test func fixedExpensesAreSetApartBeforeTodaysShare() throws {
        // (9,300 − 3,000 − 1,300) / 10 = 500, minus 200 today.
        let pace = try #require(pace(spent: 3200, today: 200, reserved: 1300, on: Self.day(22)))
        #expect(pace.dailyAllowance == 300)
        #expect(pace.free == 4800)
    }

    @Test func aRefundTodayGivesTodayBack() throws {
        let pace = try #require(pace(spent: 2900, today: -100, on: Self.day(22)))
        #expect(pace.dailyAllowance == 730)
    }

    @Test func freeIsWhatIsLeftAfterTheFixedOnesAndNeverNegative() throws {
        let pace = try #require(pace(spent: 9000, today: 0, reserved: 500, on: Self.day(22)))
        #expect(pace.remaining == 300)
        #expect(pace.free == 0)
    }

    @Test func todayIsTheDayOfTheDateInTheMainCurrency() {
        let amounts = [
            ExpenseAmount(value: 3000, currencyMarker: "MXN", date: Self.day(21)),
            ExpenseAmount(value: 600, currencyMarker: "$", date: Self.day(22, hour: 0)),
            ExpenseAmount(value: 30, currencyMarker: "MXN", date: Self.day(22, hour: 23)),
            ExpenseAmount(value: 20, currencyMarker: "USD", date: Self.day(22)),
            ExpenseAmount(value: 99, currencyMarker: "MXN", date: Self.day(23, hour: 0)),
        ]
        let today = MonthSummarizer.dayTotal(amounts, onDayOf: Self.day(22), primary: "MXN",
                                             calendar: Self.calendar)
        #expect(today == 630)
    }
}
