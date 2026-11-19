import Foundation
import Testing
@testable import CentavoCore

/// Round 2 of the personas (2026-11-18): «Dilo en una frase» and the search also read the
/// English the app shows, in both languages at once; «el 15 de septiembre» is that month, and
/// «el 31» said in March is 31 January.
@Suite struct FraseBusquedaTests {
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

    private func parse(_ sentence: String, now: Date = Self.november,
                       sources: [String] = ["Nu", "BBVA Oro"]) -> QuickEntry? {
        QuickEntryParser.parse(sentence, sources: sources, now: now, calendar: Self.calendar)
    }

    // MARK: The sentence, in English

    @Test(arguments: ["230 for tacos yesterday, cash", "230 on tacos yesterday, in cash"])
    func theEnglishExampleReadsLikeTheSpanishOne(_ sentence: String) throws {
        let entry = try #require(parse(sentence))
        #expect(entry.amountText == "230")
        #expect(entry.merchant == "Tacos")
        #expect(entry.date == Self.day(17, month: 11))
        #expect(entry.daySaid)
        #expect(entry.source == "Efectivo")
    }

    @Test(arguments: [
        ("80 coffee today", 18, 11), ("80 coffee the day before yesterday", 16, 11),
        ("80 coffee 3 days ago", 15, 11), ("80 coffee two weeks ago", 4, 11),
        ("80 coffee last week", 11, 11), ("80 coffee on Monday", 16, 11),
        ("80 coffee last Wednesday", 11, 11), ("80 coffee on the 3rd", 3, 11),
        ("80 coffee on the 15th of September", 15, 9), ("80 coffee on September 15", 15, 9),
    ])
    func englishDays(_ sentence: String, _ day: Int, _ month: Int) throws {
        let entry = try #require(parse(sentence))
        #expect(entry.amountText == "80")
        #expect(entry.merchant == "Coffee")
        #expect(entry.date == Self.day(day, month: month))
    }

    @Test func dollarsAreTheCurrencyNotTheName() throws {
        let entry = try #require(parse("20 dollars for Steam"))
        #expect(entry.amountText == "20 USD")
        #expect(entry.merchant == "Steam")
    }

    @Test func aShopThatStartsWithAnArticleKeepsIt() throws {
        #expect(parse("1200 The Home Depot")?.merchant == "The Home Depot")
        #expect(parse("1200 at the Home Depot")?.merchant == "Home Depot")
        #expect(parse("spent 45 on a coffee with my Nu")?.merchant == "Coffee")
        #expect(parse("spent 45 on a coffee with my Nu")?.source == "Nu")
    }

    @Test func theSpanishExampleIsTheSame() throws {
        let entry = try #require(parse("230 de unos tacos ayer, en efectivo"))
        #expect(entry.amountText == "230")
        #expect(entry.merchant == "Tacos")
        #expect(entry.date == Self.day(17, month: 11))
        #expect(entry.source == "Efectivo")
    }

    // MARK: «el N» and its month

    @Test func aDayWithItsMonthIsThatMonth() throws {
        let entry = try #require(parse("450 de gasolina el 15 de septiembre"))
        #expect(entry.amountText == "450")
        #expect(entry.merchant == "Gasolina")
        #expect(entry.date == Self.day(15, month: 9))
    }

    @Test func aMonthStillToComeIsLastYears() throws {
        #expect(parse("450 de gasolina el 3 de diciembre")?.date == Self.day(3, month: 12, year: 2025))
        #expect(parse("450 de gasolina el 3 de sept. de 2025")?.date == Self.day(3, month: 9, year: 2025))
    }

    @Test func aDayTheMonthDoesntHaveKeepsToday() throws {
        let entry = try #require(parse("450 de gasolina el 31 de septiembre"))
        #expect(entry.date == Self.november)
        #expect(!entry.daySaid)
        #expect(entry.merchant == "Gasolina")
    }

    @Test(arguments: [
        ("el 31", FraseBusquedaTests.day(5, month: 3), FraseBusquedaTests.day(31, month: 1, hour: 13)),
        ("el 30", FraseBusquedaTests.day(5, month: 3), FraseBusquedaTests.day(30, month: 1, hour: 13)),
        ("el 29", FraseBusquedaTests.day(2, month: 3), FraseBusquedaTests.day(29, month: 1, hour: 13)),
        ("el 31", FraseBusquedaTests.day(1, month: 12), FraseBusquedaTests.day(31, month: 10, hour: 13)),
        ("el 25", FraseBusquedaTests.day(19, month: 10), FraseBusquedaTests.day(25, month: 9, hour: 13)),
        ("el 3", FraseBusquedaTests.day(19, month: 10), FraseBusquedaTests.day(3, month: 10, hour: 13)),
    ])
    func aBareDayIsTheLastMonthThatHasIt(_ said: String, _ now: Date, _ expected: Date) throws {
        let entry = try #require(parse("120 de tacos \(said)", now: now))
        #expect(entry.date == expected)
        #expect(entry.merchant == "Tacos")
    }

    // MARK: The search, in English

    private func query(_ text: String) -> SearchQuery {
        ExpenseSearch.query(from: text, now: Self.november, calendar: Self.calendar)
    }

    @Test func englishMonthsAndBounds() {
        let wanted = query("uber in october over 200")
        #expect(wanted.words == ["uber"])
        #expect(wanted.minAmount == 200)
        #expect(!wanted.inclusive)
        #expect(wanted.interval == Self.calendar.dateInterval(of: .month, for: Self.day(1, month: 10)))
        #expect(query("coffee under 100").maxAmount == 100)
        #expect(query("coffee less than 100").maxAmount == 100)
        #expect(query("coffee more than 100").minAmount == 100)
        #expect(query("coffee up to 100").inclusive)
        #expect(query("dec").interval == Self.calendar.dateInterval(of: .month, for: Self.day(1, month: 12, year: 2025)))
    }

    @Test func aBoundWordWithoutANumberIsAName() {
        #expect(query("under armour").words == ["under", "armour"])
        #expect(query("mar").words == ["mar"])
    }

    @Test func theSpanishSearchIsTheSame() {
        let wanted = query("uber de octubre arriba de 200")
        #expect(wanted.words == ["uber"])
        #expect(wanted.minAmount == 200)
        #expect(query("desde 200").inclusive)
        #expect(!query("más de 200").inclusive)
    }
}
