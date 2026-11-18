import Foundation
import Testing
@testable import CentavoCore

/// «Próximo:» of a fixed expense is the next charge still to come, this month's if it has not
/// come yet (2026-11-18: a monthly on the 25th said «25 dic» on 18 Nov).
@Suite struct FijosProximoCobroTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, month: Int, year: Int = 2026, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static let now = day(18, month: 11, hour: 12)

    private func next(_ rule: RepeatRule, anchor: Date, day: Int? = nil, after: Date) -> Date? {
        RecurringSchedule.next(rule: rule, anchor: anchor, day: day, after: after, now: Self.now,
                               calendar: Self.calendar)
    }

    @Test func rentOnThe31stIsDueOnThe30thOfThisMonth() {
        #expect(next(.monthly, anchor: Self.day(31, month: 8), after: Self.day(31, month: 10))
                == Self.day(30, month: 11))
    }

    @Test func aSubscriptionOnThe25thIsDueThisMonth() {
        #expect(next(.monthly, anchor: Self.day(25, month: 9), after: Self.day(25, month: 10))
                == Self.day(25, month: 11))
    }

    @Test func alreadyChargedThisMonthIsDueNextMonth() {
        #expect(next(.monthly, anchor: Self.day(5, month: 9), after: Self.day(5, month: 11))
                == Self.day(5, month: 12))
    }

    @Test func aPlanThatStartedLastMonthIsDueThisMonth() {
        #expect(next(.monthly, anchor: Self.day(25, month: 10), after: Self.day(25, month: 10))
                == Self.day(25, month: 11))
    }

    @Test func theDayAskedForHoldsWhereTheMonthHasIt() {
        #expect(next(.monthly, anchor: Self.day(30, month: 9), day: 31, after: Self.day(31, month: 10))
                == Self.day(30, month: 11))
    }

    @Test func otherRhythmsStayTheSame() {
        // Wednesday 18 Nov; a weekly on Mondays logged through the 16th.
        #expect(next(.weeks(1), anchor: Self.day(2, month: 11), after: Self.day(16, month: 11))
                == Self.day(23, month: 11))
        #expect(next(.semimonthly, anchor: Self.day(1, month: 10), after: Self.day(15, month: 11))
                == Self.day(30, month: 11))
        #expect(next(.months(2), anchor: Self.day(20, month: 9), after: Self.day(20, month: 9))
                == Self.day(20, month: 11))
    }

    @Test func nothingLoggedForMonthsStillGivesWhatIsToCome() {
        #expect(next(.monthly, anchor: Self.day(25, month: 1), after: Self.day(25, month: 1))
                == Self.day(25, month: 11))
    }
}
