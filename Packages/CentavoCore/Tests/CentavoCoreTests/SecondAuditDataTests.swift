import Foundation
import Testing
@testable import CentavoCore

/// Segunda auditoría (2026-11-02), parte de datos: cada prueba reproduce una falla encontrada.
@Suite("Segunda auditoría: datos")
struct SecondAuditDataTests {
    private let mexico = TimeZone(identifier: "America/Mexico_City")!

    private func mx(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mexico
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Nombres de archivo (6)

    @Test("A las 21:00 en México el respaldo lleva la fecha de hoy, no la de mañana")
    func namesUseTheLocalDay() {
        let night = mx(2026, 3, 7, 21, 5)
        #expect(BackupRetention.fileName(for: night, timeZone: mexico) == "al-dia-2026-03-07.aldia")
        #expect(BackupRetention.partialName(for: night, timeZone: mexico) == "al-dia-solo-gastos-2026-03-07.aldia")
        #expect(BackupRetention.safetyName(for: night, timeZone: mexico) == "al-dia-antes-de-restaurar-2026-03-07T210500.aldia")
        #expect(BackupRetention.asideName(for: night, timeZone: mexico) == "al-dia-aparte-2026-03-07T210500.aldia")
    }

    @Test("Ninguno de los nombres aparte lo toca la limpieza")
    func asideNamesAreNeverTrimmed() {
        let night = mx(2026, 3, 7, 21)
        let others = [BackupRetention.partialName(for: night, timeZone: mexico),
                      BackupRetention.safetyName(for: night, timeZone: mexico),
                      BackupRetention.asideName(for: night, timeZone: mexico)]
        #expect(others.allSatisfy { BackupRetention.day(of: $0) == nil })
        #expect(others.allSatisfy(BackupRetention.isBackupFile))
    }

    @Test("Un iPhone con calendario japonés o budista sigue escribiendo el año gregoriano")
    func gregorianWhateverThePhoneUses() {
        // The calendar the names are written with never comes from the phone's settings.
        #expect(BackupRetention.calendar(in: mexico).identifier == .gregorian)
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = mexico
        let day = mx(2026, 3, 7)
        #expect(japanese.component(.year, from: day) != 2026, "El calendario japonés numera otro año")
        #expect(BackupRetention.fileName(for: day, timeZone: mexico) == "al-dia-2026-03-07.aldia")
    }

    // MARK: Un respaldo vacío no pisa el bueno (2)

    private func decide(_ expenses: Int, money: Bool = true, today: BackupPlan.Today = .none,
                        newest: BackupPlan.Today = .none, folder: Bool = true) -> BackupPlan {
        BackupPlan.decide(expenses: expenses, hasMoney: money, today: today, newest: newest, folderHasBackups: folder)
    }

    @Test("Un iPhone vacío con respaldos en la carpeta no respalda ni limpia")
    func anEmptyPhoneDoesNotBackUp() {
        #expect(decide(0, money: false, newest: .holds(expenses: 80, money: false)) == .newPhone)
        #expect(decide(0, money: false, newest: .unreadable) == .newPhone)
        #expect(decide(0, money: false, folder: false) == .daily)
    }

    @Test("Quien solo usa «Mi dinero», o borró sus gastos, sigue respaldando")
    func onlyMiDineroStillBacksUp() {
        #expect(decide(0, money: true, newest: .holds(expenses: 0, money: true)) == .daily)
        // Everything deleted on purpose, and an empty backup before: nothing to protect.
        #expect(decide(0, money: false, newest: .holds(expenses: 0, money: false)) == .daily)
    }

    @Test("Un iPhone nuevo con unos gastos no pisa ni limpia el respaldo más reciente, aunque sea de otro día")
    func aNewPhoneWithAFewExpensesGoesAside() {
        #expect(decide(3, newest: .holds(expenses: 500, money: true)) == .aside)
        #expect(decide(500, money: false, newest: .holds(expenses: 500, money: true)) == .aside)
        // A few deleted is normal life.
        #expect(decide(497, newest: .holds(expenses: 500, money: true)) == .daily)
        // Another password (or not downloaded): written, but nothing old is trimmed.
        #expect(decide(500, newest: .unreadable) == .dailyKeepingOld)
    }

    @Test("Nunca reemplaza el archivo del día por uno con menos gastos o sin «Mi dinero»")
    func neverReplacesTodaysWithLess() {
        #expect(decide(3, today: .holds(expenses: 500, money: true)) == .aside)
        #expect(decide(500, money: false, today: .holds(expenses: 500, money: true)) == .aside)
        #expect(decide(500, today: .unreadable) == .aside)
        #expect(decide(501, today: .holds(expenses: 500, money: true)) == .daily)
        #expect(decide(500, today: .holds(expenses: 500, money: false)) == .daily)
        #expect(decide(499, today: .holds(expenses: 500, money: true)) == .aside)
    }

    @Test("Nombres con años imposibles (calendario budista) no ocupan lugar entre los 30 y no se borran")
    func impossibleYearsStayQuiet() {
        let now = mx(2026, 11, 2)
        let buddhist = (1...5).map { String(format: "al-dia-2569-10-%02d.aldia", $0) }
        let real = (1...30).map { String(format: "al-dia-2026-10-%02d.aldia", $0) } + ["al-dia-2026-09-15.aldia", "al-dia-2026-09-30.aldia"]
        let deleted = BackupRetention.toDelete(buddhist + real, now: now)
        #expect(deleted == ["al-dia-2026-09-15.aldia"])
        #expect(BackupRetention.newestDaily(buddhist + real, now: now) == "al-dia-2026-10-30.aldia")
    }

    // MARK: El corte a medias en la copia previa (4)

    @Test("La copia previa lleva los borradores y un archivo de antes se sigue leyendo")
    func draftsTravelInTheSafetyCopy() throws {
        let draft = BackupMoney.Cut(id: "c", month: "2026-11", date: mx(2026, 11, 2), mainCurrency: "MXN", rates: "",
                                    entries: [.init(account: "a", balance: "10.5", reviewed: false)], reviewedRates: "USD")
        let money = BackupMoney(accounts: [], cuts: [], incomes: [], drafts: [draft])
        let payload = BackupPayload(createdAt: mx(2026, 11, 2), writtenBy: "prueba", expenses: [], settings: [:], money: money)
        let back = try BackupPayload.decoded(from: payload.encoded())
        #expect(back.money?.drafts == [draft])
        let old = BackupPayload(createdAt: mx(2026, 11, 2), writtenBy: "prueba", expenses: [], settings: [:],
                                money: BackupMoney(accounts: [], cuts: []))
        #expect(try BackupPayload.decoded(from: old.encoded()).money?.drafts == nil)
    }

    @Test("Antes de apartar un «Mi dinero» dañado, todo lo del respaldo se comprueba")
    func miDineroIsCheckedWhole() {
        let account = BackupMoney.Account(id: "a", name: "Nu", kind: "cuenta", currency: "MXN", yearlyRate: "9.5",
                                          order: 0, archived: false, createdAt: mx(2026, 10, 1))
        let line = BackupMoney.Entry(account: "a", balance: "10.5")
        let cut = BackupMoney.Cut(id: "c", month: "2026-10", date: mx(2026, 10, 31), mainCurrency: "MXN", rates: "",
                                  entries: [line])
        #expect(BackupMoney(accounts: [account], cuts: [cut]).isWhole)
        var lost = cut
        lost.entries = [BackupMoney.Entry(account: "otra", balance: "1")]
        #expect(!BackupMoney(accounts: [account], cuts: [], drafts: [lost]).isWhole, "Un borrador con una cuenta que no viene")
        var broken = cut
        broken.entries = [BackupMoney.Entry(account: "a", balance: "12,5OO")]
        #expect(!BackupMoney(accounts: [account], cuts: [broken]).isWhole)
        var badRate = account
        badRate.yearlyRate = "x"
        #expect(!BackupMoney(accounts: [badRate], cuts: []).isWhole)
        let income = BackupMoney.Income(id: "i", name: "Sueldo", institution: nil, amount: "mil", currency: "MXN",
                                        since: mx(2026, 1, 1), archived: false)
        #expect(!BackupMoney(accounts: [], cuts: [], incomes: [income]).isWhole)
        #expect(!BackupMoney(accounts: [], cuts: []).hasContent)
        #expect(BackupMoney(accounts: [account], cuts: []).hasContent)
    }

    // MARK: iCloud lleno (3)

    @Test("Avisa si el último archivo no subió o lleva más de un día subiendo")
    func warnsWhenTheFileDidNotGoUp() {
        let written = mx(2026, 11, 1, 21)
        #expect(BackupCloud.isStuck(.failed, writtenAt: written, now: written))
        #expect(!BackupCloud.isStuck(.uploading, writtenAt: written, now: written.addingTimeInterval(3_600)))
        #expect(BackupCloud.isStuck(.uploading, writtenAt: written, now: written.addingTimeInterval(25 * 3_600)))
        #expect(!BackupCloud.isStuck(.uploaded, writtenAt: written, now: written.addingTimeInterval(99 * 3_600)))
        #expect(!BackupCloud.isStuck(.local, writtenAt: written, now: written.addingTimeInterval(99 * 3_600)))
    }

    @Test("En iCloud, la limpieza espera a que el respaldo anterior haya subido")
    func trimsOnlyAfterTheLastOneWentUp() {
        #expect(BackupCloud.mayTrim(folderInCloud: true, previous: .uploaded))
        #expect(!BackupCloud.mayTrim(folderInCloud: true, previous: .uploading))
        #expect(!BackupCloud.mayTrim(folderInCloud: true, previous: .failed))
        #expect(!BackupCloud.mayTrim(folderInCloud: true, previous: nil))
        #expect(BackupCloud.mayTrim(folderInCloud: false, previous: nil))
    }

    // MARK: El mismo pago por las dos automatizaciones (11)

    @Test("El mismo pago por «Transacción» y por «Notificación» se marca, aunque el texto sea otro")
    func bothAutomationsMarkTheSecond() {
        let now = mx(2026, 11, 2, 13)
        let fromWallet = RecentCapture(amount: 89, merchant: "OXXO ROBLE MTY", card: "Amex",
                                       date: now.addingTimeInterval(-40), currency: "MXN", fromNotice: false)
        #expect(CaptureGuard.check(amount: 89, merchant: "Oxxo", card: "American Express México", at: now,
                                   recent: [fromWallet], currency: "MXN", fromNotice: true) == .duplicate)
        // Another currency, or later than two minutes, is another payment.
        #expect(CaptureGuard.check(amount: 89, merchant: "Oxxo", card: "American Express México", at: now,
                                   recent: [fromWallet], currency: "USD", fromNotice: true) == .save)
        #expect(CaptureGuard.check(amount: 89, merchant: "Oxxo", card: nil, at: now.addingTimeInterval(200),
                                   recent: [fromWallet], currency: "MXN", fromNotice: true) == .save)
        // Two notices with different shops are two purchases.
        let notice = RecentCapture(amount: 89, merchant: "Starbucks", card: "Amex", date: now.addingTimeInterval(-40),
                                   currency: "MXN", fromNotice: true)
        #expect(CaptureGuard.check(amount: 89, merchant: "Oxxo", card: "Amex", at: now,
                                   recent: [notice], currency: "MXN", fromNotice: true) == .save)
    }

    @Test("Entre automatizaciones, $50 en OXXO y $50 en Starbucks un minuto después son dos compras")
    func otherSourceNeedsALikeShopOrCard() {
        let now = mx(2026, 11, 2, 13)
        let oxxo = RecentCapture(amount: 50, merchant: "OXXO ROBLE MTY", card: "Amex", date: now.addingTimeInterval(-60),
                                 currency: "MXN", fromNotice: false)
        #expect(CaptureGuard.check(amount: 50, merchant: "Starbucks", card: "American Express México", at: now,
                                   recent: [oxxo], currency: "MXN", fromNotice: true) == .save)
        // The same card, written the same, is enough.
        #expect(CaptureGuard.check(amount: 50, merchant: "Starbucks", card: "amex", at: now,
                                   recent: [oxxo], currency: "MXN", fromNotice: true) == .duplicate)
    }

    @Test("Un pago ya emparejado con su aviso no marca a otro")
    func pairsAreOneToOne() {
        let now = mx(2026, 11, 2, 13)
        let wallet = RecentCapture(amount: 50, merchant: "OXXO ROBLE MTY", card: "Amex", date: now.addingTimeInterval(-90),
                                   currency: "MXN", fromNotice: false)
        var notice = RecentCapture(amount: 50, merchant: "Oxxo", card: "American Express México",
                                   date: now.addingTimeInterval(-60), currency: "MXN", fromNotice: true)
        notice.markedRepeated = true
        // A second Oxxo coffee through «Transacción»: the notice is already the pair of the first.
        #expect(CaptureGuard.check(amount: 50, merchant: "OXXO", card: "Amex", at: now,
                                   recent: [wallet, notice], currency: "MXN", fromNotice: false) == .save)
        #expect(CaptureGuard.check(amount: 50, merchant: "Oxxo Roble", card: nil, at: now,
                                   recent: [wallet, notice], currency: "MXN", fromNotice: true) == .save)
    }

    // MARK: Monedas con tres decimales (17)

    @Test("Con KWD, BHD, OMR, JOD, TND o LYD, tres dígitos tras el punto son decimales", arguments: [
        ("JOD 1.250", "1.25"),
        ("BHD 0.750", "0.75"),
        ("KWD 1,250.500", "1250.5"),
        ("12.345 OMR", "12.345"),
        ("TND 3.5", "3.5"),
        ("LYD 1250", "1250"),
    ])
    func threeDecimalCurrencies(_ text: String, _ value: String) throws {
        let parsed = try #require(AmountParser.parse(text))
        #expect(parsed.value == Decimal(string: value)!)
    }

    @Test("Lo dudoso en dinares no se lee como un monto falso: queda para avisar")
    func doubtfulDinarsAreNotGuessed() {
        // «1,250» could be a thousand or one and a quarter; «1.250.500» has nothing after its
        // decimals. Neither is guessed.
        #expect(AmountParser.parse("JOD 1,250") == nil)
        #expect(AmountParser.parse("KWD 1.250.500") == nil)
        #expect(WalletNotice.mentionsMoney("Visa\nTienda\nJOD 1,250"))
    }

    @Test("El dinar iraquí no usa decimales: «IQD 1.250» son mil doscientos cincuenta, como iOS lo escribe")
    func iraqiDinarHasNoDecimals() throws {
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.currencyCode = "IQD"
        #expect(format.maximumFractionDigits == 0)
        #expect(!AmountParser.threeDecimalCurrencies.contains("IQD"))
        #expect(try #require(AmountParser.parse("IQD 1.250")).value == 1_250)
    }

    @Test("Las demás monedas siguen igual: «MXN 1.250» son mil doscientos cincuenta")
    func otherCurrenciesUnchanged() throws {
        #expect(try #require(AmountParser.parse("MXN 1.250")).value == 1_250)
        #expect(AmountParser.parse("$0.750") == nil)
    }

    @Test("Un aviso de Wallet en dinares se lee")
    func aNoticeInDinarsReads() throws {
        let notice = try #require(WalletNotice.parse("Visa ••••1234\nCarrefour\nBHD 0.750"))
        #expect(notice.amount.value == Decimal(string: "0.75")!)
        #expect(notice.merchant == "Carrefour")
    }

    @Test("Un aviso con código de moneda que no se pudo leer no se pierde en silencio")
    func aNoticeWithACurrencyIsKept() {
        #expect(WalletNotice.mentionsMoney("Amex\nTienda\nMXN 1.2.3"))
        #expect(WalletNotice.mentionsMoney("Amex · Tienda · USD 12,3456"))
        #expect(!WalletNotice.mentionsMoney("Tu pase de abordar está listo"))
        #expect(!WalletNotice.mentionsMoney("Juan te envió MXN 300.00"), "Dinero que llega no es un cargo")
    }

    // MARK: Dinero recibido, palabras completas (20)

    @Test("«Flete Envío» es una compra, no dinero recibido")
    func wholeWordsForMoneyIn() throws {
        let notice = try #require(WalletNotice.parse("BBVA\nFlete Envío\nMXN 300.00"))
        #expect(notice.amount.value == 300)
        #expect(WalletNotice.parse("Apple Cash\nAna te envió\nMXN 300.00") == nil)
        #expect(WalletNotice.parse("Apple Cash\nAna te mandó MXN 300.00") == nil)
        #expect(try #require(WalletNotice.parse("Amex\nCorte Envíos Express\nMXN 450.00")).amount.value == 450)
    }

    // MARK: Marcar un gasto viejo como «Cada mes» (14)

    @Test("Netflix del 25 de octubre marcado el 10 de noviembre: el 25 de noviembre se anota")
    func markingAnOldExpenseKeepsThisMonthsCharge() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mexico
        let netflix = mx(2026, 10, 25)
        let marked = mx(2026, 11, 10)
        let through = RecurringSchedule.lastCharge(rule: .monthly, anchor: netflix, through: marked, calendar: calendar)
        #expect(through == netflix)
        let due = RecurringSchedule.dates(rule: .monthly, anchor: netflix, after: through, through: mx(2026, 11, 30),
                                          calendar: calendar)
        #expect(due == [mx(2026, 11, 25)])
        // The old way (from the day it was marked) skipped it.
        #expect(RecurringSchedule.dates(rule: .monthly, anchor: netflix, after: marked, through: mx(2026, 11, 30),
                                        calendar: calendar).isEmpty)
        // Marked after this month's charge already came: that one isn't logged again.
        #expect(RecurringSchedule.lastCharge(rule: .monthly, anchor: netflix, through: mx(2026, 11, 30),
                                             calendar: calendar) == mx(2026, 11, 25))
    }

    // MARK: Dos originales del mismo fijo (12)

    @Test("Dos originales del mismo fijo: cada dispositivo conserva el mismo")
    func theSameOriginalIsKeptEverywhere() {
        let first = mx(2026, 10, 1)
        let later = mx(2026, 10, 1).addingTimeInterval(0.0003)
        #expect(FixedTwins.keeper([later, first]) == 1)
        #expect(FixedTwins.keeper([first, later]) == 0)
        // The same date: what differs is likely an edit (Netflix 299 → 329) not yet synced, so
        // the content never decides; neither is deleted.
        #expect(FixedTwins.keeper([first, first]) == nil)
        #expect(FixedTwins.keeper([first, first, later]) == nil)
    }
}
