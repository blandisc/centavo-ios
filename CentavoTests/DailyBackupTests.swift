import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

@MainActor
final class DailyBackupTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Expense.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func all(_ container: ModelContainer) throws -> [Expense] {
        try ModelContext(container).fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    /// Every field set to something, so a field the backup forgets shows up here.
    private func fullExpense() -> Expense {
        let expense = Expense(amount: Decimal(string: "1234.56")!, currencyMarker: "US$", merchant: "CLIP*MX TAQ GUERO 02",
                              card: "Amex", date: Date(timeIntervalSinceReferenceDate: 783_456_789.25),
                              category: "Comida", rawAmount: "US$1,234.56")
        expense.rawNotice = "Pagaste US$1,234.56"
        expense.latitude = 25.686_614
        expense.longitude = -100.316_113
        expense.placeName = "San Pedro"
        expense.repeatsMonthly = true
        expense.repeatsThrough = Date(timeIntervalSinceReferenceDate: 783_000_000)
        expense.repeatDay = 31
        expense.repeatRule = "cada-2-meses"
        expense.isRepeat = false
        expense.displayName = "Taquería El Güero"
        expense.categorySource = Expense.suggestedCategory
        expense.countedAmount = Decimal(string: "0.1")
        expense.uncountedReason = "reembolso"
        return expense
    }

    func testEveryFieldComesBackFromALockedFile() throws {
        let source = try container()
        source.mainContext.insert(fullExpense())
        try source.mainContext.save()

        let payload = try DailyBackup.snapshot(in: source.mainContext)
        let file = try BackupSeal.seal(payload, password: "prueba-clave", rounds: 1_000)
        let opened = try BackupSeal.open(file, password: "prueba-clave")

        let target = try container()
        try DailyBackup.restore(opened, into: target)
        let original = try XCTUnwrap(all(source).first)
        let back = try XCTUnwrap(all(target).first)
        XCTAssertEqual(back.backedUp, original.backedUp)
        XCTAssertEqual(back.amount, Decimal(string: "1234.56"))
        XCTAssertEqual(back.countedAmount, Decimal(string: "0.1"))
        XCTAssertEqual(back.date, original.date)
    }

    func testRestoringReplacesWhatWasThere() throws {
        let target = try container()
        target.mainContext.insert(Expense(amount: 50, merchant: "Viejo"))
        try target.mainContext.save()

        var row = BackupExpense(amount: 99, date: .now, merchant: "Nuevo")
        row.category = "Súper"
        let payload = BackupPayload(createdAt: .now, writtenBy: "prueba", expenses: [row],
                                    settings: DailyBackup.Settings.current())
        try DailyBackup.restore(payload, into: target)
        XCTAssertEqual(try all(target).map(\.merchant), ["Nuevo"])
    }

    func testADamagedAmountChangesNothing() throws {
        let target = try container()
        target.mainContext.insert(Expense(amount: 50, merchant: "Se queda"))
        try target.mainContext.save()

        var broken = BackupExpense(amount: 1, date: .now, merchant: "Roto")
        broken.amount = "12,5OO"
        let payload = BackupPayload(createdAt: .now, writtenBy: "prueba", expenses: [broken],
                                    settings: DailyBackup.Settings.current())
        XCTAssertThrowsError(try DailyBackup.restore(payload, into: target))
        XCTAssertEqual(try all(target).map(\.merchant), ["Se queda"])
    }

    func testOnlyTheAppsOwnSettingsTravel() {
        XCTAssertTrue(DailyBackup.Settings.isOurs("monthlyBudget"))
        XCTAssertFalse(DailyBackup.Settings.isOurs(DailyBackup.folderKey))
        XCTAssertFalse(DailyBackup.Settings.isOurs(DailyBackup.lastKey))
        XCTAssertFalse(DailyBackup.Settings.isOurs("AppleLanguages"))
        XCTAssertEqual(DailyBackup.Settings.setting(true as NSNumber), .flag(true))
        XCTAssertEqual(DailyBackup.Settings.setting(3 as NSNumber), .whole(3))
        XCTAssertEqual(DailyBackup.Settings.setting(0.5 as NSNumber), .number(0.5))
        XCTAssertNil(DailyBackup.Settings.setting(Data()))
    }
}
