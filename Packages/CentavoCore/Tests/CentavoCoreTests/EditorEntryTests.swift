import Foundation
import Testing
@testable import CentavoCore

/// What the expense sheet reads from what is typed or said (2026-11-18).
@Suite struct EditorEntryTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 13))!

    private func parse(_ sentence: String) -> QuickEntry? {
        QuickEntryParser.parse(sentence, sources: ["Nu"], now: Self.now, calendar: Self.calendar)
    }

    // MARK: «230.» in the field

    @Test func aPointJustTypedReadsAsTheAmountBeforeIt() {
        #expect(AmountParser.parseTyped("230.")?.value == 230)
        #expect(AmountParser.parseTyped("1,234.")?.value == 1234)
        #expect(AmountParser.parseTyped("1,234.5")?.value == Decimal(string: "1234.5"))
        #expect(AmountParser.parseTyped("0")?.value == 0)
        #expect(AmountParser.parseTyped("") == nil)
        #expect(AmountParser.parseTyped(".") == nil)
    }

    @Test func aWalletNoticeWithATrailingPointIsStillNotRead() {
        // Only the field forgives it: in a notice or a backup it is not cents.
        #expect(AmountParser.parse("230.") == nil)
    }

    // MARK: The sentence's amount written into the field

    @Test(arguments: [("12.5", "12.5"), ("1234.5", "1,234.5"), ("230", "230"), ("8000", "8,000"), ("0.75", "0.75")] as [(String, String)])
    func theAmountIsWrittenAsTheFieldWritesIt(value: String, shown: String) throws {
        let amount = try #require(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
        #expect(AmountTyping.text(for: amount, decimals: 0...2) == shown)
        #expect(AmountParser.parse(shown)?.value == amount)
    }

    @Test func aRefundIsWrittenWithoutItsSign() throws {
        let amount = try #require(Decimal(string: "-45.5", locale: Locale(identifier: "en_US_POSIX")))
        #expect(AmountTyping.text(for: amount, decimals: 0...2) == "45.5")
    }

    // MARK: A day said, or none

    @Test func aSentenceWithNoDaySaysSo() throws {
        let entry = try #require(parse("230 de tacos"))
        #expect(!entry.daySaid)
        #expect(entry.date == Self.now)
    }

    @Test func aSentenceWithADaySaysSo() throws {
        let entry = try #require(parse("230 de tacos ayer"))
        #expect(entry.daySaid)
    }

    @Test func theModelsReadingKeepsWhetherADayWasSaid() throws {
        for (sentence, said) in [("230 de tacos ayer", true), ("230 de tacos", false)] {
            let base = try #require(parse(sentence))
            let refined = QuickEntryParser.refine(base, sentence: sentence, amount: "230", merchant: "Tacos",
                                                  when: nil, payment: nil, sources: [], now: Self.now,
                                                  calendar: Self.calendar)
            #expect(refined.daySaid == said, "«\(sentence)»")
        }
    }

    // MARK: «€»

    @Test(arguments: [
        ("gasté 12,50€ en Mercadona", "Mercadona"),
        ("12,50 € Mercadona", "Mercadona"),
        ("€12,50 café", "Café"),
    ] as [(String, String)])
    func theEuroSignIsTheCurrency(sentence: String, merchant: String) throws {
        let entry = try #require(parse(sentence), "«\(sentence)»")
        #expect(entry.amountText == "12,50 euros", "«\(sentence)»")
        #expect(entry.merchant == merchant, "«\(sentence)»")
        let amount = try #require(AmountParser.parse(entry.amountText))
        #expect(amount.value == Decimal(string: "12.5"))
        #expect(amount.currencyMarker == "euros")
    }
}
