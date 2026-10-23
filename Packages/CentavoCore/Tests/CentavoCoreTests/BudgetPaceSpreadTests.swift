import Foundation
import Testing
@testable import CentavoCore

/// «Repartir»: what is left is spread over the days still to come and what today spent comes
/// off today (the rule of PR #94, kept as the second choice in the budget sheet).
@Suite struct BudgetPaceSpreadTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func pace(budget: Decimal = 9300, spent: Decimal, today: Decimal = 0, fixed: Decimal = 0,
                      fixedToday: Decimal = 0, reserved: Decimal = 0, on date: Date) -> BudgetPace? {
        BudgetPace(budget: budget, spent: spent, spentToday: today, fixedSpent: fixed, fixedToday: fixedToday,
                   reserved: reserved, mode: .spread, on: date, calendar: Self.calendar)
    }

    @Test func theDayStartsWithItsShareOfWhatIsLeft() throws {
        // October 22nd: 10 days left. (9,300 − 3,000) / 10 = 630.
        let pace = try #require(pace(spent: 3000, on: Self.day(22)))
        #expect(pace.mode == .spread)
        #expect(pace.daysLeft == 10)
        #expect(pace.dailyAllowance == 630)
    }

    @Test func spendingTodayComesOffToday() throws {
        let spentIt = try #require(pace(spent: 3630, today: 630, on: Self.day(22)))
        #expect(spentIt.dailyAllowance == 0)
        let some = try #require(pace(spent: Decimal(string: "3047.50")!, today: Decimal(string: "47.50")!,
                                     on: Self.day(22)))
        #expect(some.dailyAllowance == 582)
        #expect(some.todayShare == 630)
    }

    @Test func goingPastTodaysShareShowsZeroNotLess() throws {
        let pace = try #require(pace(spent: 4000, today: 1000, on: Self.day(22)))
        #expect(pace.dailyAllowance == 0)
        #expect(!pace.isOverToday)
    }

    @Test func whatADayLeavesIsSpreadOverTheRestNotGivenToTomorrow() throws {
        // The 630 of the 22nd is now before today: (9,300 − 3,630) / 9 = 630.
        let tomorrow = try #require(pace(spent: 3630, on: Self.day(23, hour: 0)))
        #expect(tomorrow.dailyAllowance == 630)
        // Spending 1,000 on the 22nd leaves less for every day after, not 370 less tomorrow.
        let after = try #require(pace(spent: 4000, on: Self.day(23)))
        #expect(after.dailyAllowance == 588)
    }

    @Test func fixedExpensesStillToComeAreSetApart() throws {
        // (9,300 − 3,000 − 1,300) / 10 = 500, minus 200 today.
        let pace = try #require(pace(spent: 3200, today: 200, reserved: 1300, on: Self.day(22)))
        #expect(pace.dailyAllowance == 300)
    }

    @Test func aFixedExpenseChargedTodayDoesNotEatTodaysShare() throws {
        // Rent of 1,300 was still to come when the 22nd began, and it was charged today:
        // (9,300 − 3,000 − 1,300) / 10 = 500, and today has spent nothing of its own.
        let pace = try #require(pace(spent: 4300, today: 1300, fixed: 1300, fixedToday: 1300, on: Self.day(22)))
        #expect(pace.dailyAllowance == 500)
        #expect(pace.variableToday == 0)
    }

    @Test func aRefundTodayGivesTodayBack() throws {
        let pace = try #require(pace(spent: 2900, today: -100, on: Self.day(22)))
        #expect(pace.dailyAllowance == 730)
    }

    @Test func podriasLlevarIsTheBudgetSpreadEvenly() throws {
        // 8,000 × 12 / 31 = 3,096.77; spent 1,093.50, so 2,003.27 under.
        let pace = try #require(pace(budget: 8000, spent: Decimal(string: "1093.50")!, on: Self.day(12)))
        #expect(pace.expectedToDate == Decimal(string: "3096.77"))
        #expect(pace.carriedOver == Decimal(string: "2003.27"))
        #expect(pace.dailyAllowance == 345)
    }

    @Test func theSameMonthGivesDifferentDaysInEachMode() throws {
        // $700 a day in November: spend 300 on the 1st.
        let calendar = Self.calendar
        let second = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let carry = try #require(BudgetPace(budget: 21_000, spent: 300, on: second, calendar: calendar))
        let spread = try #require(BudgetPace(budget: 21_000, spent: 300, mode: .spread, on: second, calendar: calendar))
        #expect(carry.dailyAllowance == 1_100)
        // (21,000 − 300) / 29 = 713.79.
        #expect(spread.dailyAllowance == 713)
    }

    @Test func anUnknownStoredChoiceIsCarry() {
        #expect(AllowanceMode(stored: nil) == .carry)
        #expect(AllowanceMode(stored: "") == .carry)
        #expect(AllowanceMode(stored: "repartir") == .spread)
        #expect(AllowanceMode(stored: "acumular") == .carry)
    }
}
