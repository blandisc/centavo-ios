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

    /// The card's last four digits right after the amount used to swallow it.
    @Test(arguments: ["$89.00 1234", "Oxxo $89.00 1234", "Oxxo\n$89.00\n1234", "Oxxo\nBBVA\n$89.00\n1234",
                      "$89.00\n1234"])
    func theCardAfterTheAmountDoesNotHideIt(text: String) throws {
        let parsed = try #require(CaptureText.amount(in: text), "No encontró el monto en «\(text)»")
        #expect(parsed.value == 89)
        #expect(parsed.currencyMarker == "$")
    }

    @Test func spacesStillGroupThousands() {
        #expect(CaptureText.amount(in: "1 234,56 €")?.value == Decimal(string: "1234.56"))
        #expect(CaptureText.amount(in: "Café 1 234,56 €")?.value == Decimal(string: "1234.56"))
    }

    /// A bank's initials next to the card are not a currency.
    @Test(arguments: ["BBVA 1234", "NU 1234", "HSBC 4321", "AMEX 1005", "1234 BBVA"])
    func aBankIsNotACurrency(text: String) {
        #expect(CaptureText.amount(in: text) == nil, "Leyó un monto en «\(text)»")
    }

    @Test func goodCaptureStaysTheSame() {
        #expect(CaptureText.amount(in: "1234") == ParsedAmount(value: 1234))
        #expect(CaptureText.amount(in: "$-20") == ParsedAmount(value: -20, currencyMarker: "$"))
        #expect(CaptureText.amount(in: "CAD 99.99") == ParsedAmount(value: Decimal(string: "99.99")!,
                                                                   currencyMarker: "CAD"))
        #expect(CaptureText.amount(in: "$1,234.567") == nil)
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

@Suite struct CaptureTextRealWorldTests {
    /// Sent by a real automation: the merchant name, twice, where the amount should be.
    @Test func aMerchantNameIsNotAnAmount() {
        #expect(CaptureText.amount(in: "Oxxo Roble Mty 50ht1Oxxo Roble Mty 50ht1") == nil)
    }
}
