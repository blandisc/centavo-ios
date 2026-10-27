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

    @Test func pastTheRuleItSaysDeberias() throws {
        // By the 12th an even month is at 3,096.77: «Podrías llevar» under it, «Deberías» over.
        let under = try #require(makePace(budget: 8000, spent: 3000, on: Self.day(2026, 10, 12)))
        #expect(!under.isAheadOfPace)
        let over = try #require(makePace(budget: 8000, spent: 3100, on: Self.day(2026, 10, 12)))
        #expect(over.isAheadOfPace)
    }

    @Test func theBarSubtractsToTheFigureItStates() throws {
        // 3,096.77 − 2,757.40 = 339.37: rounded one by one, $3,097 − $2,757 read $340 next to
        // «Hoy puedes gastar $339». «Podrías llevar» is «Llevas» plus the figure instead.
        let carry = try #require(makePace(budget: 8000, spent: Decimal(string: "2757.40")!,
                                          on: Self.day(2026, 10, 12)))
        #expect(carry.dailyAllowance == 339)
        #expect(carry.spentShown == 2757)
        #expect(carry.expectedShown == 3096)
        let spread = try #require(BudgetPace(budget: 8000, spent: Decimal(string: "2757.40")!, mode: .spread,
                                             on: Self.day(2026, 10, 12), calendar: Self.calendar))
        #expect(spread.gapShown == 339)
        #expect(spread.expectedShown == 3096)
    }

    @Test func theSumAddsUpToThePeso() throws {
        // October, 8,000 a month: $258.06 a day. Rounded line by line, cents could leave the
        // ticket $1 off «Hoy puedes gastar».
        let date = Self.day(2026, 10, 12)
        for spent in ["2757.40", "2757.60", "3096.10", "3500.55", "0.49"] {
            for today in ["0", "10.60", "10.40", "-5.50"] {
                let spent = Decimal(string: spent)!, today = Decimal(string: today)!
                for mode in AllowanceMode.allCases {
                    let pace = try #require(BudgetPace(budget: 8000, spent: spent + today, spentToday: today,
                                                       mode: mode, on: date, calendar: Self.calendar))
                    let sum = pace.sum
                    #expect(sum.budget - sum.spent == sum.remaining)
                    if mode == .carry {
                        #expect(sum.perDay + sum.carriedOver - sum.variableToday == pace.dailyAllowance)
                        #expect(sum.perDay == 258)
                    } else if pace.todayShare >= pace.variableToday {
                        #expect(sum.forToday - sum.variableToday == pace.dailyAllowance)
                    }
                }
            }
        }
        // On the 1st there are no days before: «Por día» takes the peso.
        let first = try #require(BudgetPace(budget: 8000, spent: Decimal(string: "10.60")!,
                                            spentToday: Decimal(string: "10.60")!,
                                            on: Self.day(2026, 10, 1), calendar: Self.calendar))
        #expect(first.sum.perDay - first.sum.variableToday == first.dailyAllowance)
        #expect(first.sum.carriedOver == 0)
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

    @Test func everyDaySoFarCountsTodayIncluded() throws {
        // 8,000 ÷ 31 = 258.06 a day; 12 days = 3,096.77, minus the 1,093.50 already spent.
        let pace = try #require(makePace(budget: 8000, spent: Decimal(string: "1093.50")!,
                                         on: Self.day(2026, 10, 12)))
        #expect(pace.daysLeft == 20)
        #expect(pace.dailyAllowance == 2003)
    }

    @Test func theLastDayGetsAllThatIsLeft() throws {
        let pace = try #require(makePace(budget: 1000, spent: 400, on: Self.day(2026, 10, 31)))
        #expect(pace.daysLeft == 1)
        #expect(pace.dailyAllowance == 600)
    }

    @Test func aBlownBudgetGoesNegative() throws {
        // 1,000 ÷ 31 × 5 = 161.29 − 1,500 = −1,338.71, rounded toward less money.
        let pace = try #require(makePace(budget: 1000, spent: 1500, on: Self.day(2026, 10, 5)))
        #expect(pace.dailyAllowance == -1339)
        #expect(pace.isOverToday)
    }
}

/// What a day leaves over or overspends goes whole to the next one (owner's decision,
/// 2026-10-22). November has 30 days, so 21,000 is $700 a day.
@Suite struct BudgetPaceCarryOverTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func sample(budget: Decimal = 21_000, spent: Decimal, today: Decimal = 0, fixed: Decimal = 0,
                      fixedToday: Decimal = 0, reserved: Decimal = 0, on day: Int) -> BudgetPace? {
        BudgetPace(budget: budget, spent: spent, spentToday: today, fixedSpent: fixed,
                   fixedToday: fixedToday, reserved: reserved, on: Self.day(day), calendar: Self.calendar)
    }

    @Test func theFirstDayStartsWithTheDailyBase() throws {
        let pace = try #require(sample(spent: 0, on: 1))
        #expect(pace.dailyBase == 700)
        #expect(pace.carriedOver == 0)
        #expect(pace.dailyAllowance == 700)
        let spent = try #require(self.sample(spent: 300, today: 300, on: 1))
        #expect(spent.dailyAllowance == 400)
    }

    @Test func whatADayLeavesGoesWholeToTheNext() throws {
        // Spent 300 on the 1st: the 2nd can spend 700 + 400.
        let pace = try #require(sample(spent: 300, on: 2))
        #expect(pace.carriedOver == 400)
        #expect(pace.dailyAllowance == 1100)
    }

    @Test func overspendingTodayGoesNegative() throws {
        // Spending 1,500 on the 2nd: 1,100 − 1,500.
        let pace = try #require(sample(spent: 1800, today: 1500, on: 2))
        #expect(pace.dailyAllowance == -400)
        #expect(pace.isOverToday)
        #expect(!pace.isOverBudget)
    }

    @Test func whatADayOverspendsComesWholeOffTheNext() throws {
        // 700 × 3 − (300 + 1,500).
        let pace = try #require(sample(spent: 1800, on: 3))
        #expect(pace.carriedOver == -400)
        #expect(pace.dailyAllowance == 300)
    }

    @Test func theMonthsFixedExpensesComeOffTheBaseAndNotOffTheDays() throws {
        // 22,000 − 600 of rent charged on the 1st − 400 still to come = 21,000: $700 a day.
        // The rent is not what the 1st spent: the 2nd still gets 1,100.
        let pace = try #require(sample(budget: 22_000, spent: 900, fixed: 600, reserved: 400, on: 2))
        #expect(pace.fixedMonth == 1000)
        #expect(pace.dailyBase == 700)
        #expect(pace.dailyAllowance == 1100)
        #expect(pace.expectedToDate == 2000)
    }

    @Test func aFixedExpenseChargedTodayDoesNotEatToday() throws {
        let pace = try #require(sample(budget: 22_000, spent: 900, today: 600, fixed: 600, fixedToday: 600,
                                     reserved: 400, on: 2))
        #expect(pace.variableToday == 0)
        #expect(pace.dailyAllowance == 1100)
    }

    @Test func aRefundTodayGivesTodayBack() throws {
        let pace = try #require(sample(spent: 200, today: -100, on: 2))
        #expect(pace.dailyAllowance == 1200)
    }

    @Test func roundsDownTowardLessMoney() throws {
        // 10,000 ÷ 30 = 333.33.
        let pace = try #require(sample(budget: 10_000, spent: 0, on: 1))
        #expect(pace.dailyAllowance == 333)
        let over = try #require(self.sample(budget: 10_000, spent: 500, today: 500, on: 1))
        #expect(over.dailyAllowance == -167)
    }

    @Test func theLastDayIsWhatIsFreeOfTheMonth() throws {
        let pace = try #require(sample(budget: 22_000, spent: 15_600, fixed: 600, reserved: 400, on: 30))
        #expect(pace.dailyAllowance == 6_000)
        #expect(pace.free == 6_000)
    }

    @Test func freeIsWhatIsLeftAfterTheFixedOnesAndNeverNegative() throws {
        let pace = try #require(sample(spent: 20_700, reserved: 500, on: 22))
        #expect(pace.remaining == 300)
        #expect(pace.free == 0)
    }
}

/// Which expenses count as today's.
@Suite struct BudgetPaceTodayTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
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
