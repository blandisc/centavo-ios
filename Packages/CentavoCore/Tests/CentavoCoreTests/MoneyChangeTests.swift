import Foundation
import Testing
@testable import CentavoCore

/// Segunda auditoría (2026-11-02): «desde sep» y los meses del corte.
@Suite struct MoneyChangeTests {
    private func cut(_ lines: [String: MoneyLine], rates: [String: Decimal] = [:]) -> MoneyChange.Cut<String> {
        MoneyChange.Cut(lines: lines, main: "MXN", rates: rates)
    }

    private func mxn(_ value: Decimal, _ kind: MoneyKind = .account) -> MoneyLine {
        MoneyLine(kind: kind, currency: "MXN", balance: value)
    }

    @Test func archivingAnAccountIsNotALoss() {
        // Septiembre: Nu 10,000 y Caja 5,000. Octubre: Nu 11,000, Caja 5,000; luego se archiva Caja.
        let previous = cut(["nu": mxn(10_000), "caja": mxn(5_000)])
        let latest = cut(["nu": mxn(11_000), "caja": mxn(5_000)])
        #expect(MoneyChange.since(previous: previous, latest: latest, counting: ["nu"]) == 1_000)
        #expect(MoneyChange.since(previous: previous, latest: latest, counting: ["nu", "caja"]) == 1_000)
    }

    @Test func aNewAccountIsNotSavings() {
        // Un fondo de $100,000 agregado el 15 de noviembre entra al último corte (octubre).
        let previous = cut(["nu": mxn(10_000)])
        let latest = cut(["nu": mxn(10_500), "fondo": mxn(100_000)])
        #expect(MoneyChange.since(previous: previous, latest: latest, counting: ["nu", "fondo"]) == 500)
    }

    @Test func anAccountMissingARateInEitherCutIsLeftOut() {
        let previous = cut(["usd": MoneyLine(kind: .account, currency: "USD", balance: 100), "nu": mxn(1_000)])
        let latest = cut(["usd": MoneyLine(kind: .account, currency: "USD", balance: 100), "nu": mxn(1_200)],
                         rates: ["USD": 18])
        #expect(MoneyChange.since(previous: previous, latest: latest, counting: ["usd", "nu"]) == 200)
    }

    @Test func debtsSubtract() {
        let previous = cut(["amex": mxn(6_000, .debt), "nu": mxn(10_000)])
        let latest = cut(["amex": mxn(4_000, .debt), "nu": mxn(9_000)])
        #expect(MoneyChange.since(previous: previous, latest: latest, counting: ["amex", "nu"]) == 1_000)
    }

    // MARK: Meses del corte (#6)

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    @Test func aMonthBeforeTheLatestCutIsNeverOffered() {
        // 2 de noviembre, con un corte de noviembre ya hecho: octubre ya no se ofrece.
        let months = MoneyMath.cutMonths(now: Self.date(11, 2), latest: "2026-11", calendar: Self.calendar)
        #expect(months == ["2026-11"])
        let early = MoneyMath.cutMonths(now: Self.date(11, 2), latest: "2026-10", calendar: Self.calendar)
        #expect(early == ["2026-10", "2026-11"])
        let none = MoneyMath.cutMonths(now: Self.date(11, 20), latest: nil, calendar: Self.calendar)
        #expect(none == ["2026-11", "2026-10"])
    }

    @Test func anAccountCreatedAfterAMonthDoesNotBelongToIt() {
        #expect(MoneyMath.belongs(createdAt: Self.date(10, 31), to: "2026-10", calendar: Self.calendar))
        #expect(!MoneyMath.belongs(createdAt: Self.date(11, 1), to: "2026-10", calendar: Self.calendar))
        #expect(MoneyMath.belongs(createdAt: Self.date(9, 1), to: "2026-10", calendar: Self.calendar))
    }

    // MARK: Lo escrito en un corte a medias (#5)

    @Test func aBalanceTypedComesBackAsText() {
        #expect(MoneyTyping.text(Decimal(string: "12000.50")!) == "12000.5")
        #expect(MoneyTyping.text(12_000) == "12000")
        #expect(MoneyTyping.signedText(-300) == "−300")
        #expect(MoneyTyping.signedText(nil) == "")
    }

    @Test func whatDoesNotReadIsSaid() {
        #expect(MoneyTyping.reading("") == .empty)
        #expect(MoneyTyping.reading("12,000") == .value(12_000))
        #expect(MoneyTyping.reading("12 mil") == .unreadable)
        #expect(MoneyTyping.reading("1.234") == .unreadable, "Más de centavos no se lee")
        #expect(MoneyTyping.signedReading("−300") == .value(-300))
        #expect(MoneyTyping.signedReading("-abc") == .unreadable)
    }
}
