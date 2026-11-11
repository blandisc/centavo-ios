import Foundation
import Testing
@testable import CentavoCore

/// Respaldos «aparte» (2026-11-11): por qué se apartó, qué dice la pantalla, «Este iPhone es el
/// bueno» y cuántos archivos aparte se quedan.
@Suite("Respaldos aparte")
struct BackupAsideTests {
    private let mexico = TimeZone(identifier: "America/Mexico_City")!

    private func mx(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 21, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mexico
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func aside(_ expenses: Int, money: Bool = true, today: BackupPlan.Today = .none,
                       newest: BackupPlan.Today = .none) -> BackupAside? {
        BackupPlan.aside(expenses: expenses, hasMoney: money, today: today, newest: newest)
    }

    // MARK: Por qué

    @Test("Respaldas en la mañana y en la tarde borras un gasto repetido: aparte, con las dos cuentas")
    func oneFewerThanTodaysFile() {
        let today = BackupPlan.Today.holds(expenses: 131, money: true)
        #expect(aside(130, today: today, newest: today) == .fewer(than: .today, here: 130, there: 131))
    }

    @Test("Menos de la mitad que el diario más reciente: aparte, comparado con ese")
    func muchFewerThanTheNewest() {
        #expect(aside(118, newest: .holds(expenses: 300, money: true)) == .fewer(than: .newest, here: 118, there: 300))
        // A few deleted since yesterday is normal life.
        #expect(aside(118, newest: .holds(expenses: 131, money: true)) == nil)
    }

    @Test("Sin «Mi dinero» frente a un respaldo que sí lo trae")
    func noMoney() {
        #expect(aside(500, money: false, today: .holds(expenses: 500, money: true)) == .noMoney(than: .today))
        #expect(aside(500, money: false, newest: .holds(expenses: 500, money: true)) == .noMoney(than: .newest))
    }

    @Test("El archivo del día no se puede abrir; si es el más reciente el que no abre, no se aparta")
    func unreadable() {
        #expect(aside(500, today: .unreadable, newest: .unreadable) == .unreadable)
        #expect(aside(500, newest: .unreadable) == nil)
        #expect(aside(500) == nil)
    }

    @Test("Los gastos se dicen antes que «Mi dinero», y el archivo del día antes que el más reciente")
    func theOrderOfReasons() {
        #expect(aside(3, money: false, today: .holds(expenses: 5, money: true), newest: .holds(expenses: 900, money: true))
                == .fewer(than: .today, here: 3, there: 5))
    }

    @Test("«Aparte» y su motivo siempre van juntos")
    func decideAgreesWithTheReason() {
        let states: [BackupPlan.Today] = [.none, .unreadable, .holds(expenses: 0, money: false),
                                          .holds(expenses: 4, money: true), .holds(expenses: 500, money: false),
                                          .holds(expenses: 500, money: true)]
        for expenses in [0, 1, 4, 5, 249, 250, 499, 500, 501] {
            for money in [true, false] {
                for today in states {
                    for newest in states {
                        let plan = BackupPlan.decide(expenses: expenses, hasMoney: money, today: today, newest: newest,
                                                     folderHasBackups: true)
                        let reason = aside(expenses, money: money, today: today, newest: newest)
                        if plan != .newPhone { #expect((plan == .aside) == (reason != nil)) }
                    }
                }
            }
        }
    }

    // MARK: «Este iPhone es el bueno»

    @Test("«Este iPhone es el bueno» escribe el del día aunque tenga menos, y esa noche no limpia")
    func trustingThisPhoneWritesTheDaily() {
        func trusted(_ expenses: Int, money: Bool = true, today: BackupPlan.Today = .none,
                     newest: BackupPlan.Today = .none) -> BackupPlan {
            BackupPlan.decide(expenses: expenses, hasMoney: money, today: today, newest: newest,
                              folderHasBackups: true, trustingThisPhone: true)
        }
        #expect(trusted(118, today: .holds(expenses: 131, money: true)) == .dailyKeepingOld)
        #expect(trusted(118, newest: .holds(expenses: 300, money: true)) == .dailyKeepingOld)
        #expect(trusted(118, money: false, newest: .holds(expenses: 118, money: true)) == .dailyKeepingOld)
        #expect(trusted(118, today: .unreadable) == .dailyKeepingOld)
        // Nothing to override: a normal night.
        #expect(trusted(131, newest: .holds(expenses: 131, money: true)) == .daily)
        // A phone with nothing at all still never writes over a folder with backups.
        #expect(trusted(0, money: false, newest: .holds(expenses: 131, money: true)) == .newPhone)
    }

    @Test("Después de «Este iPhone es el bueno» las noches siguientes son normales")
    func theNightsAfterAreNormal() {
        // The trusted file is now today's and the newest: 118 against 118.
        let trusted = BackupPlan.Today.holds(expenses: 118, money: true)
        #expect(BackupPlan.decide(expenses: 118, hasMoney: true, today: trusted, newest: trusted, folderHasBackups: true) == .daily)
        #expect(BackupPlan.decide(expenses: 120, hasMoney: true, today: .none, newest: trusted, folderHasBackups: true) == .daily)
    }

    // MARK: Lo que dice la pantalla

    @Test("La nota dice cuántos gastos hay aquí y allá, y de qué día es el otro respaldo")
    func theNoteInPlainWords() {
        let now = mx(2026, 11, 11)
        let note = BackupAsideNote(.fewer(than: .newest, here: 118, there: 131),
                                   comparedWith: "al-dia-2026-11-10.aldia", file: "al-dia-aparte-2026-11-11T210000.aldia")
        #expect(note.message(now: now, timeZone: mexico)
                == "Tu último respaldo se guardó aparte: este iPhone tiene menos gastos (118) que el respaldo del 10 nov (131).")
        let money = BackupAsideNote(.noMoney(than: .today), comparedWith: "al-dia-2026-11-11.aldia", file: "x")
        #expect(money.message(now: now, timeZone: mexico)
                == "Tu último respaldo se guardó aparte: este iPhone no tiene «Mi dinero» y el respaldo del 11 nov sí.")
        let locked = BackupAsideNote(.unreadable, comparedWith: "al-dia-2026-11-11.aldia", file: "x")
        #expect(locked.message(now: now, timeZone: mexico)
                == "Tu último respaldo se guardó aparte: el respaldo del 11 nov no se pudo abrir para compararlo. Puede tener otra contraseña o no haber bajado de iCloud.")
    }

    @Test("Un respaldo de otro año lleva su año; sin día conocido no se inventa una fecha")
    func otherYearsAndUnknownDays() {
        let now = mx(2026, 1, 3)
        let old = BackupAsideNote(.unreadable, comparedWith: "al-dia-2025-12-31.aldia", file: "x")
        #expect(old.otherBackup(now: now, timeZone: mexico) == "el respaldo del 31 dic 2025")
        let unknown = BackupAsideNote(.unreadable, comparedWith: nil, file: "x")
        #expect(unknown.otherBackup(now: now, timeZone: mexico) == "el respaldo anterior")
        var broken = unknown
        broken.day = "2026-02-31"
        #expect(broken.otherBackup(now: now, timeZone: mexico) == "el respaldo anterior")
    }

    @Test("La nota se guarda y se lee igual; lo que no es una nota no dice nada")
    func theNoteRoundTrips() {
        let note = BackupAsideNote(.fewer(than: .today, here: 3, there: 500),
                                   comparedWith: "al-dia-2026-11-10.aldia", file: "al-dia-aparte-2026-11-11T210000.aldia")
        #expect(BackupAsideNote(stored: note.stored) == note)
        #expect(note.day == "2026-11-10")
        #expect(BackupAsideNote(stored: nil) == nil)
        #expect(BackupAsideNote(stored: "") == nil)
        #expect(BackupAsideNote(stored: "{\"kind\":\"otra\",\"file\":\"x\"}") == nil)
    }

    // MARK: Limpieza

    private func asides(_ days: ClosedRange<Int>) -> [String] {
        days.map { BackupRetention.asideName(for: mx(2026, 11, $0), timeZone: mexico) }
    }

    @Test("Se conservan los 5 archivos aparte más nuevos")
    func keepsTheNewestFive() {
        let names = asides(1...8).shuffled()
        #expect(Set(BackupRetention.asidesToDelete(names, now: mx(2026, 11, 9))) == Set(asides(1...3)))
        #expect(BackupRetention.asidesToDelete(asides(1...5), now: mx(2026, 11, 9)).isEmpty)
    }

    @Test("El aparte recién escrito nunca se borra, aunque haya cinco con fecha posterior")
    func theOneJustWrittenAlwaysStays() {
        // The clock was set back (or another device is ahead): five apart files «from the future».
        let written = BackupRetention.asideName(for: mx(2026, 11, 1), timeZone: mexico)
        let later = asides(2...6)
        let now = mx(2026, 11, 1)
        #expect(BackupRetention.asidesToDelete(later + [written], now: now) == [written], "Sin `keeping` se iría el nuevo")
        // It stays and takes one of the five places: the oldest of the others goes.
        #expect(BackupRetention.asidesToDelete(later + [written], keeping: written, now: now) == asides(2...2))
        #expect(BackupRetention.asidesToDelete(asides(2...5) + [written], keeping: written, now: now).isEmpty)
        // Not in the list yet (the folder was read before writing): the same answer.
        #expect(BackupRetention.asidesToDelete(later, keeping: written, now: now) == asides(2...2))
    }

    @Test("Dos del mismo día se ordenan por su hora")
    func sameDayByTime() {
        let morning = BackupRetention.asideName(for: mx(2026, 11, 1, 8), timeZone: mexico)
        let night = BackupRetention.asideName(for: mx(2026, 11, 1, 21), timeZone: mexico)
        let deleted = BackupRetention.asidesToDelete([night, morning] + asides(2...5), now: mx(2026, 11, 9))
        #expect(deleted == [morning])
    }

    @Test("La limpieza de los aparte no toca ningún otro archivo")
    func nothingElseIsTouched() {
        let night = mx(2026, 10, 1)
        let others = [BackupRetention.fileName(for: night, timeZone: mexico),
                      BackupRetention.partialName(for: night, timeZone: mexico),
                      BackupRetention.safetyName(for: night, timeZone: mexico),
                      BackupRetention.replacedName(for: night, timeZone: mexico),
                      "al-dia-aparte-notas.aldia", "al-dia-aparte-2026-10-01T2100.aldia",
                      "al-dia-aparte-2026-10-01T210000.txt", ".al-dia-aparte-2026-10-01T210000.aldia.icloud", "foto.jpg"]
        #expect(BackupRetention.asidesToDelete(others + asides(1...9), now: mx(2026, 11, 9)) .allSatisfy { !others.contains($0) })
        #expect(others.allSatisfy { BackupRetention.asideStamp(of: $0) == nil })
    }

    @Test("Un aparte con año imposible no cuenta entre los 5 y no se borra")
    func impossibleYearsStay() {
        let buddhist = (1...6).map { String(format: "al-dia-aparte-2569-10-%02dT210000.aldia", $0) }
        let deleted = BackupRetention.asidesToDelete(buddhist + asides(1...6), now: mx(2026, 11, 9))
        #expect(deleted == asides(1...1))
    }

    @Test("El archivo reemplazado no es diario ni aparte: ninguna limpieza lo toca")
    func theReplacedFileIsNeverTrimmed() {
        let name = BackupRetention.replacedName(for: mx(2026, 3, 7, 21, 5), timeZone: mexico)
        #expect(name == "al-dia-reemplazado-2026-03-07T210500.aldia")
        #expect(BackupRetention.day(of: name) == nil)
        #expect(BackupRetention.asideStamp(of: name) == nil)
        #expect(BackupRetention.isBackupFile(name))
        #expect(BackupRetention.toDelete([name]).isEmpty)
    }
}
