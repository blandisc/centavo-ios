import Foundation
import Security
import Testing
@testable import CentavoCore

/// The widgets work «Hoy puedes gastar» out from what the app left, at any later moment.
@Suite struct WidgetSnapshotTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// November 1st: $700 a day, $300 spent today, $1,000 of fixed expenses still to come.
    private let snapshot = WidgetSnapshot(budget: 22_000, isoCode: "MXN", label: "$", takenAt: date(11, 1, hour: 20),
                                          spent: 300, spentToday: 300, reserved: 1_000)

    @Test func theSameDayIsWhatTheAppSaw() throws {
        let pace = try #require(snapshot.pace(at: Self.date(11, 1, hour: 23), calendar: Self.calendar))
        #expect(pace.dailyAllowance == 400)
    }

    @Test func atMidnightTodayBecomesYesterday() throws {
        let pace = try #require(snapshot.pace(at: Self.date(11, 2, hour: 0), calendar: Self.calendar))
        #expect(pace.dailyAllowance == 1_100)
        #expect(pace.carriedOver == 400)
    }

    @Test func aNewMonthStartsFromZeroWithTheFixedOnesSetApart() throws {
        let rent = WidgetSnapshot(budget: 22_000, isoCode: "MXN", label: "$", takenAt: Self.date(10, 31),
                                  spent: 9_000, spentToday: 200, fixedSpent: 1_000,
                                  slices: [.init(name: "Comida", amount: 8_000)])
        let month = rent.month(at: Self.date(11, 1, hour: 8), calendar: Self.calendar)
        #expect(month.spent == 0)
        #expect(month.reserved == 1_000)
        #expect(month.slices.isEmpty)
        let pace = try #require(rent.pace(at: Self.date(11, 1, hour: 8), calendar: Self.calendar))
        #expect(pace.dailyAllowance == 700)
    }

    /// «Actualizado hace X» only once the app left it a day ago or more.
    @Test func aSnapshotIsStaleOnlyAfterADay() {
        #expect(snapshot.daysOld(at: Self.date(11, 1, hour: 23)) == nil)
        #expect(snapshot.daysOld(at: Self.date(11, 2, hour: 19)) == nil)
        #expect(snapshot.daysOld(at: Self.date(11, 2, hour: 20)) == 1)
        #expect(snapshot.daysOld(at: Self.date(11, 4, hour: 21)) == 3)
        #expect(snapshot.daysOld(at: Self.date(10, 30)) == nil)
    }

    @Test func noBudgetNoPace() {
        var none = snapshot
        none.budget = nil
        #expect(none.pace(at: Self.date(11, 1), calendar: Self.calendar) == nil)
    }

    @Test func survivesTheTripThroughTheAppGroup() throws {
        let back = try #require(WidgetSnapshot.decode(snapshot.encoded()))
        #expect(back == snapshot)
    }

    @Test func keychainItemIsTheSharedOne() {
        let store = WidgetSnapshotStore(keychainGroup: "B7KRCF776Z.com.blandisc.centavo.shared")
        let query = store.itemQuery
        #expect(query[kSecAttrService as String] as? String == "centavo.widget")
        #expect(query[kSecAttrAccount as String] as? String == "snapshot")
        #expect(query[kSecAttrAccessGroup as String] as? String == "B7KRCF776Z.com.blandisc.centavo.shared")
        // An unexpanded build setting is no group.
        #expect(WidgetSnapshotStore(keychainGroup: "$(AppIdentifierPrefix)x").keychainGroup == nil)
    }

    @Test func slicesAreTheThreeBiggestAndTheRest() {
        let slices = WidgetSnapshot.slices([
            CategoryTotal(category: "Comida", amount: 2_450), CategoryTotal(category: "Despensa", amount: 1_980),
            CategoryTotal(category: "Transporte", amount: 1_320), CategoryTotal(category: "Café", amount: 900),
            CategoryTotal(category: "Ropa", amount: 1_490),
        ])
        #expect(slices.map(\.name) == ["Comida", "Despensa", "Transporte", nil])
        #expect(slices.last?.isRest == true)
        #expect(slices.last?.amount == 2_390)
    }

    @Test func theWidgetUsesTheChosenRule() throws {
        var spread = snapshot
        spread.mode = .spread
        // November 2nd, 300 spent on the 1st: (22,000 − 300 − 1,000) / 29 = 713.79.
        let pace = try #require(spread.pace(at: Self.date(11, 2), calendar: Self.calendar))
        #expect(pace.mode == .spread)
        #expect(pace.dailyAllowance == 713)
        #expect(try #require(snapshot.pace(at: Self.date(11, 2), calendar: Self.calendar)).dailyAllowance == 1_100)
    }

    @Test func aSnapshotFromBeforeTheChoiceReadsAsCarry() throws {
        var old = snapshot
        old.mode = nil
        let back = try #require(WidgetSnapshot.decode(old.encoded()))
        #expect(back.mode == nil)
        #expect(try #require(back.pace(at: Self.date(11, 2), calendar: Self.calendar)).mode == .carry)
    }
}
