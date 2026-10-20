import Foundation
import Testing
@testable import CentavoCore

@Suite struct QuickEntryTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    /// Monday 19 October 2026, 13:00.
    private static let now = day(19, hour: 13)

    private static func day(_ day: Int, month: Int = 10, hour: Int = 13) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func parse(_ sentence: String, sources: [String] = ["Nu", "BBVA Oro"]) -> QuickEntry? {
        QuickEntryParser.parse(sentence, sources: sources, now: Self.now, calendar: Self.calendar)
    }

    @Test func readsTheExampleFromThePitch() throws {
        let entry = try #require(parse("230 de unos tacos ayer, en efectivo"))
        #expect(entry.amountText == "230")
        #expect(entry.merchant == "Tacos")
        #expect(entry.date == Self.day(18))
        #expect(entry.source == "Efectivo")
    }

    @Test(arguments: [
        ("anota 89.50 en Oxxo", "89.50", "Oxxo"),
        ("gasté 1,250 en Liverpool", "1,250", "Liverpool"),
        ("500 de gasolina en Pemex", "500", "Pemex"),
        ("20 dólares de Steam", "20 dólares", "Steam"),
        ("$45 café", "$45", "Café"),
    ] as [(String, String, String)])
    func findsAmountAndMerchant(sentence: String, amount: String, merchant: String) throws {
        let entry = try #require(parse(sentence))
        #expect(entry.amountText == amount, "«\(sentence)»")
        #expect(entry.merchant == merchant, "«\(sentence)»")
        #expect(entry.date == Self.now)
    }

    @Test(arguments: [
        ("hoy", 19, 10), ("ayer", 18, 10), ("antier", 17, 10), ("antes de ayer", 17, 10),
        ("el viernes", 16, 10), ("el lunes", 19, 10), ("el domingo pasado", 18, 10),
        ("el 3", 3, 10), ("el día 25", 25, 9), ("hace 3 días", 16, 10), ("hace dos días", 17, 10),
        ("la semana pasada", 12, 10),
    ] as [(String, Int, Int)])
    func understandsWhen(phrase: String, day: Int, month: Int) {
        let date = QuickEntryParser.date(from: phrase, now: Self.now, calendar: Self.calendar)
        #expect(date == Self.day(day, month: month), "«\(phrase)»")
    }

    @Test func theDayOfTheMonthIsNotTheAmount() throws {
        let entry = try #require(parse("el 3 pagué 120 de tortillas"))
        #expect(entry.amountText == "120")
        #expect(entry.date == Self.day(3))
        #expect(entry.merchant == "Tortillas")
    }

    @Test func knowsYourCardsByName() throws {
        #expect(parse("300 en Soriana con la Nu")?.source == "Nu")
        #expect(parse("300 en Soriana con mi tarjeta BBVA Oro")?.source == "BBVA Oro")
        #expect(parse("300 en Soriana con la Banamex")?.source == nil)
    }

    @Test func noAmountNoExpense() {
        #expect(parse("tacos ayer") == nil)
        #expect(parse("") == nil)
        #expect(parse("0 en Oxxo") == nil)
    }

    @Test func modelReadingIsUsedOnlyWhereItMatchesWhatWasSaid() throws {
        let sentence = "me tomé un cafecito de 45 en la Ceiba ayer"
        let base = try #require(parse(sentence))
        let refined = QuickEntryParser.refine(base, sentence: sentence, amount: "45", merchant: "la Ceiba",
                                              when: "ayer", payment: nil, sources: [], now: Self.now,
                                              calendar: Self.calendar)
        #expect(refined.merchant == "La Ceiba")
        #expect(refined.amountText == "45")
        #expect(refined.date == Self.day(18))

        // A merchant or an amount that was never said is ignored.
        let invented = QuickEntryParser.refine(base, sentence: sentence, amount: "450", merchant: "Starbucks",
                                               when: "el viernes", payment: "con la Nu", sources: ["Nu"],
                                               now: Self.now, calendar: Self.calendar)
        #expect(invented.amountText == base.amountText)
        #expect(invented.merchant == base.merchant)
        #expect(invented.date == base.date)
        #expect(invented.source == nil)
    }

    @Test(arguments: [
        ("5 tacos de 20", "20"),
        ("gasté 300 en 2 cosas", "300"),
        ("2 cafés por 90", "90"),
        ("3 boletos 450 pesos", "450 pesos"),
        ("3 tacos 60", "60"),
        ("Farmacia 24 horas 180", "180"),
        ("Oxxo 2 aguas 30", "30"),
        ("hace 90 días 200 de super", "200"),
    ] as [(String, String)])
    func picksTheAmountNotACount(sentence: String, amount: String) {
        #expect(parse(sentence)?.amountText == amount, "«\(sentence)»")
    }

    @Test func aModelNumberMustBeAWholeWordOfTheSentence() throws {
        let sentence = "450 en Liverpool"
        let base = try #require(parse(sentence))
        let refined = QuickEntryParser.refine(base, sentence: sentence, amount: "45", merchant: nil, when: nil,
                                              payment: nil, sources: [], now: Self.now, calendar: Self.calendar)
        #expect(refined.amountText == "450")
    }

    @Test func aSurePlainAmountStandsAgainstTheModel() throws {
        let sentence = "5 tacos de 20"
        let base = try #require(parse(sentence))
        let refined = QuickEntryParser.refine(base, sentence: sentence, amount: "5", merchant: nil, when: nil,
                                              payment: nil, sources: [], now: Self.now, calendar: Self.calendar)
        #expect(refined.amountText == "20")
        // An unsure one (no currency, no «de») is the model's to settle.
        let unsure = "3 tacos 60 y 2 refrescos"
        let plain = try #require(parse(unsure))
        let settled = QuickEntryParser.refine(plain, sentence: unsure, amount: "60", merchant: nil, when: nil,
                                              payment: nil, sources: [], now: Self.now, calendar: Self.calendar)
        #expect(settled.amountText == "60")
    }

    @Test func thePlainDayAndCardWinOverTheModels() throws {
        let sentence = "120 de pan antes de ayer en efectivo"
        let base = try #require(parse(sentence))
        #expect(base.date == Self.day(17))
        let refined = QuickEntryParser.refine(base, sentence: sentence, amount: nil, merchant: nil, when: "ayer",
                                              payment: "en efectivo", sources: [], now: Self.now,
                                              calendar: Self.calendar)
        #expect(refined.date == Self.day(17))
        #expect(refined.source == "Efectivo")
    }

    @Test func theDayOrTheCardIsNotTheMerchant() throws {
        let sentence = "230 de tacos ayer en efectivo con la Nu"
        let base = try #require(parse(sentence))
        for wrong in ["tacos ayer en efectivo", "la Nu", "ayer"] {
            let refined = QuickEntryParser.refine(base, sentence: sentence, amount: nil, merchant: wrong, when: nil,
                                                  payment: nil, sources: ["Nu"], now: Self.now, calendar: Self.calendar)
            #expect(refined.merchant == base.merchant, "«\(wrong)»")
        }
    }
}
