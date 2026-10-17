import Foundation
import Testing
@testable import CentavoCore

@Suite struct CaptureTextTests {
    @Test(arguments: [
        ("$89.00", "89", "$"),
        ("MX$1,234.50", "1234.5", "MX$"),
        ("12,50 €", "12.5", "€"),
        ("USD 24.99", "24.99", "USD"),
        ("-$230.00", "-230", "$"),
        ("89.00", "89", nil),
        ("R$ 50", "50", "R$"),
        ("Bs. 50", "0.5", "Bs"),       // the parser's own reading; only parity matters here
    ] as [(String, String, String?)])
    func justAnAmountReadsAsBefore(text: String, expected: String, marker: String?) throws {
        let parsed = try #require(CaptureText.amount(in: text))
        #expect(parsed.value == Decimal(string: expected))
        #expect(parsed.currencyMarker == marker)
        #expect(parsed == AmountParser.parse(text), "Cambió cómo se lee un monto solo")
    }

    /// What arrives when the whole payment is connected instead of its «Importe».
    @Test(arguments: [
        ("Oxxo\n$89.00\nBBVA •••• 1234", "89", "$"),
        ("Compra en OXXO por MX$1,234.50 con tarjeta 4321", "1234.5", "MX$"),
        ("Café 12,50 € Nu", "12.5", "€"),
        ("Steam, USD 24.99, BBVA", "24.99", "USD"),
        ("Liverpool -$230.00 (devolución)", "-230", "$"),
        ("Netflix: 219.00 MXN, tarjeta 9876", "219", "MXN"),
    ] as [(String, String, String)])
    func findsTheFigureWithACurrencyInAWholePayment(text: String, expected: String,
                                                    marker: String) throws {
        let parsed = try #require(CaptureText.amount(in: text), "No encontró el monto en «\(text)»")
        #expect(parsed.value == Decimal(string: expected))
        #expect(parsed.currencyMarker == marker)
    }

    /// A card number or a bare figure among words is never taken for the amount.
    @Test(arguments: ["Tarjeta 1234", "Oxxo BBVA 4321", "Nu 1234 Oxxo", "Nu 1234", "1234 Oxxo",
                      "abc", "", "$"])
    func neverGuessesWithoutACurrency(text: String) {
        #expect(CaptureText.amount(in: text) == nil, "Leyó un monto en «\(text)»")
    }

    @Test func aCardCodeIsNotACurrency() {
        #expect(!CaptureText.isCurrency("BBVA"))
        #expect(!CaptureText.isCurrency("NU"))
        #expect(CaptureText.isCurrency("MXN"))
        #expect(CaptureText.isCurrency("MX$"))
    }
}
