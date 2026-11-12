import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// El historial del presupuesto en la app (2026-11-11): los meses pasados se juzgan con el
/// presupuesto que tenían, y uno fijado a mitad de mes cuenta desde ese día en la pantalla,
/// los widgets y Siri. La cuenta está probada en CentavoCore (`BudgetHistoryTests`,
/// `BudgetPaceStartTests`); aquí, que la app la use y la guarde.
final class BudgetHistoryAppTests: XCTestCase {
    private var context: ModelContext!
    private var savedBudget: String?
    private var savedHistory: String?

    private static func at(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
        // These tests write the two settings: what the simulator had comes back afterwards.
        savedBudget = UserDefaults.standard.string(forKey: BudgetStore.key)
        savedHistory = UserDefaults.standard.string(forKey: BudgetHistory.key)
        UserDefaults.standard.removeObject(forKey: BudgetStore.key)
        UserDefaults.standard.removeObject(forKey: BudgetHistory.key)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedBudget, forKey: BudgetStore.key)
        UserDefaults.standard.set(savedHistory, forKey: BudgetHistory.key)
    }

    private func expense(_ amount: Decimal, _ date: Date) -> Expense {
        let expense = Expense(amount: amount, currencyMarker: "$", merchant: "Oxxo", date: date)
        context.insert(expense)
        return expense
    }

    private func history(_ changes: (amount: Decimal?, previous: Decimal?, date: Date)...) -> String {
        changes.reduce(BudgetHistory()) { $0.recording($1.amount, previous: $1.previous, on: $1.date) }.stored
    }

    private func pace(budget: Decimal?, rows: [Expense], month: Date, now: Date, history: String) -> BudgetPace? {
        TodayBudget.pace(budget: budget, rows: rows, originals: [], plans: [], primary: "USD", month: month,
                         now: now, mode: .carry, history: history)
    }

    // MARK: Meses pasados

    func testAMonthThatIsOverIsJudgedWithTheBudgetItClosedWith() throws {
        // Octubre: $9,000 gastados con $8,000 de presupuesto. El 14 nov lo sube a $10,000.
        let rows = [expense(9_000, Self.at(10, 9))]
        let now = Self.at(11, 20)
        let changed = history((10_000, 8_000, Self.at(11, 14)))
        let october = try XCTUnwrap(pace(budget: 10_000, rows: rows, month: Self.at(10, 9), now: now, history: changed))
        XCTAssertEqual(october.budget, 8_000)
        XCTAssertTrue(october.isOverspent)
        XCTAssertEqual(october.overspentShown, 1_000)
        // Antes (y sin historial): se juzgaba con el de hoy, «Cerraste con $1,000 de sobra».
        let before = try XCTUnwrap(pace(budget: 10_000, rows: rows, month: Self.at(10, 9), now: now, history: ""))
        XCTAssertEqual(before.budget, 10_000)
        XCTAssertEqual(before.sum.remaining, 1_000)
    }

    func testAMonthThatClosedWithoutABudgetHasNoVerdict() {
        // Lo quitó el 20 oct y lo volvió a poner el 14 nov.
        let rows = [expense(9_000, Self.at(10, 9))]
        let text = history((nil, 8_000, Self.at(10, 20)), (10_000, nil, Self.at(11, 14)))
        XCTAssertNil(pace(budget: 10_000, rows: rows, month: Self.at(10, 9), now: Self.at(11, 20), history: text))
        XCTAssertEqual(pace(budget: 10_000, rows: [], month: Self.at(9, 9), now: Self.at(11, 20), history: text)?.budget, 8_000)
    }

    func testAClosedMonthKeepsItsBudgetAfterTodaysIsTakenOff() {
        let rows = [expense(5_000, Self.at(10, 9))]
        let text = history((nil, 8_000, Self.at(11, 14)))
        XCTAssertEqual(pace(budget: nil, rows: rows, month: Self.at(10, 9), now: Self.at(11, 20), history: text)?.budget, 8_000)
        XCTAssertNil(pace(budget: nil, rows: [], month: Self.at(11, 20), now: Self.at(11, 20), history: text))
    }

    // MARK: Fijado a mitad de mes

    func testABudgetSetMidMonthCountsFromThatDay() throws {
        // $30,000 fijados el 16 de noviembre (30 días: $1,000 al día); del 1 al 15, $2,000; hoy, $400.
        let now = Self.at(11, 16, hour: 20)
        let rows = [expense(1_500, Self.at(11, 3)), expense(500, Self.at(11, 9)), expense(400, Self.at(11, 16))]
        let set = history((30_000, nil, Self.at(11, 16, hour: 9)))
        let today = try XCTUnwrap(pace(budget: 30_000, rows: rows, month: now, now: now, history: set))
        XCTAssertEqual(today.startDay, 16)
        XCTAssertEqual(today.dailyAllowance, 600)
        XCTAssertEqual(today.spent, 2_400, "Lo de antes sigue en «Llevas»")
        XCTAssertEqual(today.countsFrom, Calendar.current.startOfDay(for: now))
        // Sin el día (antes): 16 × $1,000 − $2,400.
        XCTAssertEqual(pace(budget: 30_000, rows: rows, month: now, now: now, history: "")?.dailyAllowance, 13_600)
        // La foto de los widgets lo lleva, y al día siguiente acumula desde el 16.
        let snapshot = TodayBudget.snapshot(budget: 30_000, rows: rows, originals: [], plans: [], primary: "USD",
                                            month: now, now: now, mode: .carry, history: set)
        XCTAssertEqual(snapshot.startDay, 16)
        XCTAssertEqual(snapshot.pace(at: Self.at(11, 17, hour: 1))?.dailyAllowance, 1_600)
        // Un mes pasado no lo lleva.
        let october = TodayBudget.snapshot(budget: 30_000, rows: [], originals: [], plans: [], primary: "USD",
                                           month: Self.at(10, 9), now: now, mode: .carry, history: set)
        XCTAssertNil(october.startDay)
    }

    func testSiriSaysTheSameFigure() throws {
        let now = Self.at(11, 16, hour: 20)
        _ = [expense(2_000, Self.at(11, 3)), expense(400, Self.at(11, 16))]
        UserDefaults.standard.set("30000", forKey: BudgetStore.key)
        BudgetStore.noteChange(from: "", to: "30000", now: Self.at(11, 16, hour: 9))
        XCTAssertEqual(try MonthStatus.todaySentence(in: context, budget: 30_000, now: now, primary: "USD"),
                       "Hoy puedes gastar $600.")
    }

    // MARK: Guardar

    func testEveryChangeIsWrittenDownOnce() {
        // Tenía $8,000 desde siempre: el primer cambio conserva la cifra anterior.
        UserDefaults.standard.set("8000", forKey: BudgetStore.key)
        BudgetStore.settleHistory(now: Self.at(11, 10))
        XCTAssertEqual(BudgetStore.savedHistory, "", "Con presupuesto y sin historial no se escribe nada")
        BudgetStore.noteChange(from: "8000", to: "10000", now: Self.at(11, 14))
        UserDefaults.standard.set("10000", forKey: BudgetStore.key)
        let once = BudgetStore.savedHistory
        XCTAssertEqual(BudgetHistory(stored: once).entries.map(\.value), [8_000, 10_000])
        // La hoja ya lo anotó; el aviso del ajuste y el arranque no lo repiten.
        BudgetStore.noteChange(from: "8000", to: "10000", now: Self.at(11, 14, hour: 13))
        BudgetStore.settleHistory(now: Self.at(11, 15))
        XCTAssertEqual(BudgetStore.savedHistory, once)
        // Quitarlo también se anota.
        BudgetStore.noteChange(from: "10000", to: "", now: Self.at(11, 18))
        XCTAssertEqual(BudgetHistory(stored: BudgetStore.savedHistory).entries.map(\.value), [8_000, 10_000, nil])
    }

    func testAChangeNobodyWroteDownIsDatedOnce() {
        // Otra versión de la app cambió la cifra: el historial dice $8,000 y la cifra, $9,500.
        BudgetStore.noteChange(from: "", to: "8000", now: Self.at(10, 3))
        UserDefaults.standard.set("9500", forKey: BudgetStore.key)
        BudgetStore.settleHistory(now: Self.at(11, 16))
        let settled = BudgetStore.savedHistory
        XCTAssertEqual(BudgetHistory(stored: settled).entries.last?.date, Self.at(11, 16))
        BudgetStore.settleHistory(now: Self.at(11, 20))
        XCTAssertEqual(BudgetStore.savedHistory, settled, "El día no se mueve")
    }

    /// Independent review, 2026-11-11: this phone had $8,000 and a backup with $10,000 and no
    /// list is restored (every backup from before the list existed). The main screen, alive
    /// under «Ajustes», sees the budget change: it must not write «always $8,000; since today
    /// $10,000», which would judge the backup's months with a budget they never had.
    func testRestoringABackupWithAnotherBudgetAndNoListLeavesNoList() throws {
        UserDefaults.standard.set("8000", forKey: BudgetStore.key)
        BudgetStore.noteChange(from: "7000", to: "8000", now: Self.at(11, 3))
        XCTAssertFalse(BudgetStore.savedHistory.isEmpty)
        // The backup: this phone's settings, with another budget and without the list.
        var backup = DailyBackup.Settings.current()
        backup[BudgetStore.key] = .text("10000")
        backup[BudgetHistory.key] = nil
        DailyBackup.Settings.restore(backup)
        // What the main screen does when the saved budget changes.
        BudgetStore.settleHistory(now: Self.at(11, 20))
        XCTAssertEqual(BudgetStore.savedHistory, "", "Restaurar no es un cambio de hoy")
        let rows = [expense(9_000, Self.at(10, 9))]
        let october = try XCTUnwrap(TodayBudget.pace(budget: 10_000, rows: rows, originals: [], plans: [],
                                                     primary: "USD", month: Self.at(10, 9), now: Self.at(11, 20),
                                                     mode: .carry))
        XCTAssertEqual(october.budget, 10_000)
        XCTAssertFalse(october.isOverspent)
        // A backup with no budget either: no budget, no list.
        backup[BudgetStore.key] = nil
        DailyBackup.Settings.restore(backup)
        BudgetStore.settleHistory(now: Self.at(11, 20))
        XCTAssertEqual(BudgetStore.savedHistory, "")
    }

    /// A change from elsewhere with a list on this phone is still dated when it is noticed.
    func testAChangeFromElsewhereWithAListIsStillDated() {
        UserDefaults.standard.set("8000", forKey: BudgetStore.key)
        BudgetStore.noteChange(from: "7000", to: "8000", now: Self.at(10, 3))
        UserDefaults.standard.set("9500", forKey: BudgetStore.key)
        BudgetStore.settleHistory(now: Self.at(11, 16))
        XCTAssertEqual(BudgetHistory(stored: BudgetStore.savedHistory).entries.map(\.value), [7_000, 8_000, 9_500])
    }

    func testTheHistoryTravelsWithTheBackupAndICloud() {
        XCTAssertTrue(DailyBackup.Settings.isOurs(BudgetHistory.key))
        XCTAssertTrue(BudgetSync.keys.contains(BudgetHistory.key))
        XCTAssertTrue(BudgetSync.keys.contains(BudgetStore.key))
        // Adopted before the budget, while this phone's own figure is still the saved one.
        XCTAssertEqual(BudgetSync.keys.first, BudgetHistory.key)
    }
}
