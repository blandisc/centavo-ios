import Foundation
import Testing
@testable import CentavoCore

@Suite struct CaptureHealthTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    @Test func neverSetUpIsSaid() {
        #expect(CaptureHealth(lastCapture: nil, now: now, calendar: calendar) == .never)
    }

    @Test func todayAndTwoDaysAgoAreFine() {
        for days in [0, 1, 2] {
            #expect(CaptureHealth(lastCapture: daysAgo(days), now: now, calendar: calendar)
                    == .recent(daysAgo(days)))
        }
    }

    @Test func threeQuietDaysAreWorthALook() {
        #expect(CaptureHealth(lastCapture: daysAgo(3), now: now, calendar: calendar) == .quiet(days: 3))
        #expect(CaptureHealth(lastCapture: daysAgo(12), now: now, calendar: calendar) == .quiet(days: 12))
    }
}
