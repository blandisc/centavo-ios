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

    @Test func aDayThatCameStartsThisMonth() {
        let first = RecurringSchedule.firstDate(day: 5, now: at(2026, 10, 18, hour: 12), calendar: Self.calendar)
        #expect(first == at(2026, 10, 5))
    }

    @Test func aDayStillToComeStartsLastMonthAndLogsItselfWhenItArrives() {
        let now = at(2026, 10, 18, hour: 12)
        let first = RecurringSchedule.firstDate(day: 25, now: now, calendar: Self.calendar)
        #expect(first == at(2026, 9, 25))
        #expect(due(anchor: first, after: first, now: now).isEmpty)
        #expect(due(anchor: first, after: first, now: at(2026, 10, 25, hour: 12)) == [at(2026, 10, 25)])
    }

    @Test func the31stStartsOnTheLastDayOfAShortMonth() {
        let first = RecurringSchedule.firstDate(day: 31, now: at(2026, 3, 10, hour: 12), calendar: Self.calendar)
        #expect(first == at(2026, 2, 28))
    }

    /// Set up for the 31st while September (30 days) was the start: October still gets the 31st.
    @Test func theDayAskedForSurvivesAShortFirstMonth() {
        let start = RecurringSchedule.firstDate(day: 31, now: at(2026, 10, 18), calendar: Self.calendar)
        #expect(start == at(2026, 9, 30))
        let dates = RecurringSchedule.dueDates(anchor: start, day: 31, after: start,
                                               now: at(2026, 12, 31, hour: 12), calendar: Self.calendar)
        #expect(dates == [at(2026, 10, 31), at(2026, 11, 30), at(2026, 12, 31)])
    }

    @Test func theFirstDateIsNeverAheadOfNow() {
        let early = at(2026, 10, 18, hour: 7)
        #expect(RecurringSchedule.firstDate(day: 18, now: early, calendar: Self.calendar) == early)
    }
}
