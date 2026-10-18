import Foundation
import Testing
@testable import CentavoCore

@Suite struct CSVImporterTests {
    private let mexico = TimeZone(identifier: "America/Mexico_City")!

    @Test func whatTheExporterWritesComesBackTheSame() throws {
        let original = [
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_000_000), merchant: "Boru Oum",
                          amount: 175, currency: "MXN", card: "American Express México", category: "Comida"),
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_100_000), merchant: "Steam, \"Inc\"",
                          amount: Decimal(string: "24.99")!, currency: "USD"),
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_200_000), merchant: "=HYPERLINK(\"x\")",
                          amount: -230, currency: "MXN", category: "Ropa\ny más"),
        ]
        let text = CSVExporter.csv(from: original, timeZone: mexico)
        let back = try CSVImporter.records(from: text)
        #expect(back.skipped == 0)
        #expect(back.records == original)
    }

    @Test func reorderedColumnsStillRead() throws {
        let text = "Monto,Moneda,Comercio,Fecha\r\n89.50,MXN,Oxxo,2026-10-17T15:52:11-06:00\r\n"
        let back = try CSVImporter.records(from: text)
        #expect(back.records.first?.merchant == "Oxxo")
        #expect(back.records.first?.amount == Decimal(string: "89.5"))
    }

    @Test func badRowsAreCountedNotGuessed() throws {
        let text = """
        Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría
        ayer,Oxxo,89.50,MXN,,
        2026-10-17T15:52:11-06:00,Oxxo,mucho,MXN,,
        2026-10-17T15:52:11-06:00,Oxxo,89.50,MXN,,

        """
        let back = try CSVImporter.records(from: text)
        #expect(back.records.count == 1)
        #expect(back.skipped == 2)
    }

    @Test func aFileThatIsNotOursIsRefused() {
        #expect(throws: CSVImporter.Failure.notOurFile) { try CSVImporter.records(from: "Nombre,Edad\nAna,30\n") }
        #expect(throws: CSVImporter.Failure.notOurFile) { try CSVImporter.records(from: "") }
    }
}
