import Foundation
import Testing
@testable import CentavoCore

@Suite struct MonthCalendarTests {
    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        calendar.locale = Locale(identifier: "es_MX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static let monday = calendar(firstWeekday: 2)

    private static func day(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        monday.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func build(_ amounts: [ExpenseAmount], today: Int = 12,
                       calendar: Calendar = MonthCalendarTests.monday,
                       primary: String = "MXN") -> MonthCalendar {
        MonthCalendar.make(amounts, inMonthOf: Self.day(1), primary: primary,
                           today: Self.day(today), calendar: calendar)
    }

    private func days(_ month: MonthCalendar) -> [MonthCalendar.Day] {
        month.cells.compactMap { cell in
            if case .day(let day) = cell { return day }
            return nil
        }
    }

    private func spend(_ value: Decimal, on day: Int, month: Int = 10,
                       marker: String? = "$") -> ExpenseAmount {
        ExpenseAmount(value: value, currencyMarker: marker, date: Self.day(day, month: month))
    }

    @Test func padsTheGridSoTheFirstLandsOnItsWeekday() {
        // 1 Oct 2026 is a Thursday: three slots before it on a Monday-first week,
        // four on a Sunday-first one.
        let mondayFirst = build([])
        #expect(mondayFirst.cells.prefix(3).allSatisfy { $0 == .padding })
        #expect(days(mondayFirst).first?.number == 1)
        #expect(mondayFirst.cells.count == 3 + 31)

        let sundayFirst = build([], calendar: Self.calendar(firstWeekday: 1))
        #expect(sundayFirst.cells.prefix(4).allSatisfy { $0 == .padding })
        #expect(sundayFirst.cells.count == 4 + 31)
    }

    @Test func weekdayHeadersStartOnTheFirstWeekday() {
        #expect(build([]).weekdaySymbols == ["L", "M", "M", "J", "V", "S", "D"])
        #expect(build([], calendar: Self.calendar(firstWeekday: 1)).weekdaySymbols
                == ["D", "L", "M", "M", "J", "V", "S"])
    }

    @Test func daysAfterTodayAreFutureAndTodayIsMarked() {
        let all = days(build([], today: 12))
        #expect(all.first(where: { $0.number == 12 })?.isToday == true)
        #expect(all.filter(\.isToday).count == 1)
        #expect(all.first(where: { $0.number == 12 })?.state == .empty)
        #expect(all.first(where: { $0.number == 13 })?.state == .future)
        #expect(all.first(where: { $0.number == 11 })?.state == .empty)
    }

    @Test func aPastMonthHasNoFutureAndNoToday() {
        let month = MonthCalendar.make([], inMonthOf: Self.day(1, month: 9), primary: "MXN",
                                       today: Self.day(12), calendar: Self.monday)
        let all = days(month)
        #expect(all.count == 30)
        #expect(all.allSatisfy { $0.state == .empty && !$0.isToday })
    }

    @Test func intensityIsRelativeToTheHeaviestDay() {
        let all = days(build([
            spend(1000, on: 2),   // the heaviest: level 3
            spend(700, on: 3),    // 70% of it: level 3
            spend(400, on: 4),    // 40%: level 2
            spend(50, on: 5),     // 5%: level 1
        ]))
        func state(_ number: Int) -> MonthCalendar.Day.State? {
            all.first { $0.number == number }?.state
        }
        #expect(state(2) == .spent(level: 3))
        #expect(state(3) == .spent(level: 3))
        #expect(state(4) == .spent(level: 2))
        #expect(state(5) == .spent(level: 1))
        #expect(state(6) == .empty)
    }

    @Test func spendingOnTheSameDayAddsUp() {
        let all = days(build([spend(40, on: 8), spend(60, on: 8)]))
        let eighth = all.first { $0.number == 8 }
        #expect(eighth?.total == 100)
        #expect(eighth?.state == .spent(level: 3))
    }

    @Test func aDayWhereMoreCameBackThanWentOutIsARefund() {
        let all = days(build([spend(100, on: 9), spend(-230, on: 9)]))
        #expect(all.first { $0.number == 9 }?.state == .refund)
        #expect(all.first { $0.number == 9 }?.total == -130)
    }

    @Test func aDayThatCancelsOutIsEmpty() {
        let all = days(build([spend(100, on: 9), spend(-100, on: 9)]))
        #expect(all.first { $0.number == 9 }?.state == .empty)
    }

    @Test func onlyThePrimaryCurrencyIsDrawn() {
        let all = days(build([
            spend(100, on: 2),
            spend(5000, on: 3, marker: "USD"),
            spend(900, on: 4, marker: "€"),
        ]))
        #expect(all.first { $0.number == 2 }?.state == .spent(level: 3))
        #expect(all.first { $0.number == 3 }?.state == .empty)
        #expect(all.first { $0.number == 4 }?.state == .empty)
    }

    @Test func otherMonthsDoNotLeakIn() {
        let all = days(build([spend(100, on: 15, month: 9), spend(100, on: 15, month: 11)]))
        #expect(all.allSatisfy { $0.state == .empty || $0.state == .future })
    }
}
