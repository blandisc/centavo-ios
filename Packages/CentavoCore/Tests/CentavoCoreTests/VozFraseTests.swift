import Foundation
import Testing
@testable import CentavoCore

/// Round 3 of the personas (2026-11-19): «Dilo en una frase» reads the pound and the British
/// way of saying a day, and a Wallet payment takes one name-only notice at most.
@Suite struct VozFraseTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, month: Int, year: Int = 2026, hour: Int = 13) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Wednesday 18 November 2026, 13:00.
    private static let november = day(18, month: 11)

    private func parse(_ sentence: String) -> QuickEntry? {
        QuickEntryParser.parse(sentence, sources: ["Nu"], now: Self.november, calendar: Self.calendar)
    }

    // MARK: The pound

    @Test(arguments: ["12 pounds for lunch", "£12 for lunch", "£ 12 for lunch", "12£ for lunch", "12 quid for lunch"])
    func thePoundIsTheCurrency(_ sentence: String) throws {
        let entry = try #require(parse(sentence), "«\(sentence)»")
        #expect(entry.amountText == "12 GBP", "«\(sentence)»")
        #expect(entry.merchant == "Lunch", "«\(sentence)»")
        let amount = try #require(AmountParser.parse(entry.amountText))
        #expect(amount.value == 12)
        #expect(CurrencyResolver.isoCode(for: amount.currencyMarker, primary: "MXN") == "GBP")
    }

    @Test func poundsOfSomethingAreAWeight() {
        #expect(parse("2 pounds of beef for 15")?.amountText == "15")
    }

    @Test func theEuroStaysAsItWas() {
        #expect(parse("gasté 12,50€ en Mercadona")?.amountText == "12,50 euros")
    }

    // MARK: The day before its month

    @Test(arguments: [
        ("dinner 45 on 3rd October", 3, 10), ("dinner 45 on 3 Nov", 3, 11),
        ("dinner 45 on 3 November", 3, 11), ("dinner 45 3rd of October", 3, 10),
    ])
    func aDayWithItsMonthAfterIt(_ sentence: String, _ day: Int, _ month: Int) throws {
        let entry = try #require(parse(sentence), "«\(sentence)»")
        #expect(entry.amountText == "45", "«\(sentence)»")
        #expect(entry.merchant == "Dinner", "«\(sentence)»")
        #expect(entry.date == Self.day(day, month: month), "«\(sentence)»")
        #expect(entry.daySaid)
    }

    /// With no other number, the number is the amount: «Uber 25 nov» is $25.
    @Test func aLoneNumberBeforeAMonthIsTheAmount() throws {
        let entry = try #require(parse("Uber 25 nov"))
        #expect(entry.amountText == "25")
        #expect(!entry.daySaid)
    }

    // MARK: One notice per payment

    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aPaymentTakesOneNameOnlyNoticeOnly() {
        let first = PendingPayment(kind: .unread, text: "Oxxo", date: Self.now.addingTimeInterval(-30))
        let second = PendingPayment(kind: .unread, text: "Oxxo", date: Self.now.addingTimeInterval(-90))
        #expect(PendingPayments.settling([second, first], savedIn: ["Oxxo"], at: Self.now) == [second])
    }

    @Test func aNoticeIsSettledOnlyByAPaymentThatHasNoneYet() {
        let notice = PendingPayment(kind: .unread, text: "Oxxo", date: Self.now)
        let paired = [NoticePairing(shops: ["Oxxo"], date: Self.now.addingTimeInterval(-40))]
        #expect(PendingPayments.isSettled(notice, among: [["Oxxo"]], paired: [], at: Self.now))
        #expect(!PendingPayments.isSettled(notice, among: [["Oxxo"]], paired: paired, at: Self.now))
        #expect(PendingPayments.isSettled(notice, among: [["Oxxo"], ["OXXO ROBLE"]], paired: paired, at: Self.now))
        #expect(!PendingPayments.isSettled(notice, among: [["Google"]], paired: [], at: Self.now))
        let figure = PendingPayment(kind: .unread, text: "Oxxo 319", date: Self.now)
        #expect(!PendingPayments.isSettled(figure, among: [["Oxxo"]], paired: [], at: Self.now))
    }

    @Test func pairingsLastTheTwoMinutes() {
        let old = NoticePairing(shops: ["Oxxo"], date: Self.now.addingTimeInterval(-600))
        let new = NoticePairing(shops: ["Google"], date: Self.now)
        #expect(PendingPayments.pairings([old], adding: new, at: Self.now) == [new])
    }
}
