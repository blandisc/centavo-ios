import CentavoCore
import XCTest
@testable import Centavo

/// The expense sheet and the fixed expenses, third round (2026-11-18/19).
@MainActor
final class EditorTerceraRondaTests: XCTestCase {
    private func read(_ old: String, _ new: String) -> AmountFieldEdit {
        AmountFieldEdit.read(old: old, new: new, commaIsDecimal: false)
    }

    // MARK: One key over a selection is typing

    func testOneDigitOverASelectionIsTyped() {
        // «234» of «1,234» selected and «5» typed: 15, never 1.5.
        XCTAssertFalse(AmountFieldEdit.isPaste(old: "1,234", new: "1,5"))
        XCTAssertEqual(read("1,234", "1,5"), .typed("15"))
        // «23» selected and «9» typed: 194, never 1.94.
        XCTAssertFalse(AmountFieldEdit.isPaste(old: "1,234", new: "1,94"))
        XCTAssertEqual(read("1,234", "1,94"), .typed("194"))
    }

    func testTwoCharactersOverASelectionStayAPaste() {
        XCTAssertTrue(AmountFieldEdit.isPaste(old: "1,234", new: "1,56"))
        XCTAssertEqual(read("89.00", "12,50"), .pasted("12.50", carried: nil))
    }

    func testTheFieldsOwnRewriteStillIsNotAPaste() {
        XCTAssertFalse(AmountFieldEdit.isPaste(old: "1,2345", new: "12,345"))
        XCTAssertEqual(read("1,234", "1,2345"), .typed("12,345"))
    }

    // MARK: A plan not started yet keeps the day asked for

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testAPlanPastItsFirstDateFallsOnTheLastDay() throws {
        // «El último día» from April 30th, the app not opened until May 10th.
        let plan = FixedPlan(merchant: "Renta", amount: "8000", currency: "MXN", category: nil,
                             rule: nil, firstDate: day(2027, 4, 30), day: RepeatRule.lastDayOfMonth)
        let item = try XCTUnwrap(FixedOutlook.items(originals: [], plans: [plan], now: day(2027, 5, 10),
                                                    calendar: calendar).first)
        XCTAssertEqual(item.next, day(2027, 5, 31))
        XCTAssertEqual(item.coming, [day(2027, 5, 31)])
    }
}

/// What the note says after a paste that doesn't read (2026-11-18).
@MainActor
final class EditorTerceraRondaPasteTests: XCTestCase {
    func testOneFigureTooLongIsToldApartFromWords() {
        XCTAssertEqual(AmountFieldEdit.read(old: "100", new: "$1,234,567,890,123", commaIsDecimal: false), .unreadable)
        XCTAssertTrue(AmountFieldEdit.isOneFigure("$1,234,567,890,123"))
        XCTAssertTrue(AmountFieldEdit.isOneFigure("USD 1,234,567,890,123"))
        XCTAssertFalse(AmountFieldEdit.isOneFigure("Pedido 4521 total $230"))
        XCTAssertFalse(AmountFieldEdit.isOneFigure("Pedido 4521 total"))
        XCTAssertFalse(AmountFieldEdit.isOneFigure("hola"))
    }
}
