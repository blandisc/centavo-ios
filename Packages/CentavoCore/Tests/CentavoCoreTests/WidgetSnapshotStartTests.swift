import Foundation
import Testing
@testable import CentavoCore

/// Los widgets con un presupuesto fijado a mitad de mes (2026-11-11): la foto lleva el día desde
/// el que cuenta, y lo de antes sale de sus días.
@Suite struct WidgetSnapshotStartTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// 16 de noviembre, $30,000 fijados hoy: del 1 al 15 se fueron $2,000 y hoy $400.
    private let snapshot = WidgetSnapshot(
        budget: 30_000, isoCode: "MXN", label: "$", takenAt: date(11, 16, hour: 20), spent: 2_400, spentToday: 400,
        days: [500, 0, 1_500] + Array(repeating: Decimal(0), count: 12) + [400], startDay: 16)

    @Test func theWidgetCountsFromThatDayToo() throws {
        let pace = try #require(snapshot.pace(at: Self.date(11, 16, hour: 23), calendar: Self.calendar))
        #expect(pace.startDay == 16)
        #expect(pace.dailyAllowance == 600)
        // Sin el día, la foto de antes: 16 días × $1,000 − $2,400.
        var old = snapshot
        old.startDay = nil
        #expect(old.pace(at: Self.date(11, 16, hour: 23), calendar: Self.calendar)?.dailyAllowance == 13_600)
    }

    @Test func atMidnightItCarriesFromThatDay() throws {
        let pace = try #require(snapshot.pace(at: Self.date(11, 17, hour: 0), calendar: Self.calendar))
        #expect(pace.carriedOver == 600)
        #expect(pace.dailyAllowance == 1_600)
        #expect(pace.startDay == 16)
    }

    @Test func aNewMonthCountsFromItsFirst() throws {
        let month = snapshot.month(at: Self.date(12, 3), calendar: Self.calendar)
        #expect(month.startDay == nil)
        let pace = try #require(snapshot.pace(at: Self.date(12, 3), calendar: Self.calendar))
        #expect(pace.startDay == 1)
        // Diciembre, 31 días: 3 × $30,000 ÷ 31.
        #expect(pace.dailyAllowance == 2_903)
    }

    @Test func itTravelsInTheSnapshotAndOldOnesStillRead() throws {
        let read = try #require(WidgetSnapshot.decode(snapshot.encoded()))
        #expect(read == snapshot)
        #expect(read.startDay == 16)
        // Una foto escrita antes de que existiera: sin `startDay`, todo el mes.
        let old = #"{"budget":8000,"isoCode":"MXN","label":"$","takenAt":0,"spent":100,"spentToday":0,"fixedSpent":0,"fixedToday":0,"reserved":0,"slices":[]}"#
        let decoded = try #require(WidgetSnapshot.decode(Data(old.utf8)))
        #expect(decoded.startDay == nil)
        #expect(decoded.pace(at: Self.date(11, 16), calendar: Self.calendar)?.startDay == 1)
    }

    @Test func aChangedStartDayReloadsTheWidgets() {
        var whole = snapshot
        whole.startDay = nil
        #expect(snapshot.needsReload(replacing: whole, calendar: Self.calendar))
        #expect(!snapshot.needsReload(replacing: snapshot, calendar: Self.calendar))
    }

    @Test func withoutTheDaysNothingBeforeIsKnown() throws {
        // Una foto con el día pero sin los días (no debería pasar): lo de antes cuenta como de
        // sus días, hacia menos dinero, nunca hacia más.
        var bare = snapshot
        bare.days = nil
        let pace = try #require(bare.pace(at: Self.date(11, 16, hour: 23), calendar: Self.calendar))
        #expect(pace.dailyAllowance == -1_400)
    }
}
