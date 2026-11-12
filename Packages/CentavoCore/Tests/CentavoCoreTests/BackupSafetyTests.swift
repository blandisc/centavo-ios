import Foundation
import Testing
@testable import CentavoCore

/// La copia «antes de restaurar» (2026-11-11): nunca se reemplaza sin una copia a la vista, las
/// copias que quedaron dentro de la app se listan, y un iPhone restaurado sin respaldo lo dice.
@Suite("Copia antes de restaurar y respaldo sin configurar")
struct BackupSafetyTests {
    private let mexico = TimeZone(identifier: "America/Mexico_City")!

    private func mx(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 21, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mexico
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// iOS writes «9:40 p.m.» with a narrow space that doesn't break.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: Qué hay que hacer antes de restaurar

    @Test("Con gastos y carpeta, la copia va a la carpeta")
    func copiesToTheFolder() {
        #expect(BackupSafetyPlan.decide(expenses: 12, hasMoney: false, configured: false, folderUsable: true) == .copyToFolder)
        #expect(BackupSafetyPlan.decide(expenses: 0, hasMoney: true, configured: false, folderUsable: true) == .copyToFolder)
    }

    @Test("Con algo que guardar y sin carpeta, se pide dónde: nunca se restaura sin copia")
    func asksWhereWithoutAFolder() {
        #expect(BackupSafetyPlan.decide(expenses: 1, hasMoney: false, configured: false, folderUsable: false) == .askWhere)
        #expect(BackupSafetyPlan.decide(expenses: 0, hasMoney: true, configured: false, folderUsable: false) == .askWhere)
    }

    @Test("Un iPhone vacío no tiene nada que copiar, con carpeta o sin ella")
    func anEmptyPhoneHasNothingToCopy() {
        #expect(BackupSafetyPlan.decide(expenses: 0, hasMoney: false, configured: false, folderUsable: false) == .nothingToCopy)
        #expect(BackupSafetyPlan.decide(expenses: 0, hasMoney: false, configured: false, folderUsable: true) == .nothingToCopy)
    }

    @Test("Sin gastos pero con presupuesto o listas propias no está vacío: se copia, o se pide dónde")
    func configuredIsNotEmpty() {
        #expect(BackupSafetyPlan.decide(expenses: 0, hasMoney: false, configured: true, folderUsable: true) == .copyToFolder)
        #expect(BackupSafetyPlan.decide(expenses: 0, hasMoney: false, configured: true, folderUsable: false) == .askWhere)
    }

    @Test("Configurado: alguna de las llaves de la persona trae algo; lo vacío y lo ajeno no cuentan")
    func whatCountsAsConfigured() {
        let keys = ["monthlyBudget", "customCategories", "categoryRules", "fijosPorEmpezar"]
        func configured(_ settings: [String: BackupSetting]) -> Bool { BackupSafetyPlan.isConfigured(settings, keys: keys) }
        #expect(!configured([:]))
        // What the welcome leaves on every phone isn't the person's set-up.
        #expect(!configured(["onboarded": .flag(true), "primaryCurrency": .text("MXN")]))
        #expect(!configured(["monthlyBudget": .text(""), "customCategories": .text("[]"), "categoryRules": .text(" { } "),
                             "fijosPorEmpezar": .text("null")]))
        #expect(!configured(["monthlyBudget": .text("0"), "customCategories": .whole(0), "categoryRules": .flag(false),
                             "fijosPorEmpezar": .number(0)]))
        #expect(configured(["monthlyBudget": .text("8000")]))
        #expect(configured(["customCategories": .text("[\"Mascotas\"]")]))
        #expect(configured(["categoryRules": .text("{\"OXXO\":\"Súper\"}")]))
        #expect(configured(["fijosPorEmpezar": .text("[{\"name\":\"Renta\"}]")]))
        #expect(configured(["monthlyBudget": .whole(8000)]))
        #expect(configured(["monthlyBudget": .date(Date(timeIntervalSince1970: 0))]))
    }

    // MARK: Las copias que quedaron dentro de la app

    @Test("El nombre de una copia dice cuándo se tomó")
    func theNameTellsWhen() {
        let taken = mx(2026, 11, 12, 21, 40, 5)
        let name = BackupRetention.safetyName(for: taken, timeZone: mexico)
        #expect(name == "al-dia-antes-de-restaurar-2026-11-12T214005.aldia")
        #expect(BackupRetention.safetyDate(of: name, timeZone: mexico) == taken)
    }

    @Test("Solo las copias «antes de restaurar» cuentan: ni diarios, ni aparte, ni nombres rotos")
    func onlySafetyCopiesCount() {
        for name in ["al-dia-2026-11-12.aldia", "al-dia-aparte-2026-11-12T214005.aldia",
                     "al-dia-reemplazado-2026-11-12T214005.aldia", "al-dia-solo-gastos-2026-11-12.aldia",
                     "al-dia-antes-de-restaurar-2026-11-12T214005.txt", "al-dia-antes-de-restaurar-2026-11-12.aldia",
                     "al-dia-antes-de-restaurar-2026-13-45T214005.aldia", "al-dia-antes-de-restaurar-2026-11-12T256199.aldia",
                     "al-dia-antes-de-restaurar-2026-11-1xT214005.aldia", "notas.txt", ""] {
            #expect(BackupRetention.safetyDate(of: name, timeZone: mexico) == nil, "\(name)")
        }
    }

    @Test("Se listan de la más nueva a la más vieja, con su fecha a la vista")
    func listedNewestFirst() {
        let names = ["al-dia-antes-de-restaurar-2026-11-02T090000.aldia", "al-dia-2026-11-12.aldia",
                     "al-dia-antes-de-restaurar-2026-11-12T214000.aldia", "otra-cosa.pdf",
                     "al-dia-antes-de-restaurar-2025-12-31T235900.aldia"]
        let copies = BackupSafetyCopy.list(names, timeZone: mexico)
        #expect(copies.map(\.name) == [names[2], names[0], names[4]])
        let now = mx(2026, 11, 13)
        #expect(plain(copies[0].title(now: now, timeZone: mexico)) == "12 nov, 9:40 p.m.")
        #expect(plain(copies[1].title(now: now, timeZone: mexico)) == "2 nov, 9:00 a.m.")
        // Another year says which.
        #expect(plain(copies[2].title(now: now, timeZone: mexico)) == "31 dic 2025, 11:59 p.m.")
    }

    // MARK: Restaurado y sin respaldo

    @Test("Un iPhone que nunca se restauró no recibe el aviso")
    func neverRestoredSaysNothing() {
        #expect(!BackupSetupReminder.isDue(restoredAt: nil, saidLaterAt: nil, now: mx(2026, 11, 12)))
        #expect(!BackupSetupReminder.isDue(restoredAt: nil, saidLaterAt: mx(2026, 10, 1), now: mx(2026, 11, 12)))
    }

    @Test("Recién restaurado y sin respaldo: «Hoy» lo dice")
    func restoredSaysIt() {
        #expect(BackupSetupReminder.isDue(restoredAt: mx(2026, 11, 12), saidLaterAt: nil, now: mx(2026, 11, 12, 22)))
    }

    @Test("Tras «Ahora no» calla una semana y luego vuelve, una vez por semana")
    func quietForAWeekAfterLater() {
        let restored = mx(2026, 11, 12), later = mx(2026, 11, 12, 21, 5)
        #expect(!BackupSetupReminder.isDue(restoredAt: restored, saidLaterAt: later, now: mx(2026, 11, 13)))
        #expect(!BackupSetupReminder.isDue(restoredAt: restored, saidLaterAt: later, now: mx(2026, 11, 19, 21, 4)))
        #expect(BackupSetupReminder.isDue(restoredAt: restored, saidLaterAt: later, now: mx(2026, 11, 19, 21, 5)))
        // Seen again on the backup's screen that day: quiet for another week.
        let seen = mx(2026, 11, 20, 8)
        #expect(!BackupSetupReminder.isDue(restoredAt: restored, saidLaterAt: seen, now: mx(2026, 11, 26)))
        #expect(BackupSetupReminder.isDue(restoredAt: restored, saidLaterAt: seen, now: mx(2026, 11, 27, 8)))
    }

    @Test("Un reloj movido no lo esconde para siempre")
    func aClockSetBackDoesNotHideItForGood() {
        let restored = mx(2026, 11, 12)
        #expect(BackupSetupReminder.isDue(restoredAt: restored, saidLaterAt: mx(2030, 1, 1), now: mx(2026, 11, 13)))
    }

    @Test("El aviso de «Hoy» dice dónde arreglarlo")
    func theWarningSaysWhere() {
        #expect(BackupSetupReminder.warning
            == "El respaldo diario no está configurado en este iPhone. Configúralo en Más › Ajustes › Respaldo diario.")
    }
}
