import Foundation
import Testing
@testable import CentavoCore

@Suite struct MonthCodeTests {
    private func day(_ total: Decimal, fixed: Decimal = 0, payments: Int = 1) -> MonthCode.DayInput {
        MonthCode.DayInput(total: total, variable: total - fixed, payments: payments,
                           fixedPayments: fixed > 0 ? 1 : 0)
    }

    @Test func eachDaySaysWhatItWas() {
        // 100 a day. Today is the 4th.
        let code = MonthCode(days: [day(90), day(400, fixed: 350), day(180), day(20), MonthCode.DayInput()],
                             today: 4, limitPerDay: 100)
        #expect(code.days.map(\.kind) == [.plain, .fixed, .over, .today, .future])
        #expect(code.limitPerDay == 100)
        // The biggest day is the tallest bar; one still to come has none.
        #expect(code.days[1].height == 1)
        #expect(code.days[4].height == 0)
    }

    @Test func aFixedChargeAloneIsNotADayOverTheLimit() {
        let code = MonthCode(days: [day(9_800, fixed: 9_800), day(50)], today: 2, limitPerDay: 100)
        #expect(code.days[0].kind == .fixed)
    }

    @Test func theFiguresUnderTheCode() {
        let code = MonthCode(days: [day(100, payments: 2), day(300, payments: 3), day(0, payments: 0),
                                    MonthCode.DayInput(total: 0, payments: 1)],
                             today: 3, limitPerDay: nil)
        // Every payment counts for the folio, even one that doesn't count for the budget.
        #expect(code.payments == 6)
        // The average is over the days so far, today included.
        #expect(code.averagePerDay == Decimal(400) / 3)
        // Without a budget there is no limit, and no day is «over».
        #expect(code.limitPerDay == nil)
        #expect(!code.days.contains { $0.kind == .over })
    }

    @Test func aMonthThatIsOverHasNoTodayAndNoFuture() {
        let code = MonthCode(days: [day(10), day(20)], today: nil, limitPerDay: 50)
        #expect(code.days.map(\.kind) == [.plain, .plain])
        #expect(code.averagePerDay == 15)
    }
}
