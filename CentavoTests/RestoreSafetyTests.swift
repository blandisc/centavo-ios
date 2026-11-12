import CentavoCore
import SwiftData
import XCTest
@testable import Centavo

/// Restaurar nunca reemplaza sin una copia a la vista (2026-11-11, mapa de estados): con algo que
/// guardar y sin carpeta no se restaura; la copia va a una carpeta que la persona puede abrir,
/// nunca solo a Documentos de la app; un iPhone vacío restaura directo; y las copias que
/// quedaron dentro de la app se listan y solo se limpian si ya están en la carpeta.
@MainActor
final class RestoreSafetyTests: XCTestCase {
    private let password = "prueba-clave"
    private let keys = [DailyBackup.folderKey, DailyBackup.folderNameKey, DailyBackup.asideKey,
                        DailyBackup.restoredKey, DailyBackup.laterKey]
    private var saved: [String: Any] = [:]
    private var folder: URL!
    private var documents: URL!

    override func setUpWithError() throws {
        let defaults = UserDefaults.standard
        saved = [:]
        for key in keys {
            saved[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        let base = FileManager.default.temporaryDirectory.appending(path: "restaurar-\(UUID().uuidString)")
        folder = base.appending(path: "Al día")
        documents = base.appending(path: "Documentos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = saved[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        BackupRetention.calendar().date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func phone(_ merchants: [String]) throws -> ModelContainer {
        let container = try ModelContainer(for: Expense.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        for (index, merchant) in merchants.enumerated() {
            container.mainContext.insert(Expense(amount: 10, merchant: merchant, date: at(1, 9, index)))
        }
        try container.mainContext.save()
        return container
    }

    private func merchants(_ container: ModelContainer) throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)])).map(\.merchant)
    }

    /// The backup being restored: two expenses of another day.
    private var backup: BackupPayload {
        BackupPayload(createdAt: at(10, 21), writtenBy: "prueba",
                      expenses: [BackupExpense(amount: 99, date: at(9, 12), merchant: "Del respaldo 1"),
                                 BackupExpense(amount: 98, date: at(9, 13), merchant: "Del respaldo 2")],
                      settings: DailyBackup.Settings.current(), money: nil)
    }

    private func files(in url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false)).sorted()
    }

    // MARK: Nunca sin copia a la vista

    func testWithExpensesAndNoFolderNothingIsReplaced() async throws {
        let container = try phone(["Mío 1", "Mío 2"])
        XCTAssertEqual(DailyBackup.safetyPlan(in: container.mainContext, money: nil, settings: [:]), .askWhere)
        do {
            try await DailyBackup.restoreKeepingCopy(backup, in: container.mainContext, password: password,
                                                     now: at(12, 21, 40), money: nil, settings: [:])
            XCTFail("Restauró sin tener dónde guardar la copia")
        } catch {
            XCTAssertEqual(error as? DailyBackup.Failure, .noPlaceForCopy)
        }
        XCTAssertEqual(try merchants(container), ["Mío 1", "Mío 2"], "Sin copia a la vista no se reemplaza nada")
    }

    func testTheCopyGoesToTheFolderPickedForItBeforeReplacing() async throws {
        let container = try phone(["Mío 1", "Mío 2", "Mío 3"])
        let before = DailyBackup.strandedCopies().count
        let copy = try await DailyBackup.restoreKeepingCopy(backup, in: container.mainContext, password: password,
                                                            copyInto: folder, now: at(12, 21, 40), money: nil, settings: [:])
        let name = BackupRetention.safetyName(for: at(12, 21, 40))
        XCTAssertEqual(copy, DailyBackup.SafetyCopy(name: name, folderName: "Al día"))
        XCTAssertEqual(try files(in: folder), [name])
        let kept = try DailyBackup.read(folder.appending(path: name), password: password)
        XCTAssertEqual(kept.expenses.map(\.merchant).sorted(), ["Mío 1", "Mío 2", "Mío 3"], "La copia trae lo que había")
        XCTAssertEqual(try merchants(container), ["Del respaldo 1", "Del respaldo 2"])
        XCTAssertNil(UserDefaults.standard.data(forKey: DailyBackup.folderKey),
                     "La carpeta de la copia no se vuelve la del respaldo diario sin que la persona lo pida")
        XCTAssertEqual(DailyBackup.strandedCopies().count, before, "Ya no se escribe otra copia dentro de la app")
    }

    func testTheCopyGoesToTheBackupFolderWhenThereIsOne() async throws {
        try DailyBackup.choose(folder: folder)
        let container = try phone(["Mío"])
        XCTAssertEqual(DailyBackup.safetyPlan(in: container.mainContext, money: nil, settings: [:]), .copyToFolder)
        let copy = try await DailyBackup.restoreKeepingCopy(backup, in: container.mainContext, password: password,
                                                            now: at(12, 21, 40), money: nil, settings: [:])
        let name = try XCTUnwrap(copy?.name)
        XCTAssertEqual(copy?.folderName, "Al día")
        XCTAssertEqual(try DailyBackup.read(folder.appending(path: name), password: password).expenses.map(\.merchant), ["Mío"])
        XCTAssertEqual(try merchants(container), ["Del respaldo 1", "Del respaldo 2"])
    }

    func testACopyThatCannotBeWrittenStopsTheRestore() async throws {
        let container = try phone(["Mío"])
        let gone = folder.appending(path: "ya-no-existe")
        do {
            try await DailyBackup.restoreKeepingCopy(backup, in: container.mainContext, password: password,
                                                     copyInto: gone, now: at(12, 21, 40), money: nil, settings: [:])
            XCTFail("Restauró sin que la copia quedara escrita")
        } catch {
            XCTAssertEqual(error as? DailyBackup.Failure, .copyNotSaved)
        }
        XCTAssertEqual(try merchants(container), ["Mío"])
    }

    func testAFolderThatIsGoneCountsAsNoFolder() async throws {
        try DailyBackup.choose(folder: folder)
        try FileManager.default.removeItem(at: folder)
        let container = try phone(["Mío"])
        XCTAssertFalse(DailyBackup.folderIsUsable)
        XCTAssertEqual(DailyBackup.safetyPlan(in: container.mainContext, money: nil, settings: [:]), .askWhere)
        do {
            try await DailyBackup.restoreKeepingCopy(backup, in: container.mainContext, password: password,
                                                     now: at(12, 21, 40), money: nil, settings: [:])
            XCTFail("Restauró sin que la copia quedara escrita")
        } catch {
            XCTAssertNotNil(error as? DailyBackup.Failure)
        }
        XCTAssertEqual(try merchants(container), ["Mío"])
    }

    func testAnEmptyPhoneRestoresWithoutACopy() async throws {
        let container = try phone([])
        XCTAssertEqual(DailyBackup.safetyPlan(in: container.mainContext, money: nil, settings: [:]), .nothingToCopy)
        let copy = try await DailyBackup.restoreKeepingCopy(backup, in: container.mainContext, password: password,
                                                            now: at(12, 21, 40), money: nil, settings: [:])
        XCTAssertNil(copy, "Sin gastos ni «Mi dinero» no hay nada que copiar")
        XCTAssertEqual(try merchants(container), ["Del respaldo 1", "Del respaldo 2"])
    }

    /// No expenses, but a budget or lists of their own: restoring replaces them too, so it's
    /// copied like any other phone, and without a folder nothing is replaced (independent review).
    func testNoExpensesButABudgetOrACatalogIsCopiedFirst() async throws {
        let budget: [String: BackupSetting] = [BudgetStore.key: .text("8000")]
        for settings in [budget, [UserCatalog.categoriesKey: .text("[\"Mascotas\"]")],
                         [UserCatalog.merchantRenamesKey: .text("{\"OXXO 123\":\"Oxxo\"}")],
                         [UserCatalog.categoryRulesKey: .text("{\"Oxxo\":\"Súper\"}")],
                         [FixedPlan.key: .text("[{\"name\":\"Renta\"}]")]] {
            let container = try phone([])
            XCTAssertEqual(DailyBackup.safetyPlan(in: container.mainContext, money: nil, settings: settings), .askWhere,
                           "\(settings.keys)")
        }
        // What every phone has after the welcome doesn't count.
        let fresh = try phone([])
        XCTAssertEqual(DailyBackup.safetyPlan(in: fresh.mainContext, money: nil,
                                              settings: ["onboarded": .flag(true), CurrencyPreference.key: .text("MXN"),
                                                         BudgetStore.key: .text(""), UserCatalog.categoriesKey: .text("[]")]),
                       .nothingToCopy)

        let container = try phone([])
        do {
            try await DailyBackup.restoreKeepingCopy(backup, in: container.mainContext, password: password,
                                                     now: at(12, 21, 40), money: nil, settings: budget)
            XCTFail("Restauró sin copia un iPhone con presupuesto")
        } catch {
            XCTAssertEqual(error as? DailyBackup.Failure, .noPlaceForCopy)
        }
        XCTAssertEqual(try merchants(container), [], "No se reemplazó nada")

        let copy = try await DailyBackup.restoreKeepingCopy(backup, in: container.mainContext, password: password,
                                                            copyInto: folder, now: at(12, 21, 40), money: nil, settings: budget)
        XCTAssertNotNil(copy, "Con presupuesto se saca la copia aunque no haya gastos")
        XCTAssertEqual(try files(in: folder), [BackupRetention.safetyName(for: at(12, 21, 40))])
        XCTAssertEqual(try merchants(container), ["Del respaldo 1", "Del respaldo 2"])
    }

    func testEveryPersonalSettingTravelsInTheBackup() {
        for key in DailyBackup.personalKeys {
            XCTAssertTrue(DailyBackup.Settings.isOurs(key), "\(key) no viajaría en la copia")
        }
    }

    func testAnEmptyPhoneWithMiDineroIsNotEmpty() throws {
        let container = try phone([])
        let money = try MoneyStore.inMemory()
        XCTAssertEqual(DailyBackup.safetyPlan(in: container.mainContext, money: money, settings: [:]), .nothingToCopy)
        try MoneyStore.add(MoneyAccount(name: "Nu", kind: .account, currency: "MXN"), balance: 500, rate: nil,
                           in: ModelContext(money), mainCurrency: "MXN")
        XCTAssertEqual(DailyBackup.safetyPlan(in: container.mainContext, money: money, settings: [:]), .askWhere)
    }

    // MARK: Las copias que quedaron dentro de la app

    private func leave(_ name: String, _ text: String, in url: URL) throws {
        try Data(text.utf8).write(to: url.appending(path: name))
    }

    func testCopiesLeftInsideTheAppAreListedNewestFirst() throws {
        let old = BackupRetention.safetyName(for: at(2, 9)), new = BackupRetention.safetyName(for: at(12, 21, 40))
        try leave(old, "vieja", in: documents)
        try leave(new, "nueva", in: documents)
        try leave("al-dia-2026-11-12.aldia", "diario", in: documents)
        try leave("notas.txt", "otra cosa", in: documents)
        XCTAssertEqual(DailyBackup.strandedCopies(in: documents).map(\.name), [new, old])
        XCTAssertEqual(DailyBackup.strandedCopies(in: documents.appending(path: "no-existe")), [])
    }

    func testOnlyCopiesAlreadyInTheFolderAreCleaned() throws {
        try DailyBackup.choose(folder: folder)
        let same = BackupRetention.safetyName(for: at(2, 9))
        let different = BackupRetention.safetyName(for: at(3, 9))
        let onlyInside = BackupRetention.safetyName(for: at(4, 9))
        for name in [same, different, onlyInside] { try leave(name, "copia \(name)", in: documents) }
        try leave("notas.txt", "otra cosa", in: documents)
        try leave(same, "copia \(same)", in: folder)
        try leave(different, "otro contenido", in: folder)

        XCTAssertEqual(DailyBackup.tidyStrandedCopies(in: documents), [same])
        XCTAssertEqual(try files(in: documents), [different, onlyInside, "notas.txt"].sorted(),
                       "Solo se va la que ya está igual en la carpeta")
        XCTAssertEqual(try files(in: folder), [same, different].sorted(), "La carpeta no se toca")
    }

    func testWithoutAFolderNoCopyIsCleaned() throws {
        let name = BackupRetention.safetyName(for: at(2, 9))
        try leave(name, "copia", in: documents)
        XCTAssertEqual(DailyBackup.tidyStrandedCopies(in: documents), [])
        XCTAssertEqual(try files(in: documents), [name])
    }

    func testDeletingACopyOnlyDeletesThatCopy() throws {
        let name = BackupRetention.safetyName(for: at(2, 9))
        try leave(name, "copia", in: documents)
        try leave("notas.txt", "otra cosa", in: documents)
        XCTAssertFalse(DailyBackup.removeStranded(BackupSafetyCopy(name: "notas.txt", date: at(2, 9)), in: documents))
        XCTAssertTrue(DailyBackup.removeStranded(try XCTUnwrap(DailyBackup.strandedCopies(in: documents).first), in: documents))
        XCTAssertEqual(try files(in: documents), ["notas.txt"])
    }

    // MARK: Restaurado y sin respaldo configurado

    func testARestoredPhoneWithoutBackupSaysSoOnceAWeek() throws {
        let name = "pruebas-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertNil(DailyBackup.setUpNotice(now: at(12, 21), defaults: defaults), "Nunca se restauró: nada que decir")

        DailyBackup.noteRestored(now: at(12, 21), defaults: defaults)
        XCTAssertEqual(DailyBackup.setUpNotice(now: at(12, 22), defaults: defaults), BackupSetupReminder.warning)

        DailyBackup.sayLater(now: at(12, 22), defaults: defaults)
        XCTAssertNil(DailyBackup.setUpNotice(now: at(15, 9), defaults: defaults), "«Ahora no»: calla una semana")
        XCTAssertEqual(DailyBackup.setUpNotice(now: at(19, 22), defaults: defaults), BackupSetupReminder.warning)

        // Restoring again starts over: it's said that same day.
        DailyBackup.sayLater(now: at(19, 23), defaults: defaults)
        DailyBackup.noteRestored(now: at(20, 9), defaults: defaults)
        XCTAssertEqual(DailyBackup.setUpNotice(now: at(20, 10), defaults: defaults), BackupSetupReminder.warning)
    }

    func testTheNewMarksStayOnThisPhone() {
        XCTAssertFalse(DailyBackup.Settings.isOurs(DailyBackup.restoredKey))
        XCTAssertFalse(DailyBackup.Settings.isOurs(DailyBackup.laterKey))
    }

    // MARK: Lo que dice la pantalla

    func testTheQuestionSaysWhereTheCopyGoes() {
        let what = "Del 10 nov: 2 gastos."
        XCTAssertTrue(BackupSettingsView.question(what, plan: .copyToFolder, folder: "Al día")
            .hasSuffix("Antes se guarda una copia de lo actual en tu carpeta «Al día»."))
        let asks = BackupSettingsView.question(what, plan: .askWhere, folder: nil)
        XCTAssertTrue(asks.contains("eliges la carpeta en Archivos"))
        XCTAssertTrue(asks.contains("Si no eliges ninguna, no se restaura nada."))
        XCTAssertFalse(asks.contains("en tu carpeta"), "Sin carpeta no se promete una")
        XCTAssertTrue(BackupSettingsView.question(what, plan: .nothingToCopy, folder: nil)
            .hasSuffix("Este iPhone no tiene gastos, ni «Mi dinero», ni presupuesto o listas tuyas, así que no hay nada que guardar antes."))
    }

    func testDoneSaysWhereTheCopyIsAndOffersToKeepBackingUp() {
        let summary = backup.summary
        let copy = DailyBackup.SafetyCopy(name: "al-dia-antes-de-restaurar-2026-11-12T214000.aldia", folderName: "Al día")
        let plain = BackupSettingsView.done(RestoreOutcome(summary: summary, copy: copy, copyUsesSavedPassword: true,
                                                           offersSetUp: false, hasPassword: true))
        XCTAssertEqual(plain, "Se restauraron 2 gastos y tus ajustes. Lo que había antes quedó en la carpeta «Al día», como «al-dia-antes-de-restaurar-2026-11-12T214000.aldia». Se abre con la contraseña del respaldo de este iPhone.")

        let newPhone = BackupSettingsView.done(RestoreOutcome(summary: summary, copy: nil, copyUsesSavedPassword: false,
                                                              offersSetUp: true, hasPassword: false))
        XCTAssertTrue(newPhone.hasPrefix("Se restauraron 2 gastos y tus ajustes. Este iPhone estaba vacío: no había nada que guardar antes."))
        XCTAssertTrue(newPhone.contains(BackupSetupReminder.text))
        XCTAssertTrue(newPhone.contains("guarda en este iPhone la contraseña con la que abriste este respaldo"))
        for step in BackupSettingsView.automationSteps {
            XCTAssertTrue(newPhone.contains(step), "La automatización también hay que crearla en el iPhone nuevo")
        }
        XCTAssertTrue(BackupSettingsView.setUpText(folder: "Al día", localOnly: false).contains("Respaldar Al día"))
        XCTAssertTrue(BackupSettingsView.setUpText(folder: "Al día", localOnly: true).contains("solo en este iPhone"))
    }
}

/// «Al día no pudo abrir tus gastos» (2026-11-11): reintentar sin abrir dos veces, la causa, y la
/// copia de los archivos tal cual.
@MainActor
final class StoreTroubleAppTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appending(path: "base-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appending(path: "datos"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    func testRetryingNeverOpensAnOpenStoreTwice() throws {
        let first = try Store.opened.get()
        XCTAssertTrue(try Store.retry().get() === first, "Un almacén abierto se entrega tal cual")
        XCTAssertTrue(try Store.opened.get() === first)
    }

    func testTheCauseIsReadThroughEveryErrorUnderneath() {
        let disk = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let sqlite = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSUnderlyingErrorKey: disk])
        let top = NSError(domain: "SwiftData.SwiftDataError", code: 1, userInfo: [NSUnderlyingErrorKey: sqlite])
        XCTAssertEqual(StoreFiles.codes(of: top).map(\.domain), ["SwiftData.SwiftDataError", NSCocoaErrorDomain, NSPOSIXErrorDomain])
        XCTAssertEqual(StoreTrouble.cause(codes: StoreFiles.codes(of: top), freeBytes: 20_000_000_000), .noSpace)
        XCTAssertEqual(StoreTrouble.cause(codes: StoreFiles.codes(of: CocoaError(.fileWriteOutOfSpace)), freeBytes: nil), .noSpace)
        XCTAssertEqual(StoreTrouble.cause(codes: StoreFiles.codes(of: CocoaError(.fileReadCorruptFile)),
                                          freeBytes: 20_000_000_000), .unknown)
    }

    func testTheCopyBringsEveryStoreFileUntouched() throws {
        let data = base.appending(path: "datos")
        let stores = ["default.store": "gastos", "default.store-wal": "diario de gastos", "default.store-shm": "índice",
                      "dinero.store": "mi dinero", "dinero.store.danado-2026-11-02T210000": "apartado"]
        for (name, text) in stores { try Data(text.utf8).write(to: data.appending(path: name)) }
        try Data("otra cosa".utf8).write(to: data.appending(path: "notas.txt"))

        // The same folder twice (both stores live in one): each file once.
        let found = StoreFiles.all(in: [data, data], store: "default.store")
        XCTAssertEqual(found.map(\.lastPathComponent).sorted(), stores.keys.sorted())

        let now = BackupRetention.calendar().date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 21, minute: 40))!
        let copy = try XCTUnwrap(StoreFiles.copyOut(found, to: base, now: now))
        XCTAssertEqual(copy.lastPathComponent, "Al día - copia de datos 2026-11-12T214000")
        let copied = try FileManager.default.contentsOfDirectory(atPath: copy.path(percentEncoded: false)).sorted()
        XCTAssertEqual(copied, stores.keys.sorted())
        for (name, text) in stores {
            XCTAssertEqual(try Data(contentsOf: copy.appending(path: name)), Data(text.utf8), name)
            XCTAssertEqual(try Data(contentsOf: data.appending(path: name)), Data(text.utf8), "El original no se toca")
        }
        StoreFiles.discard(copy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    func testWithNoFilesThereIsNoCopy() throws {
        XCTAssertNil(try StoreFiles.copyOut([], to: base))
        XCTAssertEqual(StoreFiles.all(in: [base.appending(path: "no-existe")], store: "default.store"), [])
    }

    func testAHalfMadeCopyIsNeverHandedOver() throws {
        let data = base.appending(path: "datos")
        try Data("gastos".utf8).write(to: data.appending(path: "default.store"))
        let missing = data.appending(path: "default.store-wal")
        XCTAssertThrowsError(try StoreFiles.copyOut([data.appending(path: "default.store"), missing], to: base))
        let left = try FileManager.default.contentsOfDirectory(atPath: base.path(percentEncoded: false))
        XCTAssertEqual(left, ["datos"], "No queda una carpeta con solo parte de los archivos")
    }
}
