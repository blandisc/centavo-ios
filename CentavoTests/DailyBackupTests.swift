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
        amex.subtype = MoneySubtype.loan.rawValue
        amex.institution = "American Express"
        context.insert(MoneyIncome(name: "Sueldo", institution: "Arca", amount: 60_000, currency: "MXN"))
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
        let restored = try ModelContext(elsewhere).fetch(FetchDescriptor<MoneyAccount>(predicate: #Predicate { $0.name == "Amex" }))
        XCTAssertEqual(restored.first?.subtype, "prestamo", "El respaldo ya no pierde el tipo de cada deuda")
        XCTAssertEqual(restored.first?.institution, "American Express")
        XCTAssertEqual(try ModelContext(elsewhere).fetch(FetchDescriptor<MoneyIncome>()).first?.amount, 60_000)
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
        // The month already has a cut: replacing it is asked first, never done in silence.
        XCTAssertThrowsError(try MoneyStore.finish(draft, in: context)) { error in
            guard case MoneyStore.CutProblem.monthHasCut = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.netWorth.total, 1_000, "Nada cambió sin preguntar")
        try MoneyStore.finish(draft, replacing: true, in: context)
        XCTAssertEqual(try context.fetch(MoneyCut.finished).count, 1)
        XCTAssertEqual(MoneyStore.latestCut(in: context)?.netWorth.total, 9_999)
    }

    func testTheNewFieldsTravelToo() throws {
        let source = try container()
        let original = Expense(amount: 5_000, currencyMarker: "MXN", merchant: "Colegio")
        original.fixedID = "colegio-1"
        let copy = Expense(amount: 5_000, currencyMarker: "MXN", merchant: "Colegio")
        copy.fixedOf = "colegio-1"
        copy.maybeRepeated = true
        source.mainContext.insert(original)
        source.mainContext.insert(copy)
        let payload = try DailyBackup.snapshot(in: source.mainContext, moneyContainer: nil)
        let target = try container()
        try DailyBackup.restore(payload, into: target, money: nil)
        let back = try all(target)
        XCTAssertEqual(Set(back.compactMap(\.fixedID)), ["colegio-1"])
        XCTAssertEqual(Set(back.compactMap(\.fixedOf)), ["colegio-1"])
        XCTAssertEqual(back.filter { $0.maybeRepeated == true }.count, 1)
    }

    /// A file with «Mi dinero» and no «Mi dinero» to put it in: nothing changes, it doesn't
    /// quietly bring back only the expenses.
    func testAFileWithMiDineroNeedsItsStore() throws {
        let money = try MoneyStore.inMemory()
        try MoneyStore.add(MoneyAccount(name: "Nu", kind: .account, currency: "MXN"), balance: 500, rate: nil,
                           in: ModelContext(money), mainCurrency: "MXN")
        let source = try container()
        source.mainContext.insert(Expense(amount: 89, merchant: "Oxxo"))
        let payload = try DailyBackup.snapshot(in: source.mainContext, moneyContainer: money)
        let target = try container()
        target.mainContext.insert(Expense(amount: 1, merchant: "Antes"))
        try target.mainContext.save()
        XCTAssertThrowsError(try DailyBackup.restore(payload, into: target, money: nil))
        XCTAssertEqual(try all(target).map(\.merchant), ["Antes"])
    }

    func testAnOldFileRestoresWithoutMiDinero() throws {
        let source = try container()
        source.mainContext.insert(Expense(amount: 89, merchant: "Oxxo"))
        let payload = try DailyBackup.snapshot(in: source.mainContext, moneyContainer: nil)
        XCTAssertNil(payload.money)
        let target = try container()
        try DailyBackup.restore(payload, into: target)
        XCTAssertEqual(try all(target).map(\.merchant), ["Oxxo"])
    }

    func testUndoBringsBackEveryField() throws {
        // Held for the whole test: a context whose container is gone traps on insert.
        let store = try container()
        let context = store.mainContext
        let expense = fullExpense()
        expense.maybeRepeated = true
        expense.fixedOf = "x"
        let deleted = DeletedExpense(expense)
        let back = try XCTUnwrap(deleted.make())
        XCTAssertEqual(back.backedUp, expense.backedUp)
        context.insert(back)
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

/// Respaldos «aparte» (2026-11-11), de punta a punta contra una carpeta temporal: queda dicho
/// por qué se apartó, «Este iPhone es el bueno» deja un diario normal y solo se quedan 5 aparte.
/// Escriben con `writeToday` y `record`, que es lo que hace `runNow`, para no tocar la
/// contraseña que el simulador tenga en su llavero.
@MainActor
final class DailyBackupAsideTests: XCTestCase {
    private let password = "prueba-clave"
    private let keys = [DailyBackup.folderKey, DailyBackup.folderNameKey, DailyBackup.lastKey,
                        DailyBackup.failedKey, DailyBackup.fileKey, DailyBackup.asideKey]
    private var saved: [String: Any] = [:]
    private var folder: URL!

    override func setUpWithError() throws {
        let defaults = UserDefaults.standard
        saved = [:]
        for key in keys {
            saved[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        folder = FileManager.default.temporaryDirectory.appending(path: "respaldo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try DailyBackup.choose(folder: folder)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = saved[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        BackupRetention.calendar().date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func payload(_ count: Int, money: BackupMoney? = nil, at date: Date) -> BackupPayload {
        let expenses = (0..<count).map { BackupExpense(amount: 10, date: date.addingTimeInterval(Double(-$0)), merchant: "Gasto \($0)") }
        return BackupPayload(createdAt: date, writtenBy: "prueba", expenses: expenses, settings: [:], money: money)
    }

    /// What `runNow` does once it has the payload and the password.
    @discardableResult
    private func backUp(_ count: Int, money: BackupMoney? = nil, at date: Date,
                        trustingThisPhone: Bool = false) throws -> DailyBackup.Written {
        let written = try DailyBackup.writeToday(payload(count, money: money, at: date), password: password, now: date,
                                                 trustingThisPhone: trustingThisPhone)
        DailyBackup.record(written, at: date)
        return written
    }

    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }

    private func count(in name: String) throws -> Int {
        try DailyBackup.read(folder.appending(path: name), password: password).expenses.count
    }

    /// Backed up in the morning, one repeated expense deleted in the afternoon: the night's
    /// file goes apart, the morning's stays, and it's said why, on the screen and in «Hoy».
    func testFewerThanTodaysFileGoesApartAndSaysWhy() throws {
        let daily = BackupRetention.fileName(for: at(10, 9))
        XCTAssertEqual(try backUp(8, at: at(10, 9)), DailyBackup.Written(name: daily, aside: nil))
        XCTAssertNil(DailyBackup.aside)
        XCTAssertNil(DailyBackup.notice(now: at(10, 9)))

        let written = try backUp(7, at: at(10, 21))
        let apart = BackupRetention.asideName(for: at(10, 21))
        XCTAssertEqual(written.name, apart)
        let note = try XCTUnwrap(DailyBackup.aside)
        XCTAssertEqual(note, written.aside)
        XCTAssertEqual(note.kind, .fewer)
        XCTAssertEqual(note.here, 7)
        XCTAssertEqual(note.there, 8)
        XCTAssertEqual(note.day, "2026-11-10")
        XCTAssertEqual(note.file, apart)
        XCTAssertEqual(note.message(now: at(10, 21)),
                       "Tu último respaldo se guardó aparte: este iPhone tiene menos gastos (7) que el respaldo del 10 nov (8).")
        XCTAssertEqual(DailyBackup.notice(now: at(10, 21)), DailyBackup.asideWarning)
        XCTAssertEqual(DailyBackup.lastBackup, at(10, 21), "Aparte también es un respaldo: está completo y comprobado")
        XCTAssertEqual(try names(), [daily, apart].sorted())
        XCTAssertEqual(try count(in: daily), 8, "El de la mañana no se tocó")
        XCTAssertEqual(try count(in: apart), 7)
    }

    /// «Este iPhone es el bueno»: the daily file is written from this phone, the one it replaces
    /// is kept under another name, the note goes and the next nights are normal.
    func testThisPhoneIsTheGoodOneLeavesANormalDaily() throws {
        let daily = BackupRetention.fileName(for: at(10, 9))
        try backUp(8, at: at(10, 9))
        try backUp(7, at: at(10, 21))
        XCTAssertNotNil(DailyBackup.aside)

        let written = try backUp(7, at: at(10, 21, 5), trustingThisPhone: true)
        XCTAssertEqual(written, DailyBackup.Written(name: daily, aside: nil))
        XCTAssertNil(DailyBackup.aside, "La marca se limpia")
        XCTAssertNil(DailyBackup.notice(now: at(10, 21, 5)))
        XCTAssertEqual(try count(in: daily), 7)
        let replaced = BackupRetention.replacedName(for: at(10, 21, 5))
        XCTAssertEqual(try count(in: replaced), 8, "El archivo reemplazado se conserva, con otro nombre")
        XCTAssertEqual(try names(), [daily, BackupRetention.asideName(for: at(10, 21)), replaced].sorted())

        // The next nights compare with the new daily file: normal again, even with one less.
        let next = BackupRetention.fileName(for: at(11, 21))
        XCTAssertEqual(try backUp(6, at: at(11, 21)), DailyBackup.Written(name: next, aside: nil))
        XCTAssertNil(DailyBackup.aside)
        XCTAssertEqual(try count(in: next), 6)
        XCTAssertEqual(try count(in: replaced), 8)
    }

    /// Far fewer than the newest daily file, of another day (an old backup was restored): apart
    /// every night until the person says this phone is right; then nothing has to be renamed.
    func testFarFewerThanTheNewestGoesApartUntilThisPhoneIsTrusted() throws {
        let yesterday = BackupRetention.fileName(for: at(9, 21))
        try backUp(20, at: at(9, 21))
        let written = try backUp(4, at: at(10, 21))
        XCTAssertEqual(written.aside?.kind, .fewer)
        XCTAssertEqual(written.aside?.there, 20)
        XCTAssertEqual(written.aside?.day, "2026-11-09")
        XCTAssertEqual(DailyBackup.aside?.message(now: at(10, 21)),
                       "Tu último respaldo se guardó aparte: este iPhone tiene menos gastos (4) que el respaldo del 9 nov (20).")

        let today = BackupRetention.fileName(for: at(10, 21))
        XCTAssertEqual(try backUp(4, at: at(10, 21, 5), trustingThisPhone: true).name, today)
        XCTAssertNil(DailyBackup.aside)
        XCTAssertEqual(try count(in: yesterday), 20, "El de ayer sigue igual")
        // The daily cleanup would drop yesterday's some thirty backups later: a copy of it stays
        // for good under a name no cleanup touches.
        let replaced = BackupRetention.replacedName(for: at(10, 21, 5))
        XCTAssertEqual(try Data(contentsOf: folder.appending(path: replaced)),
                       try Data(contentsOf: folder.appending(path: yesterday)), "Copia byte por byte del que tenía más")
        XCTAssertEqual(try count(in: replaced), 20)
        XCTAssertEqual(try count(in: today), 4)
        XCTAssertEqual(try backUp(4, at: at(11, 21)).aside, nil, "La noche siguiente ya es normal")
        XCTAssertEqual(try names().filter { $0.contains("reemplazado") }, [replaced], "Y no se copia otra vez")
    }

    /// The copy of the backup that had more can't be made (its name is taken): nothing is
    /// written, the mark stays and the folder is as it was.
    func testIfTheBackupWithMoreCannotBeKeptNothingIsWritten() throws {
        try backUp(20, at: at(9, 21))
        try backUp(4, at: at(10, 21))
        let taken = BackupRetention.replacedName(for: at(10, 21, 5))
        try Data("x".utf8).write(to: folder.appending(path: taken))
        let before = try names()
        XCTAssertThrowsError(try backUp(4, at: at(10, 21, 5), trustingThisPhone: true)) { error in
            XCTAssertEqual(error as? DailyBackup.Failure, .oldNotKept)
        }
        XCTAssertEqual(try names(), before)
        XCTAssertNotNil(DailyBackup.aside)
    }

    /// Five apart files dated after «now» (a clock set back, another device ahead): the one
    /// just written is never the one deleted, and «Último respaldo» points at a file that's there.
    func testTheApartFileJustWrittenIsNeverDeleted() throws {
        let later = (11...15).map { BackupRetention.asideName(for: at($0, 21)) }
        for name in later { try Data("x".utf8).write(to: folder.appending(path: name)) }
        try backUp(8, at: at(10, 9))
        let written = try backUp(7, at: at(10, 21))
        XCTAssertTrue(try names().contains(written.name))
        XCTAssertEqual(UserDefaults.standard.string(forKey: DailyBackup.fileKey), written.name)
        XCTAssertEqual(try count(in: written.name), 7)
        XCTAssertEqual(try names().filter { BackupRetention.asideStamp(of: $0) != nil }.count, 5)
    }

    /// The mark was about the backups of the folder and the data there was: choosing another
    /// folder, or restoring, clears it.
    func testChoosingAFolderOrRestoringClearsTheMark() throws {
        try backUp(8, at: at(10, 9))
        try backUp(7, at: at(10, 21))
        XCTAssertNotNil(DailyBackup.aside)
        try DailyBackup.choose(folder: folder)
        XCTAssertNil(DailyBackup.aside, "Otra carpeta: la marca ya no dice nada")

        try backUp(6, at: at(10, 21, 5))
        XCTAssertNotNil(DailyBackup.aside)
        let store = try ModelContainer(for: Expense.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let file = BackupPayload(createdAt: at(10, 9), writtenBy: "prueba",
                                 expenses: [BackupExpense(amount: 89, date: at(10, 9), merchant: "Oxxo")],
                                 settings: DailyBackup.Settings.current())
        try DailyBackup.restore(file, into: store, money: nil)
        XCTAssertNil(DailyBackup.aside, "Restaurar cambia lo que hay en el iPhone")
    }

    /// A second run while one is writing does nothing: no file, and not a failed night.
    func testASecondRunAtTheSameTimeDoesNothing() async throws {
        let store = try ModelContainer(for: Expense.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        DailyBackup.isRunning = true
        defer { DailyBackup.isRunning = false }
        do {
            try await DailyBackup.runNow(in: store.mainContext, now: at(10, 21))
            XCTFail("La segunda corrida no debe escribir")
        } catch {
            XCTAssertEqual(error as? DailyBackup.Failure, .busy)
        }
        XCTAssertTrue(DailyBackup.isRunning, "No apaga la bandera de la corrida que sí está escribiendo")
        XCTAssertNil(DailyBackup.lastFailure)
        XCTAssertNil(DailyBackup.lastBackup)
        XCTAssertEqual(try names(), [])
    }

    /// Only the newest five apart files stay; nothing else in the folder is touched.
    func testOnlyTheNewestFiveApartFilesStay() throws {
        let old = (1...7).map { BackupRetention.asideName(for: at($0, 21)) }
        let others = [BackupRetention.partialName(for: at(1, 21)), BackupRetention.safetyName(for: at(1, 21)),
                      BackupRetention.replacedName(for: at(1, 21)), "al-dia-aparte-2569-10-01T210000.aldia", "foto.jpg"]
        for name in old + others { try Data("x".utf8).write(to: folder.appending(path: name)) }

        let daily = BackupRetention.fileName(for: at(10, 9))
        try backUp(8, at: at(10, 9))
        try backUp(7, at: at(10, 21))
        let kept = Array(old.suffix(4)) + [BackupRetention.asideName(for: at(10, 21))]
        XCTAssertEqual(try names(), (kept + others + [daily]).sorted())
    }

    /// With no expenses on the phone nothing is ever deleted, apart files included.
    func testWithNoExpensesNoApartFileIsDeleted() throws {
        let old = (1...7).map { BackupRetention.asideName(for: at($0, 21)) }
        for name in old { try Data("x".utf8).write(to: folder.appending(path: name)) }
        try backUp(8, at: at(10, 9))
        let money = BackupMoney(accounts: [.init(id: "a", name: "Nu", kind: "cuenta", currency: "MXN", yearlyRate: nil,
                                                 order: 0, archived: false, createdAt: at(1, 9))], cuts: [])
        XCTAssertEqual(try backUp(0, money: money, at: at(10, 21)).aside?.kind, .fewer)
        XCTAssertTrue(try names().filter { old.contains($0) }.count == 7)
    }

    /// The daily file of today has «Mi dinero» and this phone doesn't: apart, and it says so.
    func testWithoutMiDineroGoesApartAndSaysSo() throws {
        let money = BackupMoney(accounts: [.init(id: "a", name: "Nu", kind: "cuenta", currency: "MXN", yearlyRate: nil,
                                                 order: 0, archived: false, createdAt: at(1, 9))], cuts: [])
        try backUp(8, money: money, at: at(10, 9))
        XCTAssertEqual(try backUp(8, at: at(10, 21)).aside?.kind, .noMoney)
        XCTAssertEqual(DailyBackup.aside?.message(now: at(10, 21)),
                       "Tu último respaldo se guardó aparte: este iPhone no tiene «Mi dinero» y el respaldo del 10 nov sí.")
    }

    /// The file of the day was locked with another password: apart; trusting this phone keeps
    /// that file, unopened, under its other name.
    func testAFileOfTheDayThatDoesNotOpenIsKeptWhenReplaced() throws {
        let daily = BackupRetention.fileName(for: at(10, 9))
        let foreign = try BackupSeal.seal(payload(50, at: at(10, 9)), password: "otra-clave", rounds: 1_000)
        try foreign.write(to: folder.appending(path: daily))
        XCTAssertEqual(try backUp(8, at: at(10, 21)).aside?.kind, .unreadable)
        XCTAssertEqual(try backUp(8, at: at(10, 21, 5), trustingThisPhone: true).name, daily)
        XCTAssertNil(DailyBackup.aside)
        XCTAssertEqual(try count(in: daily), 8)
        let kept = try Data(contentsOf: folder.appending(path: BackupRetention.replacedName(for: at(10, 21, 5))))
        XCTAssertEqual(kept, foreign, "El archivo que no abría se conserva byte por byte")
    }
}
