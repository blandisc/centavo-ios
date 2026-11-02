import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// Segunda auditoría (2026-11-02), parte de datos: guardado, captura, fijos y respaldo. Cada
/// prueba reproduce una falla encontrada, contra un almacén en memoria.
@MainActor
final class SecondAuditDataTests: XCTestCase {
    private var context: ModelContext!
    private let calendar = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// `logDue` also starts the plans in the app's settings: none from the simulator.
    private var savedPlans: [FixedPlan] = []

    override func setUpWithError() throws {
        savedPlans = FixedPlan.saved
        FixedPlan.save([])
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        FixedPlan.save(savedPlans)
    }

    private func at(_ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func all() throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    private func original(_ merchant: String, _ amount: Decimal, on date: Date) -> Expense {
        let expense = Expense(amount: amount, currencyMarker: "MXN", merchant: merchant, date: date)
        expense.repeatsMonthly = true
        expense.repeatsThrough = date
        context.insert(expense)
        return expense
    }

    // MARK: Captura

    /// 11. The same payment through «Transacción» and «Notificación», each with its own text.
    func testThePaymentThroughBothAutomationsIsMarked() throws {
        let first = try ExpenseRecorder.record(amountText: "$89.00", merchant: "OXXO ROBLE MTY", card: "Amex",
                                               in: context, primary: "MXN", rules: CategoryRules(), hidden: [],
                                               renames: MerchantRenames(), now: now)
        XCTAssertEqual(first, .saved(merchant: "OXXO ROBLE MTY"))
        let second = try ExpenseRecorder.record(amountText: "MXN 89.00", merchant: "Oxxo", card: "American Express México",
                                                rawNotice: "American Express México\nOxxo\nMXN 89.00",
                                                in: context, primary: "MXN", rules: CategoryRules(), hidden: [],
                                                renames: MerchantRenames(), now: now.addingTimeInterval(40))
        XCTAssertEqual(second, .maybeRepeated(merchant: "Oxxo"))
        XCTAssertEqual(try all().count, 2, "Se guarda marcada, nunca se descarta")
    }

    /// 19. A merchant named by hand isn't turned back into what the notice said.
    func testTheRepairLeavesANameWrittenByHand() throws {
        let notice = "Ahora\nAmerican Express México\nMXN 1,060.00\nLa Docena"
        try ExpenseRecorder.record(amountText: "MXN 1,060.00", merchant: "American Express México",
                                   card: nil, rawNotice: notice, in: context, renames: MerchantRenames(), now: now)
        let expense = try XCTUnwrap(all().first)
        expense.displayName = "Cena con Ana"
        try context.save()
        XCTAssertEqual(try ExpenseRecorder.repairBankMerchants(in: context, knownCards: [], defaults: nil), 0)
        XCTAssertEqual(expense.shownName, "Cena con Ana")
        XCTAssertEqual(expense.merchant, "American Express México")
    }

    // MARK: Fijos

    /// 12. Two originals of one fixed expense (two devices): one stays, the same everywhere,
    /// with the furthest progress.
    func testTwinOriginalsLeaveTheSameOne() throws {
        let early = original("Renta", 8_000, on: at(10, 1))
        let late = original("Renta", 8_000, on: at(10, 1).addingTimeInterval(0.000_3))
        early.fixedID = "renta"
        late.fixedID = "renta"
        late.repeatsThrough = at(11, 1)
        try context.save()
        try RecurringExpenses.logDue(in: context, now: at(11, 2))
        let originals = try all().filter { $0.repeatsMonthly == true }
        XCTAssertEqual(originals.count, 1)
        XCTAssertEqual(originals.first?.date, at(10, 1), "Se queda la de fecha menor")
        XCTAssertEqual(originals.first?.repeatsThrough, at(11, 1))
        XCTAssertEqual(try all().filter { $0.isRepeat == true }.count, 0, "Noviembre ya estaba anotado")
    }

    /// 12. Nothing tells them apart: neither is deleted (another device could delete the other).
    func testIdenticalTwinsAreBothKept() throws {
        for _ in 0..<2 { original("Gym", 500, on: at(10, 10)).fixedID = "gym" }
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(11, 30)), 1)
        XCTAssertEqual(try all().filter { $0.repeatsMonthly == true }.count, 2)
    }

    /// 12. A plan two devices started now leaves one original.
    func testAPlanStartedTwiceLeavesOneOriginal() throws {
        let plan = FixedPlan(merchant: "Gym", amount: "500", currency: "MXN", category: nil, rule: nil, firstDate: at(8, 10))
        context.insert(RecurringExpenses.original(from: plan))
        context.insert(RecurringExpenses.original(from: plan))
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(9, 30)), 1)
        XCTAssertEqual(try all().filter { $0.repeatsMonthly == true }.count, 1)
    }

    /// 12. The plan leaves the settings only once its original is saved.
    func testAPlanLeavesTheSettingsOnceSaved() throws {
        let plan = FixedPlan(merchant: "Colegio", amount: "5000", currency: "MXN", category: nil, rule: nil,
                             firstDate: at(10, 5))
        FixedPlan.save([plan])
        try RecurringExpenses.logDue(in: context, now: at(10, 6))
        XCTAssertTrue(FixedPlan.saved.isEmpty)
        XCTAssertEqual(try all().first?.fixedID, plan.id.uuidString)
        // A plan another device already started isn't started twice.
        FixedPlan.save([plan])
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(10, 7)), 0)
        XCTAssertEqual(try all().filter { $0.repeatsMonthly == true }.count, 1)
    }

    /// 13. Moving a fixed expense's date never logs a copy on its own day.
    func testMovingTheDateNeverRepeatsOnItsOwnDay() throws {
        let gym = original("Gym", 500, on: at(10, 1))
        gym.repeatRule = RepeatRule.weeks(1).stored
        try RecurringExpenses.logDue(in: context, now: at(10, 2))
        gym.date = at(10, 3)
        gym.repeatsThrough = RecurringExpenses.repeatsThrough(for: gym.date, rule: gym.rule, day: nil, wasRepeating: true,
                                                              current: gym.repeatsThrough, now: at(10, 4))
        try RecurringExpenses.logDue(in: context, now: at(10, 4))
        XCTAssertFalse(try all().contains { $0.isRepeat == true && calendar.isDate($0.date, inSameDayAs: at(10, 3)) })
    }

    /// 14. Netflix of Oct 25 marked as «Cada mes» on Nov 10: Nov 25 is logged.
    func testMarkingAnOldExpenseLogsThisMonthsCharge() throws {
        let netflix = Expense(amount: 299, currencyMarker: "MXN", merchant: "Netflix", date: at(10, 25))
        context.insert(netflix)
        netflix.repeatsMonthly = true
        netflix.repeatDay = 25
        netflix.repeatsThrough = RecurringExpenses.repeatsThrough(for: netflix.date, rule: .monthly, day: 25,
                                                                  wasRepeating: false, current: nil, now: at(11, 10))
        try context.save()
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(11, 26)), 1)
        XCTAssertEqual(try all().filter { $0.isRepeat == true }.map(\.date), [at(11, 25)])
    }

    /// 15. «Dejar de repetir» keeps this month's rent as a fixed charge, and logs nothing more.
    func testStoppingKeepsTheOriginalAsAFixedCharge() throws {
        let rent = original("Renta", 8_000, on: at(11, 1))
        try RecurringExpenses.logDue(in: context, now: at(11, 10))
        RecurringExpenses.stopRepeating(rent)
        try context.save()
        XCTAssertTrue(rent.isFixed, "Sigue contando como fijo ya cobrado")
        XCTAssertNil(rent.repeatsMonthly)
        XCTAssertEqual(try RecurringExpenses.logDue(in: context, now: at(12, 31)), 0)
    }

    /// 16. «Dejar de repetir» from a copy finds its own original, not another with the same name.
    func testTheOriginalOfACopyIsFoundByItsID() throws {
        let first = original("Colegio", 5_000, on: at(8, 5))
        let second = original("Colegio", 5_000, on: at(8, 5))
        first.fixedID = "a"
        second.fixedID = "b"
        let copy = Expense(amount: 5_000, currencyMarker: "MXN", merchant: "Colegio", date: at(9, 5))
        copy.isRepeat = true
        copy.fixedOf = "b"
        context.insert(copy)
        try context.save()
        XCTAssertTrue(RecurringExpenses.original(of: copy, in: context) === second)
        // A copy from before ids still finds one by merchant and amount.
        copy.fixedOf = nil
        XCTAssertNotNil(RecurringExpenses.original(of: copy, in: context))
    }

    // MARK: Respaldo

    /// 1. A store that doesn't open is moved aside with its journals, never deleted.
    func testADamagedStoreIsSetAsideWhole() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "aparte-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = folder.appending(path: "dinero.store")
        for suffix in ["", "-wal", "-shm"] {
            try Data("x\(suffix)".utf8).write(to: folder.appending(path: "dinero.store" + suffix))
        }
        try DailyBackup.setAsideMoneyFiles(at: store, now: now)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        XCTAssertFalse(names.contains("dinero.store"))
        XCTAssertFalse(names.contains("dinero.store-wal"))
        let base = "dinero.store.danado-" + BackupRetention.stamp(now, withTime: true)
        XCTAssertEqual(Set(names), [base, base + "-wal", base + "-shm"])
    }

    /// 4. The copy before a restore keeps a cut left half-done, and restoring it brings it back.
    func testTheSafetyCopyKeepsADraft() throws {
        let money = try MoneyStore.inMemory()
        let moneyContext = ModelContext(money)
        let nu = MoneyAccount(name: "Nu", kind: .account, currency: "MXN")
        try MoneyStore.add(nu, balance: 1_000, rate: nil, in: moneyContext, mainCurrency: "MXN")
        let draft = try MoneyStore.draftForThisMonth(in: moneyContext, mainCurrency: "MXN")
        draft.entry(for: nu)?.balance = 1_234
        draft.entry(for: nu)?.reviewed = true
        try moneyContext.save()

        let daily = try DailyBackup.snapshot(in: context, moneyContainer: money)
        XCTAssertNil(daily.money?.drafts, "El respaldo diario deja fuera los borradores")
        let copy = try DailyBackup.snapshot(in: context, moneyContainer: money, drafts: true)
        XCTAssertEqual(copy.money?.drafts?.count, 1)

        let elsewhere = try MoneyStore.inMemory()
        try DailyBackup.restore(copy, into: context.container, money: elsewhere)
        let back = try MoneyStore.drafts(in: ModelContext(elsewhere))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.entries?.first?.balance, 1_234)
        XCTAssertEqual(back.first?.entries?.first?.reviewed, true)
        XCTAssertEqual(MoneyStore.latestCut(in: ModelContext(elsewhere))?.netWorth.total, 1_000, "El borrador no cuenta")
    }

    /// 2. A file iCloud hasn't brought down yet still counts as today's.
    func testAFileOnlyInICloudIsSeen() {
        XCTAssertEqual(DailyBackup.visibleName(".al-dia-2026-11-01.aldia.icloud"), "al-dia-2026-11-01.aldia")
        XCTAssertEqual(DailyBackup.visibleName("al-dia-2026-11-01.aldia"), "al-dia-2026-11-01.aldia")
    }
}
