import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// Segunda ronda de datos (2026-11-18): el CSV lleva la marca UTF-8 y avisa lo que no trae, y
/// con «Mi dinero» apagado el respaldo no crea `dinero.store` ni deja uno dañado sin apartar.
@MainActor
final class DatosRespaldoCSVTests: XCTestCase {
    private var container: ModelContainer!

    // Async, so it runs on the main actor like the class (Swift 6: no warning).
    override func setUp() async throws {
        container = try ModelContainer(for: Expense.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private var moneyFolder: URL { MoneyStore.url.deletingLastPathComponent() }

    private func moneyFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: moneyFolder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix(MoneyStore.url.lastPathComponent) }.sorted()
    }

    private func removeMoneyFiles() {
        MoneyStore.forget()
        for name in moneyFiles() { try? FileManager.default.removeItem(at: moneyFolder.appending(path: name)) }
    }

    // MARK: CSV

    func testTheExportStartsWithTheUTF8MarkAndComesBack() throws {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let file = ExpensesCSVFile(expenses: [Expense(amount: 89, currencyMarker: "MXN", merchant: "Café Ñandú",
                                                      date: date, category: "Café")],
                                   primaryCurrency: "MXN")
        XCTAssertEqual(Array(file.data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = try XCTUnwrap(CSVImporter.text(from: file.data))
        XCTAssertEqual(try ExpenseImporter.importCSV(text, into: ModelContext(container)).added, 1)
        let back = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(back.merchant, "Café Ñandú")
        XCTAssertEqual(back.category, "Café")
    }

    func testAFileWithoutCategoryOrCardSaysSo() throws {
        let csv = "Fecha,Comercio,Monto,Moneda\n2026-10-17T15:52:11-06:00,Oxxo,89.50,MXN\n"
        let summary = try ExpenseImporter.importCSV(csv, into: ModelContext(container))
        XCTAssertTrue(summary.lacksCategory)
        XCTAssertTrue(summary.lacksCard)
        XCTAssertEqual(summary.text, "Se agregó 1 gasto. El archivo no trae las columnas Categoría ni Tarjeta: los gastos entraron sin tarjeta y con la categoría que ya usas para cada comercio, si hay una.")
    }

    func testTheMissingColumnsAreSaidOnlyWhenSomethingCameIn() {
        XCTAssertEqual(ExpenseImporter.Summary(added: 2, lacksCategory: true).text,
                       "Se agregaron 2 gastos. El archivo no trae la columna Categoría: los gastos entraron con la categoría que ya usas para cada comercio, si hay una.")
        XCTAssertEqual(ExpenseImporter.Summary(added: 1, lacksCard: true).text,
                       "Se agregó 1 gasto. El archivo no trae la columna Tarjeta: los gastos entraron sin tarjeta.")
        XCTAssertEqual(ExpenseImporter.Summary(alreadyThere: 1, lacksCategory: true, lacksCard: true).text,
                       "No se agregó ningún gasto. 1 ya estaba.")
    }

    // MARK: «Mi dinero» apagado

    func testABackupDoesNotCreateTheHiddenStore() throws {
        try XCTSkipIf(Features.money || MoneyStore.hasFile, "Solo en un iPhone que nunca tuvo «Mi dinero»")
        defer { removeMoneyFiles() }
        let payload = try DailyBackup.snapshot(in: container.mainContext)
        XCTAssertNil(payload.money)
        XCTAssertEqual(DailyBackup.safetyPlan(in: container.mainContext, settings: [:]), .nothingToCopy)
        XCTAssertFalse(MoneyStore.hasFile, "Respaldar no crea dinero.store")
    }

    func testRestoringABackupWithoutMoneySetsADamagedHiddenStoreAside() throws {
        try XCTSkipIf(Features.money || MoneyStore.hasFile, "Solo en un iPhone sin dinero.store propio")
        defer { removeMoneyFiles() }
        try FileManager.default.createDirectory(at: moneyFolder, withIntermediateDirectories: true)
        let garbage = Data("esto no es una base de datos".utf8)
        try garbage.write(to: MoneyStore.url)
        MoneyStore.forget()
        guard case .failure = MoneyStore.opened else { throw XCTSkip("Este sistema abrió el archivo dañado") }
        XCTAssertThrowsError(try DailyBackup.snapshot(in: container.mainContext)) {
            XCTAssertEqual($0 as? DailyBackup.Failure, .moneyUnreadable)
        }

        let backup = BackupPayload(createdAt: .now, writtenBy: "prueba",
                                   expenses: [BackupExpense(amount: 99, date: .now, merchant: "Del respaldo")],
                                   settings: DailyBackup.Settings.current(), money: nil)
        try DailyBackup.restore(backup, into: container)

        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Expense>()).map(\.merchant), ["Del respaldo"])
        XCTAssertFalse(MoneyStore.hasFile, "Lo que no abría ya no está en su lugar")
        let aside = try XCTUnwrap(moneyFiles().first { $0.contains(".danado-") }, "Se apartó, sin borrarse")
        XCTAssertEqual(try Data(contentsOf: moneyFolder.appending(path: aside)), garbage)
        // The next backups go on without it.
        XCTAssertNil(try DailyBackup.snapshot(in: container.mainContext).money)
        XCTAssertFalse(MoneyStore.hasFile)
    }
}
