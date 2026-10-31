import CentavoCore
import Foundation
import Testing

@Suite("El patrimonio de «Mi dinero»")
struct MoneyLedgerTests {
    func d(_ text: String) -> Decimal { Decimal(string: text)! }

    @Test("El ejemplo de los bocetos cuadra al peso")
    func sketchExample() {
        let worth = NetWorth(lines: [
            .init(kind: .account, currency: "MXN", balance: 185_000),
            .init(kind: .account, currency: "MXN", balance: 150_000),
            .init(kind: .account, currency: "MXN", balance: 42_300),
            .init(kind: .account, currency: "USD", balance: 2_000),
            .init(kind: .investment, currency: "MXN", balance: 25_000),
            .init(kind: .receivable, currency: "MXN", balance: 35_000),
            .init(kind: .receivable, currency: "MXN", balance: 8_000),
            .init(kind: .debt, currency: "MXN", balance: 6_420),
            .init(kind: .debt, currency: "MXN", balance: 1_500),
        ], main: "MXN", rates: ["USD": 19])
        #expect(worth.owned == 440_300)
        #expect(worth.receivable == 43_000)
        #expect(worth.debts == 7_920)
        #expect(worth.total == 475_380)
        #expect(worth.missingRates.isEmpty)
    }

    @Test("Una deuda en dólares también se convierte, y resta")
    func foreignDebt() {
        let worth = NetWorth(lines: [.init(kind: .account, currency: "MXN", balance: 1_000),
                                     .init(kind: .debt, currency: "USD", balance: 10)],
                             main: "MXN", rates: ["USD": d("18.25")])
        #expect(worth.total == d("817.50"))
    }

    @Test("Sin tipo de cambio, esa cuenta no se adivina: queda fuera y se avisa")
    func missingRate() {
        let worth = NetWorth(lines: [.init(kind: .account, currency: "MXN", balance: 100),
                                     .init(kind: .account, currency: "EUR", balance: 50)],
                             main: "MXN", rates: [:])
        #expect(worth.total == 100)
        #expect(worth.missingRates == ["EUR"])
    }

    @Test("Un saldo negativo (sobregiro) resta")
    func overdraft() {
        let worth = NetWorth(lines: [.init(kind: .account, currency: "MXN", balance: -250)], main: "MXN", rates: [:])
        #expect(worth.total == -250)
    }

    @Test("La conversión se redondea a centavos")
    func rounding() {
        let worth = NetWorth(lines: [.init(kind: .account, currency: "USD", balance: d("0.333"))],
                             main: "MXN", rates: ["USD": 3])
        #expect(worth.owned == d("1"))
        #expect(MoneyMath.cents(d("2.005")) == d("2.01"))
        #expect(MoneyMath.cents(d("-2.005")) == d("-2.01"))
    }

    @Test("Los tipos de cambio se guardan como texto y vuelven exactos")
    func rates() {
        let rates: [String: Decimal] = ["USD": d("18.4567"), "EUR": d("20.1")]
        let text = MoneyMath.encodeRates(rates)
        #expect(text == "EUR=20.1;USD=18.4567")
        #expect(MoneyMath.decodeRates(text) == rates)
        #expect(MoneyMath.decodeRates("USD=;=3;EUR=x;GBP=24") == ["GBP": 24])
        #expect(MoneyMath.decodeRates(nil).isEmpty)
    }

    @Test("Monedas que piden tipo de cambio")
    func foreign() {
        let lines: [MoneyLine] = [.init(kind: .account, currency: "USD", balance: 1),
                                  .init(kind: .debt, currency: "EUR", balance: 1),
                                  .init(kind: .account, currency: "MXN", balance: 1),
                                  .init(kind: .account, currency: "USD", balance: 2)]
        #expect(MoneyMath.foreignCurrencies(in: lines, main: "MXN") == ["EUR", "USD"])
    }

    @Test("Un corte por mes: la llave es el mes")
    func monthKey() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 23))!
        #expect(MoneyMath.monthKey(of: day, calendar: calendar) == "2026-03")
    }

    @Test("La pista de rendimiento: saldo × tasa × días ÷ 365")
    func yieldHint() {
        // 150,000 al 9.8% por 30 días: 1,208.22.
        #expect(MoneyMath.expectedYield(previous: 150_000, yearlyRate: d("9.8"), days: 30) == d("1208.22"))
        #expect(MoneyMath.expectedYield(previous: 150_000, yearlyRate: 0, days: 30) == 0)
        #expect(MoneyMath.expectedYield(previous: 150_000, yearlyRate: 10, days: 0) == 0)
    }
}
