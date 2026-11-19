import CentavoCore
import XCTest
@testable import Centavo

/// The expense sheet's amount field and its notes, second round (2026-11-18): a paste is told
/// apart by what it is, not by how much the text grew.
@MainActor
final class EditorSegundaRondaTests: XCTestCase {
    private func read(_ old: String, _ new: String, comma: Bool = false) -> AmountFieldEdit {
        AmountFieldEdit.read(old: old, new: new, commaIsDecimal: comma)
    }

    // MARK: Pasting over what is there

    func testDecimalCommaPastedOverSameLengthIsTwelveFifty() {
        // «12,50» over «89.00»: five for five characters, read 1,250 before.
        XCTAssertEqual(read("89.00", "12,50"), .pasted("12.50", carried: nil))
    }

    func testMinusPastedOverShorterAmountGoesToTheSheet() {
        XCTAssertEqual(read("100", "-$50"),
                       .pasted("50", carried: ParsedAmount(value: -50, currencyMarker: "$")))
    }

    func testCurrencyPastedOverLongerAmountGoesToTheSheet() {
        XCTAssertEqual(read("100,000", "USD 25"),
                       .pasted("25", carried: ParsedAmount(value: 25, currencyMarker: "USD")))
    }

    func testPasteWithNoAmountKeepsTheField() {
        // Joined before: 4,521,230 with nothing said.
        XCTAssertEqual(read("100", "Pedido 4521 total $230"), .unreadable)
        XCTAssertEqual(read("", "hola"), .unreadable)
    }

    func testThousandsPastedTheFieldsWayReadTheSame() {
        XCTAssertEqual(read("", "1,234.56"), .typed("1,234.56"))
        XCTAssertEqual(read("", "1.234,56"), .pasted("1,234.56", carried: nil))
    }

    // MARK: Typing stays typing

    func testOneKeyPutsTheThousandsIn() {
        XCTAssertEqual(read("1,234", "1,2345"), .typed("12,345"))
    }

    func testTheFieldsOwnRewriteIsNotAPaste() {
        XCTAssertEqual(read("1,2345", "12,345"), .typed("12,345"))
        XCTAssertFalse(AmountFieldEdit.isPaste(old: "1,2345", new: "12,345"))
    }

    func testDeletingTakesTheThousandsOut() {
        XCTAssertEqual(read("1,234", "1,23"), .typed("123"))
        XCTAssertEqual(read("1,234", ""), .typed(""))
    }

    func testCommaKeyIsTheDecimalPointWhereThePadHasOne() {
        XCTAssertEqual(read("12", "12,", comma: true), .typed("12."))
        XCTAssertEqual(read("12", "12,"), .typed("12"))
    }

    func testOneDigitOverEverythingIsTyped() {
        XCTAssertEqual(read("89.00", "5"), .typed("5"))
    }

    // MARK: The note under the amount

    func testCurrencyNoteStaysUntilTheAmountIsEmptied() {
        let note = ExpenseEditorView.PasteNote(text: "x")
        XCTAssertFalse(note.clears(with: "20"))
        XCTAssertTrue(note.clears(with: ""))
    }

    func testUnreadPasteNoteStaysThroughThePasteAndGoesWithTyping() {
        let note = ExpenseEditorView.PasteNote(text: "x", restored: "100")
        XCTAssertFalse(note.clears(with: "100"))
        XCTAssertFalse(note.clears(with: "Pedido 4521 total $230"))
        XCTAssertTrue(note.clears(with: "1005"))
        XCTAssertTrue(note.clears(with: ""))
        let fromEmpty = ExpenseEditorView.PasteNote(text: "x", restored: "")
        XCTAssertFalse(fromEmpty.clears(with: ""))
        XCTAssertTrue(fromEmpty.clears(with: "5"))
    }

    func testOnlyRealCurrenciesAreTakenFromAPaste() {
        XCTAssertTrue(ExpenseEditorView.isRealCurrency("EUR"))
        XCTAssertTrue(ExpenseEditorView.isRealCurrency("COP"))
        XCTAssertFalse(ExpenseEditorView.isRealCurrency("ABC"))
    }

    // MARK: «Llegó de Wallet»

    func testWalletStampFollowsTheClockOfTheLanguage() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18,
                                                                            hour: 14, minute: 32)))
        let american = ExpenseEditorView.stamp(date, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(american.contains("2:32"), american)
        XCTAssertFalse(american.contains("14:32"), american)
        XCTAssertTrue(ExpenseEditorView.stamp(date, locale: Locale(identifier: "en_GB")).contains("14:32"))
    }
}
