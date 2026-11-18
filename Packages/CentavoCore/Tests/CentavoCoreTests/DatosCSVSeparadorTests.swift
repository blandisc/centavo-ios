import Foundation
import Testing
@testable import CentavoCore

/// A CSV re-saved by a spreadsheet in another region or encoding still reads (2026-11-18).
@Suite struct DatosCSVSeparadorTests {
    private let header = "Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría,Cuenta,Motivo"

    @Test func semicolonsWithADecimalCommaRead() throws {
        let text = """
        Fecha;Comercio;Monto;Moneda;Tarjeta;Categoría;Cuenta;Motivo
        2026-10-17T15:52:11-06:00;Oxxo, centro;89,50;MXN;BBVA;Súper;Sí;
        2026-10-18T10:00:00-06:00;Liverpool;1.234,56;MXN;;;600,00;
        2026-10-19T10:00:00-06:00;Renta;1.234;MXN;;;;
        """
        let back = try CSVImporter.records(from: text)
        #expect(back.records.map(\.amount) == [Decimal(string: "89.5")!, Decimal(string: "1234.56")!])
        #expect(back.records.first?.merchant == "Oxxo, centro")
        #expect(back.records.last?.countedAmount == 600)
        // «1.234» could be either: not guessed.
        #expect(back.skipped == 1)
    }

    @Test func tabsRead() throws {
        let text = header.replacingOccurrences(of: ",", with: "\t")
            + "\n2026-10-17T15:52:11-06:00\tOxxo\t89.50\tMXN\t\t\t\t\n"
        let back = try CSVImporter.records(from: text)
        #expect(back.records.map(\.amount) == [Decimal(string: "89.5")!])
    }

    @Test func ourOwnCommasStayCommas() {
        #expect(CSVImporter.separator(of: header + "\nx;y;z;w;v;u;t;s;r\n") == ",")
        #expect(CSVImporter.separator(of: "\n\n" + header.replacingOccurrences(of: ",", with: ";")) == ";")
    }

    @Test func decimalCommaAmounts() {
        #expect(CSVImporter.commaDecimal("89,50") == Decimal(string: "89.5"))
        #expect(CSVImporter.commaDecimal("-230") == -230)
        #expect(CSVImporter.commaDecimal("1.234.567") == 1_234_567)
        #expect(CSVImporter.commaDecimal("89.50") == Decimal(string: "89.5"))
        #expect(CSVImporter.commaDecimal("1.234") == nil)
        #expect(CSVImporter.commaDecimal("0.500,00") == nil)
        #expect(CSVImporter.commaDecimal("12abc") == nil)
    }

    @Test func otherEncodingsAndTheMarkRead() throws {
        let row = "\n2026-10-17T15:52:11-06:00,Café,89.50,MXN,,Súper,,\n"
        let windows = try #require((header + row).data(using: .windowsCP1252))
        let utf16 = try #require((header + row).data(using: .utf16))
        let marked = Data([0xEF, 0xBB, 0xBF]) + Data((header + row).utf8)
        for data in [windows, utf16, marked] {
            let text = try #require(CSVImporter.text(from: data))
            let back = try CSVImporter.records(from: text)
            #expect(back.records.map(\.merchant) == ["Café"])
            #expect(back.records.map(\.category) == ["Súper"])
        }
    }
}
