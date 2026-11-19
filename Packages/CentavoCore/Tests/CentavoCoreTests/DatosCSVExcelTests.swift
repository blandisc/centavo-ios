import Foundation
import Testing
@testable import CentavoCore

/// A CSV that went through Excel and back (2026-11-18): doubled accents, a part saved as a
/// whole number, and amounts with more than two decimals in a «;» file.
@Suite struct DatosCSVExcelTests {
    /// What Excel writes when it opened a file without the UTF-8 mark as Windows-1252 and
    /// saved it as «CSV UTF-8»: every accent doubled.
    /// Byte by byte: Foundation refuses the five bytes Windows-1252 leaves unused (the «”» of
    /// «Ópalo”» ends in 0x9D), which Excel shows as themselves (CI, 2026-11-19).
    private func doubled(_ text: String) -> String {
        var out = ""
        for byte in text.utf8 {
            if let one = String(data: Data([byte]), encoding: .windowsCP1252) {
                out += one
            } else {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            }
        }
        return out
    }

    @Test func doubledAccentsAreUndone() throws {
        let original = """
        Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría,Cuenta,Motivo
        2026-10-17T15:52:11-06:00,Café Ñandú,89.50,MXN,Débito México,Café,Sí,
        2026-10-18T10:00:00-06:00,“Ópalo”,100.00,MXN,,Súper,No,
        """
        let mangled = "\u{FEFF}" + doubled(original)
        #expect(mangled.contains("Categor\u{C3}\u{AD}a"))
        let back = try CSVImporter.records(from: mangled)
        #expect(back.lacksCategory == false)
        #expect(back.records.map(\.merchant) == ["Café Ñandú", "“Ópalo”"])
        #expect(back.records.map(\.category) == ["Café", "Súper"])
        #expect(back.records.first?.card == "Débito México")
        #expect(back.records.map(\.counts) == [true, false])
    }

    @Test func aMarkReadAsWindowsIsDroppedToo() throws {
        let original = "\u{FEFF}Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría\n2026-10-17T15:52:11-06:00,Café,89.50,MXN,,Café\n"
        let back = try CSVImporter.records(from: doubled(original))
        #expect(back.records.first?.merchant == "Café")
        #expect(back.records.first?.category == "Café")
    }

    @Test func rightAccentsAreLeftAlone() {
        let fine = "Fecha,Comercio\n\u{C3}rea Ñ,Café\n"
        #expect(CSVImporter.repairingDoubleEncoding(fine) == fine)
        // A doubled-looking pair next to a real accent is not whole UTF-8 once undone: left alone.
        let mixed = "\u{C3}\u{A9} y é"
        #expect(CSVImporter.repairingDoubleEncoding(mixed) == mixed)
        #expect(CSVImporter.repairingDoubleEncoding("sin acentos") == "sin acentos")
    }

    @Test func missingCategoryOrCardIsSaid() throws {
        let both = try CSVImporter.records(from: "Fecha,Comercio,Monto,Moneda\n2026-10-17T15:52:11-06:00,Oxxo,89.50,MXN\n")
        #expect(both.lacksCategory && both.lacksCard)
        let full = try CSVImporter.records(from: CSVExporter.csv(from: [
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_000_000), merchant: "Oxxo", amount: 89, currency: "MXN"),
        ]))
        #expect(!full.lacksCategory && !full.lacksCard)
    }

    @Test func aPartSavedAsAWholeNumberIsStillAPart() throws {
        let text = """
        Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría,Cuenta,Motivo
        2026-10-01T12:00:00-06:00,Cena,1200.00,MXN,,,600,
        2026-10-02T12:00:00-06:00,Oxxo,89.00,MXN,,,1,
        2026-10-03T12:00:00-06:00,Uber,100.00,MXN,,,0123456789,
        2026-10-04T12:00:00-06:00,Renta,500.00,MXN,,,500,
        2026-10-05T12:00:00-06:00,Café,80.00,MXN,,,0,
        """
        let back = try CSVImporter.records(from: text)
        #expect(back.records.map(\.countedAmount) == [600, nil, nil, nil, nil])
        #expect(back.records.map(\.counts) == [true, true, true, true, true])
    }

    @Test func aPartWithADecimalCommaInASemicolonFile() throws {
        let text = """
        Fecha;Comercio;Monto;Moneda;Tarjeta;Categoría;Cuenta;Motivo
        2026-10-01T12:00:00-06:00;Cena;1200;MXN;;;600;
        2026-10-02T12:00:00-06:00;Taxi;1200;MXN;;;600,5;
        """
        let back = try CSVImporter.records(from: text)
        #expect(back.records.map(\.countedAmount) == [600, Decimal(string: "600.5")!])
    }

    @Test func moreThanTwoDecimalsInASemicolonFile() throws {
        #expect(CSVImporter.commaDecimal("0.125") == Decimal(string: "0.125"))
        #expect(CSVImporter.commaDecimal("1234.567") == Decimal(string: "1234.567"))
        #expect(CSVImporter.commaDecimal("-0.125") == Decimal(string: "-0.125"))
        // Still not guessed: a thousand with a decimal comma's grouping.
        #expect(CSVImporter.commaDecimal("1.234") == nil)
        let text = "Fecha;Comercio;Monto;Moneda\n2026-10-01T12:00:00-06:00;A;0.125;USD\n2026-10-02T12:00:00-06:00;B;1234.567;USD\n"
        let back = try CSVImporter.records(from: text)
        #expect(back.skipped == 0)
        #expect(back.records.map(\.amount) == [Decimal(string: "0.125")!, Decimal(string: "1234.567")!])
    }
}
