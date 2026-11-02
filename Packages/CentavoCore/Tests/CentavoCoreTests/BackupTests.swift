@testable import CentavoCore
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

    @Test("Un byte cambiado se nota, y con la contraseña buena dice que está dañado")
    func tampered() throws {
        var file = try BackupSeal.seal(sample(), password: "clave", rounds: rounds)
        file[file.count - 40] ^= 0x01
        #expect(throws: BackupError.damaged) { try BackupSeal.open(file, password: "clave") }
        #expect(throws: BackupError.wrongPassword) { try BackupSeal.open(file, password: "otra") }
    }

    @Test("Un archivo cortado dice que está dañado, no que la contraseña está mal")
    func truncated() throws {
        let file = try BackupSeal.seal(sample(), password: "clave", rounds: rounds)
        for length in [6, 10, 30, 60, file.count / 2, file.count - 1] {
            #expect(throws: BackupError.damaged, "\(length) bytes") {
                try BackupSeal.open(file.prefix(length), password: "clave")
            }
        }
    }

    @Test("Un respaldo de antes del verificador (versión 1) sigue abriendo")
    func legacyFile() throws {
        let old = try BackupSeal.seal(sample(), password: "clave", rounds: rounds, version: 1)
        #expect(old[5] == 1)
        #expect(try BackupSeal.open(old, password: "clave") == sample())
        #expect(throws: BackupError.wrongPassword) { try BackupSeal.open(old, password: "otra") }
        #expect(throws: BackupError.damaged) { try BackupSeal.open(old.prefix(30), password: "clave") }
    }

    @Test("Vueltas absurdas en la cabecera son un archivo dañado, no media hora de espera")
    func absurdRounds() throws {
        var file = try BackupSeal.seal(sample(), password: "clave", rounds: rounds)
        let huge = UInt32(10_000_001).bigEndian
        withUnsafeBytes(of: huge) { file.replaceSubrange(6..<10, with: $0) }
        #expect(throws: BackupError.damaged) { try BackupSeal.open(file, password: "clave") }
        file.replaceSubrange(6..<10, with: [0, 0, 0, 0])
        #expect(throws: BackupError.damaged) { try BackupSeal.open(file, password: "clave") }
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
        newer = newer.replacingOccurrences(of: "\"format\":3", with: "\"format\":4")
        #expect(throws: BackupError.newerFormat) { try BackupPayload.decoded(from: Data(newer.utf8)) }
    }

    @Test("Un respaldo de antes de «Mi dinero» (formato 1) se sigue leyendo, sin dinero")
    func formatOne() throws {
        var old = String(data: try sample().encoded(), encoding: .utf8)!
        old = old.replacingOccurrences(of: "\"format\":3", with: "\"format\":1")
        let back = try BackupPayload.decoded(from: Data(old.utf8))
        #expect(back.money == nil)
        #expect(back.expenses == sample().expenses)
        #expect(back.summary.accountCount == nil)
    }

    @Test("«Mi dinero» viaja en el respaldo, con sus montos exactos")
    func moneyRoundTrip() throws {
        var payload = sample()
        payload.money = BackupMoney(
            accounts: [.init(id: "A1", name: "CETES", kind: "cuenta", currency: "MXN", yearlyRate: "9.8",
                             order: 0, archived: false, createdAt: Date(timeIntervalSinceReferenceDate: 5),
                             subtype: "cuenta", institution: "GBM"),
                       .init(id: "A2", name: "Auto", kind: "deuda", currency: "MXN", yearlyRate: nil,
                             order: 1, archived: false, createdAt: Date(timeIntervalSinceReferenceDate: 6),
                             subtype: "prestamo", institution: nil)],
            cuts: [.init(id: "C1", month: "2026-10", date: Date(timeIntervalSinceReferenceDate: 9), mainCurrency: "MXN",
                         rates: "USD=18.5", entries: [.init(account: "A1", balance: "150000.01", movement: "-0.1")])],
            incomes: [.init(id: "I1", name: "Sueldo", institution: "Arca", amount: "60000", currency: "MXN",
                            since: Date(timeIntervalSinceReferenceDate: 7), archived: false)])
        let file = try BackupSeal.seal(payload, password: "clave", rounds: rounds)
        let back = try BackupSeal.open(file, password: "clave")
        #expect(back == payload)
        #expect(back.summary.accountCount == 2)
        #expect(back.money?.accounts[1].subtype == "prestamo")
        #expect(back.money?.incomes?.first?.amount == "60000")
        #expect(back.summary.cutCount == 1)
    }

    @Test("Lo nuevo viaja: fecha del ingreso, línea revisada, fijos y «¿repetida?»")
    func newFieldsRoundTrip() throws {
        var payload = sample()
        payload.expenses[0].fixedID = "F-1"
        payload.expenses[1].fixedOf = "F-1"
        payload.expenses[2].maybeRepeated = true
        payload.money = BackupMoney(
            accounts: [], cuts: [.init(id: "C1", month: "2026-10", date: Date(timeIntervalSinceReferenceDate: 9),
                                       mainCurrency: "MXN", rates: "",
                                       entries: [.init(account: "A1", balance: "1", reviewed: false),
                                                 .init(account: "A2", balance: "2", reviewed: true)])],
            incomes: [.init(id: "I1", name: "Sueldo", institution: nil, amount: "60000", currency: "MXN",
                            since: Date(timeIntervalSinceReferenceDate: 7), archived: false,
                            createdAt: Date(timeIntervalSinceReferenceDate: 8),
                            until: Date(timeIntervalSinceReferenceDate: 9))])
        let back = try BackupSeal.open(BackupSeal.seal(payload, password: "clave", rounds: rounds), password: "clave")
        #expect(back == payload)
        #expect(back.expenses.map(\.fixedID) == ["F-1", nil, nil])
        #expect(back.expenses.map(\.fixedOf) == [nil, "F-1", nil])
        #expect(back.expenses.map(\.maybeRepeated) == [nil, nil, true])
        #expect(back.money?.cuts[0].entries.map(\.reviewed) == [false, true])
        #expect(back.money?.incomes?[0].createdAt == Date(timeIntervalSinceReferenceDate: 8))
        #expect(back.money?.incomes?[0].until == Date(timeIntervalSinceReferenceDate: 9))
    }

    @Test("Un archivo de antes de esos campos se lee con todos vacíos")
    func oldFileWithoutNewFields() throws {
        let old = #"{"createdAt":1,"expenses":[{"amount":"5","date":2,"merchant":"Oxxo"}],"format":3,"#
            + #""money":{"accounts":[],"cuts":[{"date":3,"entries":[{"account":"A","balance":"1"}],"id":"C","mainCurrency":"MXN","month":"2026-10","rates":""}],"#
            + #""incomes":[{"amount":"1","archived":false,"currency":"MXN","id":"I","name":"N","since":4}]},"settings":{},"writtenBy":"x"}"#
        let back = try BackupPayload.decoded(from: Data(old.utf8))
        #expect(back.expenses[0].fixedID == nil && back.expenses[0].fixedOf == nil && back.expenses[0].maybeRepeated == nil)
        #expect(back.money?.cuts[0].entries[0].reviewed == nil)
        #expect(back.money?.incomes?[0].createdAt == nil)
    }

    @Test("Un número que no es número (NaN, infinito) no tumba el respaldo: se queda fuera")
    func nonFiniteNumbersAreLeftOut() throws {
        var payload = sample()
        payload.settings["roto"] = .number(.nan)
        payload.settings["infinito"] = .number(-.infinity)
        payload.expenses[0].latitude = .nan
        payload.expenses[0].longitude = .infinity
        let back = try BackupPayload.decoded(from: payload.encoded())
        #expect(back.settings["roto"] == nil && back.settings["infinito"] == nil)
        #expect(back.settings["ritmo"] == .number(0.55))
        #expect(back.expenses[0].latitude == nil && back.expenses[0].longitude == nil)
        #expect(back.expenses[1].latitude == sample().expenses[1].latitude)
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
