import Foundation
import Testing
@testable import CentavoCore

@Suite struct CSVExporterTests {
    private static let zone = TimeZone(identifier: "America/Mexico_City")!

    private static func date(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func csv(_ records: [ExpenseRecord]) -> String {
        CSVExporter.csv(from: records, timeZone: Self.zone)
    }

    private func lines(_ records: [ExpenseRecord]) -> [String] {
        csv(records).split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
    }

    @Test func writesAHeaderEvenWithNoExpenses() {
        #expect(csv([]) == "Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría,Cuenta,Motivo\r\n")
    }

    @Test func writesOneRowPerExpenseWithCRLFEndings() {
        let out = csv([
            ExpenseRecord(date: Self.date(2026, 10, 9, 8, 30), merchant: "Oxxo",
                          amount: 89, currency: "MXN", card: "BBVA", category: "Despensa"),
        ])
        #expect(out == """
        Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría,Cuenta,Motivo\r
        2026-10-09T08:30:00-06:00,Oxxo,89.00,MXN,BBVA,Despensa,Sí,\r

        """)
    }

    @Test func sortsOldestFirstWhateverOrderItGets() {
        let rows = lines([
            ExpenseRecord(date: Self.date(2026, 10, 9), merchant: "Tercero",
                          amount: 3, currency: "MXN"),
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Primero",
                          amount: 1, currency: "MXN"),
            ExpenseRecord(date: Self.date(2026, 10, 5), merchant: "Segundo",
                          amount: 2, currency: "MXN"),
        ])
        #expect(rows.dropFirst().prefix(3).map { $0.split(separator: ",")[1] }
            == ["Primero", "Segundo", "Tercero"])
    }

    @Test func amountsUseDotDecimalsAndNoGrouping() {
        let row = lines([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Liverpool",
                          amount: Decimal(string: "12345.6")!, currency: "MXN"),
        ])[1]
        #expect(row.contains("12345.60"))
    }

    @Test func refundsKeepTheirMinus() {
        let row = lines([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Liverpool",
                          amount: -230, currency: "MXN"),
        ])[1]
        #expect(row.contains("-230.00"))
    }

    @Test func missingCardAndCategoryLeaveEmptyFields() {
        #expect(lines([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Efectivo",
                          amount: 50, currency: "MXN", card: nil, category: nil),
        ])[1].hasSuffix(",MXN,,,Sí,"))
    }

    @Test func anExpenseThatDoesNotCountKeepsItsRealAmountAndSaysWhy() {
        let row = lines([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Uber", amount: 230, currency: "MXN",
                          category: "Transporte", counts: false, uncountedReason: .reimbursed),
        ])[1]
        #expect(row.hasSuffix(",230.00,MXN,,Transporte,No,Me lo reembolsan"))
    }

    @Test func aReasonIsOnlyWrittenForWhatDoesNotCount() {
        let row = lines([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Uber", amount: 230, currency: "MXN",
                          counts: true, uncountedReason: .betweenAccounts),
        ])[1]
        #expect(row.hasSuffix(",Sí,"))
    }

    @Test func quotesFieldsThatWouldBreakTheFormat() {
        let out = csv([
            ExpenseRecord(date: Self.date(2026, 10, 1),
                          merchant: #"Café "El Centavo", S.A."#,
                          amount: 50, currency: "MXN", card: "Línea\nnueva"),
        ])
        // A comma and a quote inside the name; the quote gets doubled.
        #expect(out.contains(#""Café ""El Centavo"", S.A.""#))
        // A newline inside a field stays quoted, so the record spans two lines.
        #expect(out.contains("\"Línea\nnueva\""))
    }

    @Test(arguments: ["a\nb", "a\rb", "a\r\nb", "a,b", "a\"b"])
    func quotesEveryCharacterThatNeedsIt(merchant: String) {
        let out = csv([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: merchant,
                          amount: 1, currency: "MXN"),
        ])
        let quoted = merchant.replacingOccurrences(of: "\"", with: "\"\"")
        #expect(out.contains(",\"\(quoted)\","))
    }

    @Test func accentsSurviveUnescaped() {
        let row = lines([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Farmacia Güemes",
                          amount: 50, currency: "MXN"),
        ])[1]
        #expect(row.contains("Farmacia Güemes"))
    }

    @Test(arguments: ["=HYPERLINK(\"http://x\",\"a\")", "+1+1", "-2+3", "@SUM(A1)", "\tcmd"])
    func aMerchantThatLooksLikeAFormulaIsDefused(merchant: String) {
        let out = csv([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: merchant,
                          amount: 1, currency: "MXN"),
        ])
        let row = out.split(separator: "\r\n").dropFirst().first.map(String.init) ?? ""
        #expect(!row.contains(",=") && !row.contains(",+") && !row.contains(",@"))
        #expect(row.contains("'"))
    }

    @Test func cardAndCategoryAreDefusedToo() {
        let out = csv([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Oxxo", amount: 1,
                          currency: "MXN", card: "=1+1", category: "@x"),
        ])
        #expect(out.contains(",'=1+1,'@x"))
    }

    @Test func amountsKeepTheirMinusEvenThoughTextColumnsAreDefused() {
        let row = lines([
            ExpenseRecord(date: Self.date(2026, 10, 1), merchant: "Liverpool",
                          amount: -230, currency: "MXN"),
        ])[1]
        #expect(row.contains(",-230.00,"))
    }
}
