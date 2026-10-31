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

        let payload = try DailyBackup.snapshot(in: source.mainContext, moneyContainer: nil)
        let file = try BackupSeal.seal(payload, password: "prueba-clave", rounds: 1_000)
        let opened = try BackupSeal.open(file, password: "prueba-clave")

        let target = try container()
        try DailyBackup.restore(opened, into: target, money: nil)
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
        try DailyBackup.restore(payload, into: target, money: nil)
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
        XCTAssertThrowsError(try DailyBackup.restore(payload, into: target, money: nil))
        XCTAssertEqual(try all(target).map(\.merchant), ["Se queda"])
    }

    func testMiDineroTravelsAndComesBackWhole() throws {
        let money = try MoneyStore.inMemory()
        let context = ModelContext(money)
        let cetes = MoneyAccount(name: "CETES", kind: .account, currency: "MXN", yearlyRate: Decimal(string: "9.8"))
        let dollars = MoneyAccount(name: "Dólares", kind: .account, currency: "USD")
        let amex = MoneyAccount(name: "Amex", kind: .debt, currency: "MXN")
        try MoneyStore.add(cetes, balance: Decimal(string: "150000.01")!, rate: nil, in: context, mainCurrency: "MXN")
        try MoneyStore.add(dollars, balance: 2_000, rate: 19, in: context, mainCurrency: "MXN")
        try MoneyStore.add(amex, balance: 6_420, rate: nil, in: context, mainCurrency: "MXN")
        let before = try XCTUnwrap(MoneyStore.latestCut(in: context)).netWorth.total
        XCTAssertEqual(before, Decimal(string: "181580.01"))

        let expenses = try container()
        let payload = try DailyBackup.snapshot(in: expenses.mainContext, moneyContainer: money)
        XCTAssertEqual(payload.money?.accounts.count, 3)
        let opened = try BackupSeal.open(try BackupSeal.seal(payload, password: "clave-prueba", rounds: 1_000),
                                         password: "clave-prueba")

        let elsewhere = try MoneyStore.inMemory()
        try DailyBackup.restore(opened, into: try container(), money: elsewhere)
        let back = try XCTUnwrap(MoneyStore.latestCut(in: ModelContext(elsewhere)))
        XCTAssertEqual(back.netWorth.total, before)
        XCTAssertEqual(back.rateTable, ["USD": 19])
    }

    func testAnOldBackupLeavesMiDineroAlone() throws {
        let money = try MoneyStore.inMemory()
        try MoneyStore.add(MoneyAccount(name: "Nu", kind: .account, currency: "MXN"), balance: 500, rate: nil,
                           in: ModelContext(money), mainCurrency: "MXN")
        let payload = BackupPayload(createdAt: .now, writtenBy: "prueba", expenses: [],
                                    settings: DailyBackup.Settings.current(), money: nil)
        try DailyBackup.restore(payload, into: try container(), money: money)
        XCTAssertEqual(MoneyStore.latestCut(in: ModelContext(money))?.netWorth.total, 500)
    }

    func testADraftNeverCountsAndOneCutPerMonth() throws {
        let money = try MoneyStore.inMemory()
        let context = ModelContext(money)
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        try MoneyStore.add(nu, balance: 1_000, rate: nil, in: context, mainCurrency: "MXN")
        let draft = try MoneyStore.draftForThisMonth(in: context, mainCurrency: "MXN")
        XCTAssertEqual(draft.entry(for: nu)?.reviewed, false)
        draft.entry(for: nu)?.balance = 9_999
        try context.save()
        // The draft is still a draft: the net worth is the finished cut's.
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.netWorth.total, 1_000)
        XCTAssertEqual(try MoneyStore.draftForThisMonth(in: context, mainCurrency: "MXN").id, draft.id)
        try MoneyStore.finish(draft, in: context)
        XCTAssertEqual(try context.fetch(MoneyCut.finished).count, 1)
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.netWorth.total, 9_999)
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
