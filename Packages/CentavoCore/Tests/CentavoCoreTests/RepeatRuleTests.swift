import Foundation
import Testing
@testable import CentavoCore

@Suite struct RepeatRuleTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, month: Int = 10, year: Int = 2026, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func dates(_ rule: RepeatRule, anchor: Date, after: Date? = nil, through: Date) -> [Date] {
        RecurringSchedule.dates(rule: rule, anchor: anchor, after: after ?? anchor, through: through,
                                calendar: Self.calendar)
    }

    /// Monday 5 October 2026.
    private let monday = day(5)

    @Test func everyMondayComesOnMondaysOnly() {
        #expect(dates(.weeks(1), anchor: monday, through: Self.day(28)) ==
                [Self.day(12), Self.day(19), Self.day(26)])
    }

    @Test func everyOtherWeek() {
        #expect(dates(.weeks(2), anchor: monday, through: Self.day(30, month: 11)) ==
                [Self.day(19), Self.day(2, month: 11), Self.day(16, month: 11), Self.day(30, month: 11)])
    }

    @Test func aWeeklyFarFromItsStartStillLandsOnItsDay() {
        let late = dates(.weeks(1), anchor: Self.day(5, month: 1), after: Self.day(18, month: 10),
                         through: Self.day(31, month: 10))
        #expect(late == [Self.day(19), Self.day(26)])
        #expect(late.allSatisfy { Self.calendar.component(.weekday, from: $0) == 2 })
    }

    @Test func semimonthlyIsThe15thAndTheLastDay() {
        #expect(dates(.semimonthly, anchor: Self.day(1, month: 1), after: Self.day(31, month: 1),
                      through: Self.day(31, month: 3)) ==
                [Self.day(15, month: 2), Self.day(28, month: 2), Self.day(15, month: 3), Self.day(31, month: 3)])
    }

    @Test func everyOtherMonthKeepsItsDayAndClampsShortMonths() {
        #expect(dates(.months(2), anchor: Self.day(31, month: 8), through: Self.day(31, month: 3, year: 2027)) ==
                [Self.day(31, month: 10), Self.day(31, month: 12), Self.day(28, month: 2, year: 2027)])
    }

    @Test func monthlyIsExactlyWhatItWas() {
        let anchor = Self.day(24, month: 8)
        #expect(dates(.monthly, anchor: anchor, through: Self.day(30)) ==
                RecurringSchedule.dueDates(anchor: anchor, after: anchor, now: Self.day(30), calendar: Self.calendar))
    }

    @Test func onlyDaysThatCameAreDue() {
        // Today is Monday the 19th at 8:00; the 9:00 charge has not come yet.
        let now = Self.day(19, hour: 8)
        #expect(dates(.weeks(1), anchor: monday, through: now) == [Self.day(12)])
    }

    @Test func whatIsStillToComeThisMonth() {
        let now = Self.day(19, hour: 12)
        let coming = RecurringSchedule.comingThisMonth(rule: .weeks(1), anchor: monday, after: Self.day(19),
                                                       now: now, calendar: Self.calendar)
        #expect(coming == [Self.day(26)])
        #expect(RecurringSchedule.next(rule: .weeks(1), anchor: monday, after: Self.day(19), now: now,
                                       calendar: Self.calendar) == Self.day(26))
        #expect(RecurringSchedule.next(rule: .monthly, anchor: Self.day(1), after: Self.day(1), now: now,
                                       calendar: Self.calendar) == Self.day(1, month: 11))
    }

    @Test(arguments: [RepeatRule.monthly, .months(3), .weeks(1), .weeks(2), .semimonthly])
    func survivesBeingSaved(rule: RepeatRule) {
        #expect(RepeatRule(stored: rule.stored) == rule)
    }

    @Test func oldRowsAndJunkAreMonthly() {
        #expect(RepeatRule(stored: nil) == .monthly)
        #expect(RepeatRule(stored: "lo que sea") == .monthly)
        #expect(RepeatRule(stored: "semanas:99") == .weeks(12))
    }

    @Test func saysItInSpanish() {
        #expect(RepeatRule.weeks(1).describe(anchor: monday, calendar: Self.calendar) == "cada lunes")
        #expect(RepeatRule.weeks(2).describe(anchor: monday, calendar: Self.calendar) == "cada 2 semanas, en lunes")
        #expect(RepeatRule.semimonthly.describe(anchor: monday, calendar: Self.calendar) == "cada quincena (15 y último)")
        #expect(RepeatRule.monthly.describe(anchor: monday, calendar: Self.calendar) == "cada mes, el día 5")
        #expect(RepeatRule.months(2).describe(anchor: monday, calendar: Self.calendar) == "cada 2 meses, el día 5")
    }
}

@Suite struct BudgetPaceReservedTests {
    @Test func upcomingFixedExpensesComeOffTheDailyBase() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        // 19 October. (15,000 − 1,000 to come) ÷ 31 = 451.61 a day; 19 days = 8,580.65 − 6,000.
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!
        let pace = try #require(BudgetPace(budget: 15_000, spent: 6_000, reserved: 1_000, on: date, calendar: calendar))
        #expect(pace.remaining == 9_000, "Lo que te queda no cambia: el fijo aún no se gasta")
        #expect(pace.dailyAllowance == 2_580)
        let plain = try #require(BudgetPace(budget: 15_000, spent: 6_000, on: date, calendar: calendar))
        #expect(plain.dailyAllowance == 3_193)
    }
}
