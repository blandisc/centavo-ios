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

    @Test("Un iPhone vacío con respaldos en la carpeta no respalda ni limpia")
    func anEmptyPhoneDoesNotBackUp() {
        #expect(BackupPlan.decide(expenses: 0, hasMoney: false, today: .none, folderHasBackups: true) == .newPhone)
        #expect(BackupPlan.decide(expenses: 0, hasMoney: false, today: .none, folderHasBackups: false) == .daily)
    }

    @Test("Nunca reemplaza el archivo del día por uno con menos gastos o sin «Mi dinero»")
    func neverReplacesTodaysWithLess() {
        #expect(BackupPlan.decide(expenses: 3, hasMoney: true, today: .holds(expenses: 500, money: true),
                                  folderHasBackups: true) == .aside)
        #expect(BackupPlan.decide(expenses: 500, hasMoney: false, today: .holds(expenses: 500, money: true),
                                  folderHasBackups: true) == .aside)
        #expect(BackupPlan.decide(expenses: 500, hasMoney: true, today: .unreadable, folderHasBackups: true) == .aside)
        #expect(BackupPlan.decide(expenses: 501, hasMoney: true, today: .holds(expenses: 500, money: true),
                                  folderHasBackups: true) == .daily)
        #expect(BackupPlan.decide(expenses: 500, hasMoney: true, today: .holds(expenses: 500, money: false),
                                  folderHasBackups: true) == .daily)
        #expect(BackupPlan.decide(expenses: 2, hasMoney: false, today: .none, folderHasBackups: true) == .daily)
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

    // MARK: Monedas con tres decimales (17)

    @Test("Con KWD, BHD, OMR, JOD, TND, LYD o IQD, tres dígitos al final son decimales", arguments: [
        ("JOD 1.250", "1.25"),
        ("BHD 0.750", "0.75"),
        ("KWD 1,250.500", "1250.5"),
        ("12.345 OMR", "12.345"),
        ("TND 3.5", "3.5"),
    ])
    func threeDecimalCurrencies(_ text: String, _ value: String) throws {
        let parsed = try #require(AmountParser.parse(text))
        #expect(parsed.value == Decimal(string: value)!)
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
        let first = FixedTwins.Key(date: mx(2026, 10, 1), notice: nil, content: "renta|8000")
        let later = FixedTwins.Key(date: mx(2026, 10, 1).addingTimeInterval(0.0003), notice: nil, content: "renta|8000")
        #expect(FixedTwins.keeper([later, first]) == 1)
        #expect(FixedTwins.keeper([first, later]) == 0)
        let noticed = FixedTwins.Key(date: mx(2026, 10, 1), notice: "b", content: "x")
        let other = FixedTwins.Key(date: mx(2026, 10, 1), notice: "a", content: "x")
        #expect(FixedTwins.keeper([noticed, other]) == 1)
        // Nothing tells them apart: no device deletes either (it could be a different one).
        #expect(FixedTwins.keeper([first, first]) == nil)
    }
}
