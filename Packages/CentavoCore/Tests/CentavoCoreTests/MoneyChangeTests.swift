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

    // MARK: Miles con coma al escribir (2026-11-11)

    /// Types `keys` one at a time, as the field does.
    private static func typing(_ keys: String, from start: String = "", separator: String = ".") -> String {
        keys.reduce(start) { MoneyTyping.typed($0 + String($1), was: $0, decimalSeparator: separator) }
    }

    @Test func thousandsGoInWhileABalanceIsTyped() {
        #expect(Self.typing("185000") == "185,000")
        #expect(Self.typing("12500.5") == "12,500.5")
        #expect(Self.typing("1234567.89") == "1,234,567.89")
        #expect(Self.typing(".5") == "0.5")
        #expect(Self.typing("12.345") == "12.34", "El tercer decimal no se escribe")
        // Borrar un dígito reacomoda las comas.
        #expect(MoneyTyping.typed("12,50", was: "12,500") == "1,250")
        #expect(MoneyTyping.typed("", was: "5") == "")
        // Digits typed fast arrive together: still typed («1,85000» stayed like that on screen).
        #expect(MoneyTyping.typed("1,85000", was: "1,850") == "185,000")
        #expect(MoneyTyping.typed("185000", was: "") == "185,000")
        #expect(MoneyTyping.typed("−1,50000", was: "−1,500") == "−150,000")
        #expect(MoneyTyping.typed("1.234", was: "1.2") == "1.2")
        // Donde el teclado trae «,», la coma recién escrita es el punto decimal.
        #expect(Self.typing("1234,5", separator: ",") == "1,234.5")
    }

    @Test func theSignStaysWhileTyping() {
        #expect(Self.typing("−300") == "−300")
        #expect(Self.typing("-12500") == "-12,500")
        #expect(Self.typing("−") == "−")
        // Un saldo en números rojos que se corrige no pierde el signo.
        #expect(MoneyTyping.typed("−1,5000", was: "−1,500") == "−15,000")
        #expect(MoneyTyping.signedReading(Self.typing("−12500.50")) == .value(Decimal(string: "-12500.5")!))
    }

    @Test func whatIsTypedWithCommasReadsTheSame() {
        for plain in ["0", "7", "999", "1000", "12500", "185000.00", "1234567.8", "0.05", "999999999999"] {
            let shown = Self.typing(plain)
            #expect(MoneyTyping.reading(shown) == MoneyTyping.reading(plain), "\(plain) → \(shown)")
            #expect(MoneyTyping.signedReading("−" + shown) == MoneyTyping.signedReading("−" + plain))
            // Lo que el campo ya escribió no cambia al volver a pasar.
            #expect(MoneyTyping.typed(shown, was: plain) == shown)
        }
    }

    @Test func somethingPastedIsReadNotTrimmed() {
        #expect(MoneyTyping.typed("$1,234.5", was: "") == "1,234.50")
        #expect(MoneyTyping.typed("12500", was: "") == "12,500")
        #expect(MoneyTyping.typed("7,5", was: "") == "7.50", "Una coma sola antes de uno o dos dígitos es decimal")
        #expect(MoneyTyping.typed("-1500", was: "") == "−1,500")
        // Lo que no se lee se queda como está, para decirlo: nunca recortado a otra cifra.
        #expect(MoneyTyping.typed("1.234,56", was: "") == "1.234,56")
        #expect(MoneyTyping.reading(MoneyTyping.typed("1.234,56", was: "")) == .unreadable)
        #expect(MoneyTyping.typed("12 mil", was: "") == "12 mil")
        #expect(MoneyTyping.typed("18.125", was: "") == "18.125")
        // Y sigue sin leerse si se le escribe algo más.
        #expect(MoneyTyping.typed("1.234,560", was: "1.234,56") == "1.234,560")
    }

    @Test func aSavedBalanceComesBackWithItsThousands() {
        #expect(MoneyTyping.groupedText(12_000) == "12,000")
        #expect(MoneyTyping.groupedText(Decimal(string: "12000.5")!) == "12,000.50")
        #expect(MoneyTyping.groupedText(-300) == "−300")
        #expect(MoneyTyping.groupedText(Decimal(string: "-1500.25")!) == "−1,500.25")
        #expect(MoneyTyping.groupedText(nil) == "")
        #expect(MoneyTyping.groupedText(Decimal(string: "0.125")!) == "0.125", "Más de centavos no se recorta")
        for value in [Decimal(0), 7, 12_000, Decimal(string: "185000.5")!, Decimal(string: "-1500.25")!] {
            #expect(MoneyTyping.signedReading(MoneyTyping.groupedText(value)) == .value(value))
            #expect(MoneyTyping.reading(MoneyTyping.groupedText(value)) == .value(value))
        }
    }
}
