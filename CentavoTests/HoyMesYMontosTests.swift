import XCTest
@testable import Centavo

/// «Hoy» keeps the month on screen when the month turns, and writes other currencies the Mexican
/// way (2026-11-18).
final class HoyMesYMontosTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testAPastMonthStaysOnScreenAtMidnightOnTheFirst() {
        // September on screen on October 31 (one back); at midnight it is November: two back.
        let before = date(2026, 10, 31, hour: 23)
        let after = date(2026, 11, 1, hour: 0)
        XCTAssertEqual(ViewedMonth.offset(-1, from: before, to: after, calendar: calendar), -2)
    }

    func testThisMonthFollowsNow() {
        XCTAssertEqual(ViewedMonth.offset(0, from: date(2026, 10, 31), to: date(2026, 11, 1), calendar: calendar), 0)
    }

    func testComingBackTheSameMonthChangesNothing() {
        XCTAssertEqual(ViewedMonth.offset(-3, from: date(2026, 11, 2), to: date(2026, 11, 18), calendar: calendar), -3)
    }

    func testComingBackMonthsLaterStillShowsThatMonth() {
        XCTAssertEqual(ViewedMonth.offset(-1, from: date(2026, 9, 15), to: date(2026, 12, 2), calendar: calendar), -4)
    }

    func testAClockMovedBackNeverPassesThisMonth() {
        XCTAssertEqual(ViewedMonth.offset(-1, from: date(2026, 11, 2), to: date(2026, 9, 30), calendar: calendar), 0)
    }

    func testOtherCurrenciesAreWrittenTheMexicanWay() {
        // Fixed to es_MX, whatever the phone's region: «EUR 1,234.50», never «EUR 1.234,50».
        XCTAssertEqual(plainAmount(Decimal(string: "1234.5")!), "1,234.50")
        XCTAssertEqual(plainAmount(Decimal(string: "24.99")!), "24.99")
    }
}
