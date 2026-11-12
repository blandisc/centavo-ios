import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

final class ExpenseImporterTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func all() throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    func testAnExportComesBackWhole() throws {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let csv = CSVExporter.csv(from: [
            ExpenseRecord(date: date, merchant: "Boru Oum", amount: 175, currency: "MXN",
                          card: "American Express México", category: "Comida"),
        ])
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context),
                       .init(added: 1, alreadyThere: 0, unreadable: 0))
        let expense = try XCTUnwrap(all().first)
        XCTAssertEqual(expense.merchant, "Boru Oum")
        XCTAssertEqual(expense.amount, 175)
        XCTAssertEqual(expense.currencyMarker, "MXN")
        XCTAssertEqual(expense.card, "American Express México")
        XCTAssertEqual(expense.category, "Comida")
        XCTAssertEqual(expense.date, date)
    }

    func testImportingTwiceDoesNotDuplicate() throws {
        let csv = CSVExporter.csv(from: [
            ExpenseRecord(date: Date(timeIntervalSince1970: 1_792_000_000), merchant: "Oxxo",
                          amount: 89, currency: "MXN"),
        ])
        _ = try ExpenseImporter.importCSV(csv, into: context)
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context),
                       .init(added: 0, alreadyThere: 1, unreadable: 0))
        XCTAssertEqual(try all().count, 1)
    }

    /// Two «Uber $100» logged the same moment are two expenses: both come in, and importing the
    /// file again brings neither.
    func testTwoIdenticalRowsInAFileAreTwoExpenses() throws {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let uber = ExpenseRecord(date: date, merchant: "Uber", amount: 100, currency: "MXN")
        let csv = CSVExporter.csv(from: [uber, uber])
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context),
                       .init(added: 2, alreadyThere: 0, unreadable: 0))
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context),
                       .init(added: 0, alreadyThere: 2, unreadable: 0))
        XCTAssertEqual(try all().count, 2)
    }

    func testTheSameMomentOnAnotherCardIsAnotherExpense() throws {
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        context.insert(Expense(amount: 100, currencyMarker: "MXN", merchant: "Uber", card: "Amex", date: date))
        try context.save()
        let csv = CSVExporter.csv(from: [ExpenseRecord(date: date, merchant: "Uber", amount: 100, currency: "MXN", card: "BBVA")])
        // It may be another expense or the same one with the card changed: only the person can
        // tell (2026-11-11). Asked for, it comes in; by default it is left out and said.
        XCTAssertEqual(try ExpenseImporter.preview(csv, in: context).leftOut, 1)
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context),
                       .init(added: 0, alreadyThere: 0, unreadable: 0, leftOut: 1))
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context, repeated: .add).added, 1)
        XCTAssertEqual(try all().count, 2)
    }

    // MARK: 2026-11-11 · Un CSV viejo después de renombrar

    private let moment = Date(timeIntervalSince1970: 1_792_000_000)

    /// Lo que se exportó antes de renombrar la tarjeta y corregir un comercio.
    private var oldExport: String {
        CSVExporter.csv(from: [
            ExpenseRecord(date: moment, merchant: "Uber", amount: 100, currency: "MXN", card: "American Express México"),
            ExpenseRecord(date: moment.addingTimeInterval(60), merchant: "REST BORU OUM 0234", amount: 175, currency: "MXN",
                          card: "American Express México"),
        ])
    }

    func testAnOldExportAfterRenamingACardDoesNotDuplicate() throws {
        // Hoy los dos gastos dicen «Amex» («Pagos y categorías» renombra en masa y lo recuerda).
        context.insert(Expense(amount: 100, currencyMarker: "MXN", merchant: "Uber", card: "Amex", date: moment))
        context.insert(Expense(amount: 175, currencyMarker: "MXN", merchant: "REST BORU OUM 0234", card: "Amex",
                               date: moment.addingTimeInterval(60)))
        try context.save()
        var cards = MerchantRenames()
        cards.rename("American Express México", to: "Amex")
        XCTAssertEqual(try ExpenseImporter.importCSV(oldExport, into: context, merchantRenames: MerchantRenames(), cardRenames: cards),
                       .init(added: 0, alreadyThere: 2, unreadable: 0, leftOut: 0))
        XCTAssertEqual(try all().count, 2)
    }

    func testAnOldExportAfterCorrectingAMerchantDoesNotDuplicate() throws {
        // El nombre se corrigió en la hoja del gasto: cambia `merchant` y Al día recuerda el cambio.
        let boru = Expense(amount: 175, currencyMarker: "MXN", merchant: "Boru Oum", card: "American Express México",
                           date: moment.addingTimeInterval(60))
        boru.displayName = "Boru Oum"
        // Un pago de Wallet con nombre legible: `merchant` sigue igual, `displayName` es el que se ve.
        let uber = Expense(amount: 100, currencyMarker: "MXN", merchant: "UBER *TRIP HELP.UBER.COM",
                           card: "American Express México", date: moment)
        uber.displayName = "Uber"
        context.insert(boru)
        context.insert(uber)
        try context.save()
        var merchants = MerchantRenames()
        merchants.rename("REST BORU OUM 0234", to: "Boru Oum")
        XCTAssertEqual(try ExpenseImporter.importCSV(oldExport, into: context, merchantRenames: merchants, cardRenames: MerchantRenames()),
                       .init(added: 0, alreadyThere: 2, unreadable: 0, leftOut: 0))
        XCTAssertEqual(try all().count, 2)
    }

    func testRowsThatLookRepeatedAreAskedAbout_AndLeftOutByDefault() throws {
        // Sin recuerdo del cambio (se renombró en otro iPhone, o el archivo se editó en una hoja de cálculo).
        context.insert(Expense(amount: 100, currencyMarker: "MXN", merchant: "Uber", card: "Amex", date: moment))
        try context.save()
        let csv = CSVExporter.csv(from: [
            ExpenseRecord(date: moment, merchant: "Uber", amount: 100, currency: "MXN", card: "American Express México"),
            ExpenseRecord(date: moment.addingTimeInterval(300), merchant: "Cine", amount: 180, currency: "MXN"),
        ])
        let none = MerchantRenames()
        let preview = try ExpenseImporter.preview(csv, in: context, merchantRenames: none, cardRenames: none)
        XCTAssertEqual(preview, .init(added: 1, alreadyThere: 0, unreadable: 0, leftOut: 1))
        XCTAssertEqual(try all().count, 1, "Ver qué haría no guarda nada")

        let summary = try ExpenseImporter.importCSV(csv, into: context, merchantRenames: none, cardRenames: none)
        XCTAssertEqual(summary, .init(added: 1, alreadyThere: 0, unreadable: 0, leftOut: 1))
        XCTAssertEqual(try all().map(\.merchant), ["Uber", "Cine"], "Solo los nuevos")
        XCTAssertEqual(summary.text, "Se agregó 1 gasto. 1 se dejó fuera por parecer repetido.")
        // Otra vez el mismo archivo: lo nuevo ya está y lo dudoso sigue fuera.
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context, merchantRenames: none, cardRenames: none),
                       .init(added: 0, alreadyThere: 1, unreadable: 0, leftOut: 1))
    }

    func testAgregarTodosBringsTheOnesThatLookRepeatedToo() throws {
        context.insert(Expense(amount: 100, currencyMarker: "MXN", merchant: "Uber", card: "Amex", date: moment))
        try context.save()
        let csv = CSVExporter.csv(from: [
            ExpenseRecord(date: moment, merchant: "Uber", amount: 100, currency: "MXN", card: "BBVA"),
            ExpenseRecord(date: moment.addingTimeInterval(300), merchant: "Cine", amount: 180, currency: "MXN"),
        ])
        let none = MerchantRenames()
        let summary = try ExpenseImporter.importCSV(csv, into: context, repeated: .add, merchantRenames: none, cardRenames: none)
        XCTAssertEqual(summary, .init(added: 2, alreadyThere: 0, unreadable: 0, leftOut: 0))
        XCTAssertEqual(try all().count, 3)
        // Ya con los dos, el archivo no trae nada nuevo ni dudoso.
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context, merchantRenames: none, cardRenames: none),
                       .init(added: 0, alreadyThere: 2, unreadable: 0, leftOut: 0))
    }

    func testTheWordsOfTheQuestionAndTheResult() {
        XCTAssertEqual(ExpenseImporter.Question(looksRepeated: 12).message,
                       "12 parecen repetidos: mismo día, hora y monto que gastos que ya tienes, con otro nombre o tarjeta. ¿Agregarlos también?")
        XCTAssertEqual(ExpenseImporter.Question(looksRepeated: 1).message,
                       "1 parece repetido: mismo día, hora y monto que un gasto que ya tienes, con otro nombre o tarjeta. ¿Agregarlo también?")
        XCTAssertEqual(ExpenseImporter.Summary(added: 30, alreadyThere: 5, unreadable: 1, leftOut: 12).text,
                       "Se agregaron 30 gastos. 5 ya estaban. 12 se dejaron fuera por parecer repetidos. 1 renglón no se pudo leer.")
        XCTAssertEqual(ExpenseImporter.Summary(added: 0, alreadyThere: 1, unreadable: 0, leftOut: 0).text,
                       "Se agregaron 0 gastos. 1 ya estaba.")
    }

    /// «Cuenta» from another spreadsheet (an account number, a 1 for yes) is not a part.
    func testANumberUnderCuentaThatIsNoPartMeansItCounts() throws {
        let csv = """
        Fecha,Comercio,Monto,Moneda,Tarjeta,Categoría,Cuenta,Motivo
        2026-10-01T12:00:00-06:00,Oxxo,89.00,MXN,,,0123456789,
        2026-10-02T12:00:00-06:00,Uber,100.00,MXN,,,1,
        2026-10-03T12:00:00-06:00,Cena,600.00,MXN,,,300.00,
        """
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context).added, 3)
        let rows = try all()
        XCTAssertNil(rows[0].countedAmount)
        XCTAssertNil(rows[1].countedAmount)
        XCTAssertEqual(rows[2].countedAmount, 300)
    }

    /// A Wallet capture carries fractions of a second; the export drops them. Re-importing
    /// the export must still recognize it (rounding put :20.7 at :21 and duplicated it).
    func testAFractionOfASecondDoesNotDuplicate() throws {
        let date = Date(timeIntervalSince1970: 1_792_000_020.7)
        context.insert(Expense(amount: 89, currencyMarker: "MXN", merchant: "Oxxo", date: date))
        try context.save()
        let csv = CSVExporter.csv(from: [ExpenseRecord(date: date, merchant: "Oxxo", amount: 89, currency: "MXN")])
        XCTAssertEqual(try ExpenseImporter.importCSV(csv, into: context),
                       .init(added: 0, alreadyThere: 1, unreadable: 0))
    }

    /// A row without a category gets the one the owner chose; one with a category keeps it.
    func testRowsWithoutCategoryGetTheRememberedOne() throws {
        let day = Date(timeIntervalSince1970: 1_792_000_000)
        context.insert(Expense(amount: 50, currencyMarker: "MXN", merchant: "Oxxo", date: day, category: "Despensa"))
        try context.save()
        var rules = CategoryRules()
        rules.learn("Comida", for: "Boru Oum")
        rules.learn("Mascotas", for: "Petco")
        let csv = CSVExporter.csv(from: [
            ExpenseRecord(date: day.addingTimeInterval(60), merchant: "OXXO", amount: 89, currency: "MXN"),
            ExpenseRecord(date: day.addingTimeInterval(120), merchant: "Oxxo", amount: 30, currency: "MXN",
                          category: "Antojos"),
            ExpenseRecord(date: day.addingTimeInterval(180), merchant: "boru oum", amount: 175, currency: "MXN"),
            ExpenseRecord(date: day.addingTimeInterval(240), merchant: "Petco", amount: 300, currency: "MXN"),
            ExpenseRecord(date: day.addingTimeInterval(300), merchant: "Uber", amount: 120, currency: "MXN"),
        ])
        _ = try ExpenseImporter.importCSV(csv, into: context, rules: rules, hidden: ["Mascotas"])
        // Oxxo's newest choice in the app or the file is Antojos; Mascotas was deleted; Uber was
        // never filed (the catalog does not guess on an import).
        XCTAssertEqual(try all().map(\.category), ["Despensa", "Antojos", "Antojos", "Comida", nil, nil])
    }
}
