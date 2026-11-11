import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// Nothing a model keeps may be left out of the backup by accident (2026-11-11).
///
/// A property added to `Expense`, or to one of the four «Mi dinero» models, and forgotten in
/// `backedUp` / `init(backup:)` (or in `moneySnapshot` / `restoreMoney`) would be lost in every
/// restore, and in every «Deshacer» too (`DeletedExpense` keeps the same row). These tests read
/// the stored properties from the SwiftData schema itself and compare them with what the backup
/// really writes, so adding a property fails here until it travels or is listed, with its
/// reason, among the ones that stay on purpose.
@MainActor
final class BackupCoverageTests: XCTestCase {
    private let day = Date(timeIntervalSinceReferenceDate: 783_456_789)

    /// The stored properties (attributes and relationships) of a model, as SwiftData sees them.
    private func stored(_ model: any PersistentModel.Type, named name: String) throws -> Set<String> {
        let entity = try XCTUnwrap(Schema([model]).entities.first { $0.name == name }, "No hay modelo «\(name)»")
        return Set(entity.attributes.map(\.name)).union(entity.relationships.map(\.name))
    }

    /// The keys a backup row writes. A field left empty isn't written, so every field of the
    /// row has to be filled for its key to show.
    private func written<Row: Encodable>(_ row: Row) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row))
        return Set(try XCTUnwrap(object as? [String: Any]).keys)
    }

    // MARK: Gastos

    /// Every stored property set to something that isn't its default. **A new property goes here
    /// too**: the test below fails until it does.
    private func everyFieldSet() -> Expense {
        let expense = Expense(amount: Decimal(string: "1234.56")!, currencyMarker: "US$", merchant: "CLIP*MX TAQ GUERO 02",
                              card: "Amex", date: day, category: "Comida", rawAmount: "US$1,234.56")
        expense.rawNotice = "Pagaste US$1,234.56"
        expense.latitude = 25.686_614
        expense.longitude = -100.316_113
        expense.placeName = "San Pedro"
        expense.repeatsMonthly = true
        expense.repeatsThrough = day.addingTimeInterval(86_400)
        expense.repeatDay = 31
        expense.repeatRule = "cada-2-meses"
        expense.isRepeat = true
        expense.fixedID = "fijo-1"
        expense.fixedOf = "fijo-0"
        expense.maybeRepeated = true
        expense.displayName = "Taquería El Güero"
        expense.categorySource = Expense.suggestedCategory
        expense.countedAmount = Decimal(string: "0.1")
        expense.uncountedReason = "reembolso"
        return expense
    }

    /// Stored properties of `Expense` that stay out of the backup on purpose, each with its
    /// reason. None today: everything an expense keeps travels.
    private let expenseStaysOut: [String: String] = [:]

    func testEveryStoredPropertyOfAnExpenseTravels() throws {
        let properties = try stored(Expense.self, named: "Expense")
        XCTAssertFalse(properties.isEmpty)
        let row = everyFieldSet().backedUp
        let keys = try written(row)
        let expected = properties.subtracting(expenseStaysOut.keys)

        XCTAssertEqual(expected.subtracting(keys), [],
                       "Propiedades de Expense que el respaldo no escribe: agrégalas a BackupExpense, a `backedUp` y a `init(backup:)`, y dales un valor en `everyFieldSet()`. Si de verdad no deben viajar, anótalas en `expenseStaysOut` con su motivo.")
        XCTAssertEqual(keys.subtracting(expected), [],
                       "El respaldo escribe campos que Expense ya no guarda (¿se renombró una propiedad?).")
        XCTAssertEqual(Set(expenseStaysOut.keys).subtracting(properties), [], "`expenseStaysOut` nombra algo que ya no existe.")
    }

    /// And back: what `init(backup:)` forgets comes back empty, so its key is gone from the
    /// second row. This is also what «Deshacer» does.
    func testEveryStoredPropertyOfAnExpenseComesBack() throws {
        let row = everyFieldSet().backedUp
        let back = try Expense(backup: row).backedUp
        XCTAssertEqual(try written(row).subtracting(try written(back)), [],
                       "Campos que `Expense.init(backup:)` no restaura.")
        XCTAssertEqual(back, row)

        let undone = try XCTUnwrap(DeletedExpense(everyFieldSet()).make())
        XCTAssertEqual(undone.backedUp, row, "«Deshacer» regresa el gasto con todos sus campos")
    }

    // MARK: Mi dinero

    /// Model property → the key it travels under in the backup's row.
    private let accountKeys = ["id": "id", "name": "name", "kindRaw": "kind", "currency": "currency",
                               "yearlyRate": "yearlyRate", "order": "order", "archived": "archived",
                               "createdAt": "createdAt", "institution": "institution", "subtype": "subtype"]
    /// On purpose: the lines travel from the cut's side (`BackupMoney.Cut.entries`), each naming
    /// its account; the account's own list is only the other end of that relationship.
    private let accountStaysOut = ["entries": "viaja dentro de cada corte"]

    private let cutKeys = ["id": "id", "month": "month", "date": "date", "mainCurrency": "mainCurrency",
                           "rates": "rates", "entries": "entries", "reviewedRates": "reviewedRates"]
    /// On purpose: it isn't a field of the row. A finished cut goes in `BackupMoney.cuts` and one
    /// left half-done in `BackupMoney.drafts`, and restoring reads it from there.
    private let cutStaysOut = ["isDraft": "lo dice la lista en la que viaja (cuts o drafts)"]

    private let entryKeys = ["balance": "balance", "yieldOverride": "yieldOverride", "movement": "movement",
                             "reviewed": "reviewed", "account": "account"]
    /// On purpose: a line is written inside its cut, so the cut isn't named again.
    private let entryStaysOut = ["cut": "viaja dentro de su corte"]

    private let incomeKeys = ["id": "id", "name": "name", "institution": "institution", "amount": "amount",
                              "currency": "currency", "since": "since", "archived": "archived",
                              "createdAt": "createdAt", "until": "until"]
    private let incomeStaysOut: [String: String] = [:]

    /// «Mi dinero» with every stored property of its four models set: an account, a finished
    /// cut, one left half-done (only a draft carries `reviewedRates`) and an income.
    private func everyMoneyFieldSet() throws -> ModelContainer {
        let container = try MoneyStore.inMemory()
        let context = ModelContext(container)
        let account = MoneyAccount(name: "GBM", kind: .account, currency: "USD", yearlyRate: Decimal(string: "9.8"), order: 2)
        account.archived = true
        account.createdAt = day
        account.institution = "GBM"
        account.subtype = MoneySubtype.investment.rawValue
        context.insert(account)
        for (month, isDraft) in [("2026-10", false), ("2026-11", true)] {
            let cut = MoneyCut(month: month, date: day.addingTimeInterval(isDraft ? 86_400 : 0), mainCurrency: "MXN", isDraft: isDraft)
            cut.rates = "USD=18.5"
            if isDraft { cut.reviewedRates = "USD" }
            context.insert(cut)
            let entry = MoneyEntry(balance: Decimal(string: "1000.55")!, account: account, reviewed: true)
            entry.yieldOverride = Decimal(string: "12.5")
            entry.movement = -300
            context.insert(entry)
            entry.cut = cut
        }
        let income = MoneyIncome(name: "Sueldo", institution: "Arca", amount: 60_000, currency: "MXN", since: day)
        income.archived = true
        income.createdAt = day
        income.until = day.addingTimeInterval(86_400)
        context.insert(income)
        try context.save()
        return container
    }

    private func check(_ model: any PersistentModel.Type, named name: String, travels: [String: String],
                       staysOut: [String: String], written keys: Set<String>, line: UInt = #line) throws {
        let properties = try stored(model, named: name)
        XCTAssertEqual(properties.subtracting(travels.keys).subtracting(staysOut.keys), [],
                       "Propiedades de \(name) que el respaldo no conoce: agrégalas a BackupMoney, a `moneySnapshot` y a `restoreMoney`, y a la tabla de esta prueba. Si de verdad no deben viajar, anótalas con su motivo.",
                       line: line)
        XCTAssertEqual(Set(travels.keys).union(staysOut.keys).subtracting(properties), [],
                       "La tabla de \(name) nombra propiedades que ya no existen.", line: line)
        XCTAssertEqual(Set(travels.values).subtracting(keys), [],
                       "Campos de \(name) que `moneySnapshot` no escribe.", line: line)
        XCTAssertEqual(keys.subtracting(travels.values), [],
                       "El respaldo escribe campos de \(name) que la tabla de esta prueba no tiene.", line: line)
    }

    func testEveryStoredPropertyOfMiDineroTravels() throws {
        XCTAssertEqual(MoneyStore.models.count, 4, "Hay un modelo nuevo en «Mi dinero»: agrégalo al respaldo y a esta prueba.")
        let money = try XCTUnwrap(DailyBackup.moneySnapshot(try everyMoneyFieldSet(), drafts: true))
        let account = try XCTUnwrap(money.accounts.first)
        let cut = try XCTUnwrap(money.cuts.first)
        let draft = try XCTUnwrap(money.drafts?.first)
        let entry = try XCTUnwrap(cut.entries.first)
        let income = try XCTUnwrap(money.incomes?.first)

        try check(MoneyAccount.self, named: "MoneyAccount", travels: accountKeys, staysOut: accountStaysOut,
                  written: try written(account))
        // Between the finished cut and the draft every key shows (`reviewedRates` only in a draft).
        try check(MoneyCut.self, named: "MoneyCut", travels: cutKeys, staysOut: cutStaysOut,
                  written: try written(cut).union(try written(draft)))
        try check(MoneyEntry.self, named: "MoneyEntry", travels: entryKeys, staysOut: entryStaysOut,
                  written: try written(entry))
        try check(MoneyIncome.self, named: "MoneyIncome", travels: incomeKeys, staysOut: incomeStaysOut,
                  written: try written(income))
    }

    /// And back: restored into an empty «Mi dinero» and read again, it's the same, field for field.
    func testEveryStoredPropertyOfMiDineroComesBack() throws {
        let money = try XCTUnwrap(DailyBackup.moneySnapshot(try everyMoneyFieldSet(), drafts: true))
        let elsewhere = try MoneyStore.inMemory()
        try DailyBackup.restoreMoney(money, into: elsewhere)
        let back = try XCTUnwrap(DailyBackup.moneySnapshot(elsewhere, drafts: true))
        XCTAssertEqual(back, money)
        XCTAssertEqual(back.drafts?.count, 1)
        XCTAssertEqual(back.cuts.count, 1)
    }
}
