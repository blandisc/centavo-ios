import CentavoCore
import Foundation
import Testing

@Suite("El respaldo con contraseña")
struct BackupTests {
    /// Few rounds: the tests check the format, not how slow it is to guess.
    let rounds: UInt32 = 1_000

    func sample() -> BackupPayload {
        var rent = BackupExpense(amount: Decimal(string: "12500.50")!, date: Date(timeIntervalSinceReferenceDate: 783_456_789.123_456),
                                 merchant: "Renta")
        rent.repeatsMonthly = true
        rent.repeatRule = "mensual"
        rent.category = "Casa"
        var coffee = BackupExpense(amount: Decimal(string: "0.1")!, date: Date(timeIntervalSinceReferenceDate: 783_500_000),
                                   merchant: "OXXO 1234")
        coffee.countedAmount = BackupNumber.text(0)
        coffee.uncountedReason = "reembolso"
        coffee.latitude = 25.686_614_123_456_7
        var refund = BackupExpense(amount: Decimal(string: "-1234.56")!, date: .init(timeIntervalSinceReferenceDate: 783_600_000),
                                   merchant: "Amazon")
        refund.currencyMarker = "US$"
        return BackupPayload(createdAt: Date(timeIntervalSinceReferenceDate: 783_700_000.5), writtenBy: "prueba",
                             expenses: [rent, coffee, refund],
                             settings: ["monthlyBudget": .text("40000"), "noUsaWallet": .flag(true),
                                        "vista": .whole(2), "ritmo": .number(0.55),
                                        "primeraVez": .date(.init(timeIntervalSinceReferenceDate: 1))])
    }

    @Test("Ida y vuelta: sale exactamente lo que entró, centavos y fechas incluidos")
    func roundTrip() throws {
        let payload = sample()
        let file = try BackupSeal.seal(payload, password: "mi clave", rounds: rounds)
        let back = try BackupSeal.open(file, password: "mi clave")
        #expect(back == payload)
        #expect(back.expenses[1].amountValue == Decimal(string: "0.1"))
        #expect(back.expenses[2].amountValue == Decimal(string: "-1234.56"))
        #expect(back.expenses[1].countedValue == .some(0))
        #expect(back.expenses[0].countedValue == .some(nil))
    }

    @Test("Con otra contraseña no abre, ni abre en otra cosa")
    func wrongPassword() throws {
        let file = try BackupSeal.seal(sample(), password: "mi clave", rounds: rounds)
        #expect(throws: BackupError.wrongPassword) { try BackupSeal.open(file, password: "Mi clave") }
        #expect(throws: BackupError.wrongPassword) { try BackupSeal.open(file, password: "") }
    }

    @Test("Un byte cambiado se nota")
    func tampered() throws {
        var file = try BackupSeal.seal(sample(), password: "clave", rounds: rounds)
        file[file.count - 40] ^= 0x01
        #expect(throws: BackupError.wrongPassword) { try BackupSeal.open(file, password: "clave") }
    }

    @Test("Un archivo que no es respaldo lo dice")
    func notABackup() {
        #expect(throws: BackupError.notABackup) { try BackupSeal.open(Data("Fecha,Comercio,Monto".utf8), password: "x") }
        #expect(throws: BackupError.notABackup) { try BackupSeal.open(Data(), password: "x") }
    }

    @Test("Dos respaldos iguales no se parecen: cada uno lleva su sal")
    func saltPerFile() throws {
        let one = try BackupSeal.seal(sample(), password: "clave", rounds: rounds)
        let two = try BackupSeal.seal(sample(), password: "clave", rounds: rounds)
        #expect(one != two)
    }

    @Test("La contraseña se compara igual aunque el acento venga escrito de otra forma")
    func unicodePassword() throws {
        let file = try BackupSeal.seal(sample(), password: "ca\u{00F1}a", rounds: rounds)
        #expect(try BackupSeal.open(file, password: "can\u{0303}a") == sample())
    }

    @Test("Un respaldo de una versión más nueva lo dice en vez de fallar raro")
    func newerFormat() throws {
        var newer = String(data: try sample().encoded(), encoding: .utf8)!
        newer = newer.replacingOccurrences(of: "\"format\":1", with: "\"format\":2")
        #expect(throws: BackupError.newerFormat) { try BackupPayload.decoded(from: Data(newer.utf8)) }
    }

    @Test("Los montos se escriben con punto, sea cual sea la región")
    func numbers() {
        #expect(BackupNumber.text(Decimal(string: "1234.5")!) == "1234.5")
        #expect(BackupNumber.value("1,234.5") == nil)
        #expect(BackupNumber.value("") == nil)
        #expect(BackupNumber.value("12e3") == nil)
    }

    @Test("El resumen dice cuántos gastos y de cuándo a cuándo")
    func summary() {
        let summary = sample().summary
        #expect(summary.expenseCount == 3)
        #expect(summary.firstExpense == Date(timeIntervalSinceReferenceDate: 783_456_789.123_456))
        #expect(summary.lastExpense == Date(timeIntervalSinceReferenceDate: 783_600_000))
    }
}

@Suite("Qué respaldos se conservan")
struct BackupRetentionTests {
    func names(_ days: [String]) -> [String] { days.map { "al-dia-\($0).aldia" } }

    @Test("El nombre del archivo es el día")
    func fileName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 21))!
        #expect(BackupRetention.fileName(for: day, calendar: calendar) == "al-dia-2026-03-07.aldia")
    }

    @Test("Con 30 o menos no se borra nada")
    func fewKept() {
        let days = (1...30).map { String(format: "2026-10-%02d", $0) }
        #expect(BackupRetention.toDelete(names(days)).isEmpty)
    }

    @Test("Se quedan los últimos 30 días y el más nuevo de cada mes anterior")
    func trims() {
        let september = (1...30).map { String(format: "2026-09-%02d", $0) }
        let october = (1...31).map { String(format: "2026-10-%02d", $0) }
        let deleted = BackupRetention.toDelete(names(["2026-08-15", "2026-08-31"] + september + october))
        // The newest 30 are Oct 2–31. Kept besides: Sep 30 (newest of September), Aug 31.
        // Oct 1 falls out of the 30, but October's newest is Oct 31, so it goes.
        #expect(Set(deleted) == Set(names(["2026-08-15", "2026-10-01"] + (1...29).map { String(format: "2026-09-%02d", $0) })))
    }

    @Test("Nunca toca un archivo que no es respaldo")
    func othersSafe() {
        let others = ["foto.jpg", "al-dia-notas.aldia", "al-dia-2026-10-01.txt", "Al día.csv"]
        let backups = names((1...40).map { String(format: "2026-%02d-01", ($0 % 12) + 1) })
        let deleted = BackupRetention.toDelete(others + backups)
        #expect(deleted.allSatisfy { !others.contains($0) })
    }
}
