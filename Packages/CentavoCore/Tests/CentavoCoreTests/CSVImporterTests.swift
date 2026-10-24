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

    @Test func whatDoesNotCountComesBackWithItsReason() throws {
        let original = [
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_000_000), merchant: "Uber",
                          amount: 230, currency: "MXN", category: "Transporte",
                          counts: false, uncountedReason: .reimbursed),
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_100_000), merchant: "SPEI Nu",
                          amount: 5000, currency: "MXN", counts: false, uncountedReason: .betweenAccounts),
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_200_000), merchant: "Regalo",
                          amount: 400, currency: "MXN", counts: false, uncountedReason: .other),
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_300_000), merchant: "Oxxo",
                          amount: 89, currency: "MXN"),
        ]
        let back = try CSVImporter.records(from: CSVExporter.csv(from: original, timeZone: mexico))
        #expect(back.skipped == 0)
        #expect(back.records == original)
    }

    @Test func aFileFromBeforeTheColumnsCountsEverything() throws {
        let text = """
        Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría
        2026-10-17T15:52:11-06:00,Uber,230.00,MXN,,Transporte

        """
        let record = try #require(try CSVImporter.records(from: text).records.first)
        #expect(record.counts)
        #expect(record.uncountedReason == nil)
        #expect(record.amount == 230)
    }

    @Test func onlyANoLeavesItOutAndAReasonIsReadEitherWay() throws {
        let text = """
        Fecha,Comercio,Monto,Moneda,Cuenta,Motivo
        2026-10-17T15:52:11-06:00,A,1.00,MXN,no,entre-cuentas
        2026-10-17T15:52:12-06:00,B,1.00,MXN,NO,me lo reembolsan
        2026-10-17T15:52:13-06:00,C,1.00,MXN,No,quién sabe
        2026-10-17T15:52:14-06:00,D,1.00,MXN,quizá,Otro
        2026-10-17T15:52:15-06:00,E,1.00,MXN,,

        """
        let records = try CSVImporter.records(from: text).records
        #expect(records.map(\.counts) == [false, false, false, true, true])
        #expect(records.map(\.uncountedReason) == [.betweenAccounts, .reimbursed, nil, nil, nil])
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

    /// A re-saved spreadsheet: grouping is read, junk is refused instead of half-read.
    @Test func amountsAreReadWholeOrNotAtAll() {
        #expect(CSVImporter.number("1,234.56") == Decimal(string: "1234.56"))
        #expect(CSVImporter.number("-230.00") == -230)
        #expect(CSVImporter.number("0.125") == Decimal(string: "0.125"))
        #expect(CSVImporter.number("12abc") == nil)
        #expect(CSVImporter.number("$12") == nil)
    }
}
