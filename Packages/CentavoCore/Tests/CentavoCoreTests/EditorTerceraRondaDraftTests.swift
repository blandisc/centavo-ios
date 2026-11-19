import Foundation
import Testing
@testable import CentavoCore

/// The new expense's draft and its date, third round (2026-11-19): a date only proposed by a
/// past month never comes back, and one picked only in the month on screen.
@Suite struct EditorTerceraRondaDraftTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func aProposedDateNeverComesBack() {
        // «+» in October: the 31st at 23:59 proposed; reopened in November.
        let draft = ExpenseDraft(amountText: "50", currency: "MXN", date: day(2026, 10, 31, hour: 23),
                                 dateProposed: true)
        #expect(draft.restoredDate(visible: day(2026, 11, 2), calendar: calendar) == nil)
        #expect(draft.restoredDate(visible: day(2026, 10, 31), calendar: calendar) == nil)
    }

    @Test func aPickedDateComesBackInItsMonth() {
        let picked = day(2026, 11, 3)
        let draft = ExpenseDraft(amountText: "50", currency: "MXN", date: picked)
        #expect(draft.restoredDate(visible: day(2026, 11, 19), calendar: calendar) == picked)
    }

    @Test func aPickedDateOfAnotherMonthIsLetGo() {
        // Picked in November, the sheet opened again from «+» in October: October's own wins.
        let draft = ExpenseDraft(amountText: "50", currency: "MXN", date: day(2026, 11, 3))
        #expect(draft.restoredDate(visible: day(2026, 10, 31, hour: 23), calendar: calendar) == nil)
    }

    @Test func noDateIsNoDate() {
        let draft = ExpenseDraft(amountText: "50", currency: "MXN")
        #expect(draft.restoredDate(visible: day(2026, 11, 19), calendar: calendar) == nil)
    }
}
