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

    @Test("Tras abrir la guía se espera el primer pago; a los 3 días se avisa")
    func waitingThenSilent() {
        #expect(CaptureHealth(lastCapture: nil, now: now, guideOpened: daysAgo(0), calendar: calendar) == .waiting)
        #expect(CaptureHealth(lastCapture: nil, now: now, guideOpened: daysAgo(2), calendar: calendar) == .waiting)
        #expect(CaptureHealth(lastCapture: nil, now: now, guideOpened: daysAgo(3), calendar: calendar) == .silent(days: 3))
        // A guide opened "in the future" (clock moved back) proves nothing.
        #expect(CaptureHealth(lastCapture: nil, now: now, guideOpened: now.addingTimeInterval(60),
                              calendar: calendar) == .never)
    }

    @Test("El primer pago se dice durante un día, y luego es uno más")
    func firstIsSaidForADay() {
        let first = now.addingTimeInterval(-3600)
        let health = CaptureHealth(lastCapture: first, now: now, guideOpened: daysAgo(1), firstArrival: first,
                                   calendar: calendar)
        #expect(health == .first(first))
        #expect(health.isRecent)
        let later = CaptureHealth(lastCapture: daysAgo(1), now: now, firstArrival: daysAgo(2), calendar: calendar)
        #expect(later == .recent(daysAgo(1)))
    }
}
