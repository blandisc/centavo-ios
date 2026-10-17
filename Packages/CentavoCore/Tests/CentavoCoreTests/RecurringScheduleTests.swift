import Foundation
import Testing
@testable import CentavoCore

@Suite struct RecurringScheduleTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func due(anchor: Date, after: Date, now: Date) -> [Date] {
        RecurringSchedule.dueDates(anchor: anchor, after: after, now: now, calendar: Self.calendar)
    }

    @Test func nothingIsDueInTheSameMonth() {
        let rent = at(2026, 10, 1)
        #expect(due(anchor: rent, after: rent, now: at(2026, 10, 20)).isEmpty)
    }

    @Test func nextMonthCountsOnlyOnceItsDayCame() {
        let rent = at(2026, 10, 5)
        #expect(due(anchor: rent, after: rent, now: at(2026, 11, 4)).isEmpty)
        #expect(due(anchor: rent, after: rent, now: at(2026, 11, 5, hour: 12)) == [at(2026, 11, 5)])
    }

    @Test func monthsAwayAreAllCaughtUp() {
        let netflix = at(2026, 8, 24)
        #expect(due(anchor: netflix, after: netflix, now: at(2026, 10, 30))
                == [at(2026, 9, 24), at(2026, 10, 24)])
    }

    @Test func the31stLandsOnTheLastDayOfShortMonths() {
        let bill = at(2026, 1, 31)
        #expect(due(anchor: bill, after: bill, now: at(2026, 4, 30, hour: 23))
                == [at(2026, 2, 28), at(2026, 3, 31), at(2026, 4, 30)])
    }

    @Test func monthsAlreadyLoggedAreNotRepeated() {
        let rent = at(2026, 8, 1)
        #expect(due(anchor: rent, after: at(2026, 9, 1), now: at(2026, 10, 2)) == [at(2026, 10, 1)])
    }

    @Test func aClockFarAheadCannotFloodTheStore() {
        let rent = at(2026, 1, 1)
        #expect(due(anchor: rent, after: rent, now: at(2100, 1, 1)).count == 120)
    }
}
