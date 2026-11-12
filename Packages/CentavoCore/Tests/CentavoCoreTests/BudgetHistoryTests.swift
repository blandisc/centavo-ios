import Foundation
import Testing
@testable import CentavoCore

/// El historial del presupuesto (2026-11-11): qué presupuesto juzga cada mes y desde qué día
/// cuenta el de este mes.
@Suite struct BudgetHistoryTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static let madrid: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }()

    private static func at(_ month: Int, _ day: Int, year: Int = 2026, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func terms(_ history: BudgetHistory, month: Date, current: Decimal?, now: Date,
                       calendar: Calendar = BudgetHistoryTests.calendar) -> BudgetTerms {
        history.terms(for: month, current: current, now: now, calendar: calendar)
    }

    private func record(_ history: BudgetHistory, _ amount: Decimal?, previous: Decimal?, on date: Date) -> BudgetHistory {
        history.recording(amount, previous: previous, on: date, calendar: Self.calendar)
    }

    // MARK: Sin historial: «desde siempre»

    @Test func aBudgetWithNoListHasAlwaysBeenThatOne() {
        // Todos los de hoy: presupuesto y ninguna entrada. Nada cambia, ni este mes ni los pasados.
        let history = BudgetHistory()
        let now = Self.at(11, 16)
        #expect(terms(history, month: now, current: 8_000, now: now) == BudgetTerms(budget: 8_000, startDay: 1))
        #expect(terms(history, month: Self.at(10, 5), current: 8_000, now: now) == BudgetTerms(budget: 8_000))
        #expect(terms(history, month: Self.at(3, 5, year: 2025), current: 8_000, now: now) == BudgetTerms(budget: 8_000))
        #expect(history.settled(current: 8_000, on: now, calendar: Self.calendar).entries.isEmpty)
        #expect(history.stored == "")
    }

    @Test func noBudgetAndNoListIsNoBudgetAnywhere() {
        let now = Self.at(11, 16)
        #expect(terms(BudgetHistory(), month: now, current: nil, now: now) == BudgetTerms(budget: nil))
        #expect(terms(BudgetHistory(), month: Self.at(10, 5), current: nil, now: now) == BudgetTerms(budget: nil))
        #expect(terms(BudgetHistory(), month: now, current: 0, now: now) == BudgetTerms(budget: nil))
    }

    // MARK: Meses pasados (H3)

    @Test func theFirstChangeKeepsWhatItWasForTheMonthsBefore() {
        // Tenía $8,000 desde siempre; el 14 de noviembre lo sube a $10,000.
        let history = record(BudgetHistory(), 10_000, previous: 8_000, on: Self.at(11, 14))
        #expect(history.entries.count == 2)
        #expect(history.entries.first?.since == nil)
        let now = Self.at(11, 20)
        // Octubre y septiembre siguen juzgándose con $8,000 (antes: con $10,000).
        #expect(terms(history, month: Self.at(10, 9), current: 10_000, now: now) == BudgetTerms(budget: 8_000))
        #expect(terms(history, month: Self.at(9, 9), current: 10_000, now: now) == BudgetTerms(budget: 8_000))
        // Noviembre: el vigente, y cuenta desde el 1 (cambiar el monto no reinicia).
        #expect(terms(history, month: now, current: 10_000, now: now) == BudgetTerms(budget: 10_000, startDay: 1))
    }

    @Test func aClosedMonthKeepsTheBudgetItClosedWith() {
        // $8,000 desde siempre; $10,000 el 14 nov; $12,000 el 3 ene.
        var history = record(BudgetHistory(), 10_000, previous: 8_000, on: Self.at(11, 14))
        history = record(history, 12_000, previous: 10_000, on: Self.at(1, 3, year: 2027))
        let now = Self.at(2, 10, year: 2027)
        #expect(terms(history, month: Self.at(10, 1), current: 12_000, now: now).budget == 8_000)
        // Noviembre cerró con $10,000 aunque empezó con $8,000.
        #expect(terms(history, month: Self.at(11, 30), current: 12_000, now: now).budget == 10_000)
        #expect(terms(history, month: Self.at(12, 31), current: 12_000, now: now).budget == 10_000)
        #expect(terms(history, month: Self.at(1, 1, year: 2027), current: 12_000, now: now).budget == 12_000)
        #expect(terms(history, month: now, current: 12_000, now: now) == BudgetTerms(budget: 12_000, startDay: 1))
    }

    @Test func aChangeOnTheLastSecondCountsForThatMonthAndOneOnTheFirstForTheNext() {
        let lastOfOctober = Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 59, second: 59))!
        let late = record(BudgetHistory(), 9_000, previous: 8_000, on: lastOfOctober)
        let now = Self.at(12, 5)
        #expect(terms(late, month: Self.at(10, 5), current: 9_000, now: now).budget == 9_000)
        let early = record(BudgetHistory(), 9_000, previous: 8_000, on: Self.at(11, 1, hour: 0))
        #expect(terms(early, month: Self.at(10, 5), current: 9_000, now: now).budget == 8_000)
        #expect(terms(early, month: Self.at(11, 5), current: 9_000, now: now).budget == 9_000)
    }

    @Test func aMonthBeforeTheFirstEntryUsesTheOldestKnown() {
        // Nunca tuvo presupuesto; lo fija el 14 nov en $8,000 y en diciembre lo sube.
        var history = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(11, 14))
        history = record(history, 9_000, previous: 8_000, on: Self.at(12, 2))
        #expect(history.entries.count == 2)
        let now = Self.at(12, 20)
        #expect(terms(history, month: Self.at(10, 5), current: 9_000, now: now).budget == 8_000)
        #expect(terms(history, month: Self.at(11, 5), current: 9_000, now: now).budget == 8_000)
    }

    @Test func aMonthThatClosedWithoutABudgetHasNone() {
        // $8,000 desde siempre; lo quita el 20 oct; lo vuelve a poner el 14 nov.
        var history = record(BudgetHistory(), nil, previous: 8_000, on: Self.at(10, 20))
        history = record(history, 9_000, previous: nil, on: Self.at(11, 14))
        let now = Self.at(12, 3)
        #expect(terms(history, month: Self.at(9, 5), current: 9_000, now: now).budget == 8_000)
        #expect(terms(history, month: Self.at(10, 5), current: 9_000, now: now).budget == nil)
        #expect(terms(history, month: Self.at(11, 5), current: 9_000, now: now).budget == 9_000)
    }

    @Test func aClosedMonthKeepsItsBudgetAfterTodaysIsTakenOff() {
        let history = record(BudgetHistory(), nil, previous: 8_000, on: Self.at(11, 14))
        let now = Self.at(11, 20)
        #expect(terms(history, month: Self.at(10, 5), current: nil, now: now).budget == 8_000)
        #expect(terms(history, month: now, current: nil, now: now) == BudgetTerms(budget: nil))
    }

    // MARK: Desde qué día cuenta este mes (H2)

    @Test func aBudgetFirstSetMidMonthCountsFromThatDay() {
        let history = record(BudgetHistory(), 30_000, previous: nil, on: Self.at(11, 14, hour: 18))
        #expect(terms(history, month: Self.at(11, 14, hour: 18), current: 30_000, now: Self.at(11, 14, hour: 18))
                == BudgetTerms(budget: 30_000, startDay: 14))
        #expect(terms(history, month: Self.at(11, 25), current: 30_000, now: Self.at(11, 25))
                == BudgetTerms(budget: 30_000, startDay: 14))
        // El mes siguiente lo tiene desde su día 1; noviembre, ya cerrado, se juzga completo.
        #expect(terms(history, month: Self.at(12, 2), current: 30_000, now: Self.at(12, 2))
                == BudgetTerms(budget: 30_000, startDay: 1))
        #expect(terms(history, month: Self.at(11, 25), current: 30_000, now: Self.at(12, 2))
                == BudgetTerms(budget: 30_000, startDay: 1))
    }

    @Test func aScreenThatLookedAtTheClockBeforeTheChangeStillSeesIt() {
        // La pantalla guarda su «ahora» de cuando abrió (12:00); el presupuesto se fija a las
        // 12:05. Leído con las 12:00, el cambio no es «del futuro»: antes se descartaba y la
        // pantalla contaba desde el día 1 hasta que su reloj se refrescara.
        let history = record(BudgetHistory(), 30_000, previous: nil, on: Self.at(11, 20, hour: 12, minute: 5))
        let stale = Self.at(11, 20, hour: 12)
        #expect(terms(history, month: stale, current: 30_000, now: stale) == BudgetTerms(budget: 30_000, startDay: 20))
        #expect(history.settled(current: 30_000, on: stale, calendar: Self.calendar) == history)
        // Y un cambio de monto más tarde ese día, leído con la hora vieja, tampoco lo reinicia.
        let changed = record(history, 24_000, previous: 30_000, on: Self.at(11, 20, hour: 18))
        #expect(terms(changed, month: stale, current: 24_000, now: stale) == BudgetTerms(budget: 24_000, startDay: 20))
        // Aun con un «ahora» de ayer (pasó la medianoche sin refrescar): no se pierde.
        let yesterday = Self.at(11, 19, hour: 23)
        #expect(terms(history, month: yesterday, current: 30_000, now: yesterday) == BudgetTerms(budget: 30_000, startDay: 20))
    }

    @Test func setOnTheFirstCountsTheWholeMonth() {
        let late = record(BudgetHistory(), 30_000, previous: nil, on: Self.at(11, 1, hour: 23, minute: 59))
        #expect(terms(late, month: Self.at(11, 9), current: 30_000, now: Self.at(11, 9)).startDay == 1)
        let second = record(BudgetHistory(), 30_000, previous: nil, on: Self.at(11, 2, hour: 0))
        #expect(terms(second, month: Self.at(11, 9), current: 30_000, now: Self.at(11, 9)).startDay == 2)
    }

    @Test func changingTheAmountMidMonthDoesNotRestart() {
        var history = record(BudgetHistory(), 30_000, previous: nil, on: Self.at(11, 14))
        history = record(history, 24_000, previous: 30_000, on: Self.at(11, 20))
        #expect(terms(history, month: Self.at(11, 22), current: 24_000, now: Self.at(11, 22))
                == BudgetTerms(budget: 24_000, startDay: 14))
    }

    @Test func takingItOffAndSettingItAgainTheSameMonthDoesNotRestart() {
        // Lo tenía el día 1: quitarlo el 10 y volver a ponerlo el 20 no borra lo que llevaba.
        var history = record(BudgetHistory(), nil, previous: 8_000, on: Self.at(11, 10))
        history = record(history, 8_000, previous: nil, on: Self.at(11, 20))
        #expect(terms(history, month: Self.at(11, 22), current: 8_000, now: Self.at(11, 22))
                == BudgetTerms(budget: 8_000, startDay: 1))
        // Lo fijó por primera vez el 14, lo quitó el 18 y lo volvió a poner el 22: sigue el 14.
        var late = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(11, 14))
        late = record(late, nil, previous: 8_000, on: Self.at(11, 18))
        #expect(terms(late, month: Self.at(11, 19), current: nil, now: Self.at(11, 19)) == BudgetTerms(budget: nil))
        late = record(late, 9_000, previous: nil, on: Self.at(11, 22))
        #expect(terms(late, month: Self.at(11, 23), current: 9_000, now: Self.at(11, 23))
                == BudgetTerms(budget: 9_000, startDay: 14))
    }

    @Test func takenOffAMonthBeforeAndSetAgainCountsFromThatDay() {
        var history = record(BudgetHistory(), nil, previous: 8_000, on: Self.at(10, 20))
        history = record(history, 8_000, previous: nil, on: Self.at(11, 14))
        #expect(terms(history, month: Self.at(11, 15), current: 8_000, now: Self.at(11, 15))
                == BudgetTerms(budget: 8_000, startDay: 14))
    }

    @Test func shortAndLongMonthsAndTheTurnOfTheYear() {
        // Último día de un mes de 28, de 31 y de diciembre.
        let february = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(2, 28, year: 2027))
        #expect(terms(february, month: Self.at(2, 28, year: 2027), current: 8_000, now: Self.at(2, 28, year: 2027, hour: 20)).startDay == 28)
        #expect(terms(february, month: Self.at(3, 1, year: 2027), current: 8_000, now: Self.at(3, 1, year: 2027)).startDay == 1)
        let october = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(10, 31))
        #expect(terms(october, month: Self.at(10, 31), current: 8_000, now: Self.at(10, 31, hour: 22)).startDay == 31)
        let december = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(12, 20))
        #expect(terms(december, month: Self.at(12, 31), current: 8_000, now: Self.at(12, 31)).startDay == 20)
        let january = Self.at(1, 5, year: 2027)
        #expect(terms(december, month: january, current: 8_000, now: january) == BudgetTerms(budget: 8_000, startDay: 1))
        #expect(terms(december, month: Self.at(12, 5), current: 8_000, now: january) == BudgetTerms(budget: 8_000))
        // Un año después, el mismo mes no hereda el día.
        #expect(terms(december, month: Self.at(12, 25, year: 2027), current: 8_000, now: Self.at(12, 25, year: 2027)).startDay == 1)
    }

    @Test func theDayIsTheCalendarsDay() {
        // Fijado el 14 nov a las 23:30 de México: en Madrid ya era el 15.
        let history = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(11, 14, hour: 23, minute: 30))
        let now = Self.at(11, 20)
        #expect(terms(history, month: now, current: 8_000, now: now).startDay == 14)
        #expect(terms(history, month: now, current: 8_000, now: now, calendar: Self.madrid).startDay == 15)
        // Fijado el 31 oct a las 23:30 de México: en Madrid es 1 nov, así que noviembre lo tuvo
        // desde su día 1 en los dos calendarios y octubre solo existe con él en México.
        let edge = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(10, 31, hour: 23, minute: 30))
        #expect(terms(edge, month: now, current: 8_000, now: now).startDay == 1)
        #expect(terms(edge, month: now, current: 8_000, now: now, calendar: Self.madrid).startDay == 1)
    }

    // MARK: Escribir los cambios

    @Test func severalChangesTheSameDayLeaveTheLast() {
        var history = record(BudgetHistory(), 9_000, previous: 8_000, on: Self.at(11, 14, hour: 9))
        history = record(history, 9_500, previous: 9_000, on: Self.at(11, 14, hour: 10))
        history = record(history, 10_000, previous: 9_500, on: Self.at(11, 14, hour: 22))
        #expect(history.entries.map(\.value) == [8_000, 10_000])
        // Volver a lo que era al empezar el día no deja rastro.
        history = record(history, 8_000, previous: 10_000, on: Self.at(11, 14, hour: 23))
        #expect(history.entries.map(\.value) == [8_000])
        #expect(terms(history, month: Self.at(10, 3), current: 8_000, now: Self.at(11, 15)).budget == 8_000)
    }

    @Test func setAndTakenOffTheSameDayLeavesNothing() {
        var history = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(11, 14, hour: 9))
        history = record(history, nil, previous: 8_000, on: Self.at(11, 14, hour: 10))
        #expect(history.entries.isEmpty)
        #expect(history.stored == "")
        // Y fijarlo de nuevo otro día cuenta desde ese día.
        history = record(history, 8_000, previous: nil, on: Self.at(11, 20))
        #expect(terms(history, month: Self.at(11, 21), current: 8_000, now: Self.at(11, 21)).startDay == 20)
    }

    @Test func savingTheSameBudgetWritesNothing() {
        let history = record(BudgetHistory(), 9_000, previous: 8_000, on: Self.at(11, 14))
        #expect(record(history, 9_000, previous: 9_000, on: Self.at(11, 20)) == history)
        // Llamado dos veces por el mismo cambio (la hoja y luego el aviso de los ajustes).
        #expect(record(history, 9_000, previous: 8_000, on: Self.at(11, 14, hour: 13)) == history)
        #expect(record(BudgetHistory(), 8_000, previous: 8_000, on: Self.at(11, 14)).entries.isEmpty)
        #expect(record(BudgetHistory(), nil, previous: nil, on: Self.at(11, 14)).entries.isEmpty)
    }

    @Test func aChangeNobodyWroteDownIsDatedWhenItIsNoticed() {
        // Otra versión cambió la cifra: el historial dice $8,000 y la cifra vigente, $9,500.
        let history = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(10, 3))
        let now = Self.at(11, 16)
        let settled = history.settled(current: 9_500, on: now, calendar: Self.calendar)
        #expect(settled.entries.map(\.value) == [8_000, 9_500])
        #expect(settled.entries.last?.date == now)
        // Sin guardarlo aún, la lectura ya responde igual.
        #expect(terms(history, month: now, current: 9_500, now: now) == BudgetTerms(budget: 9_500, startDay: 1))
        #expect(terms(history, month: Self.at(10, 9), current: 9_500, now: now).budget == 8_000)
        // Quitado en octubre y vuelto a poner sin que nadie lo anotara: cuenta desde que se nota.
        let removed = record(history, nil, previous: 8_000, on: Self.at(10, 20))
        #expect(terms(removed, month: now, current: 9_500, now: now) == BudgetTerms(budget: 9_500, startDay: 16))
    }

    @Test func anEntryFromTheFutureIsDropped() {
        // El reloj estuvo adelantado: una entrada de diciembre vista en noviembre.
        let ahead = record(BudgetHistory(), 9_000, previous: 8_000, on: Self.at(12, 20))
        let now = Self.at(11, 16)
        let back = record(ahead, 10_000, previous: 9_000, on: now)
        #expect(back.entries.map(\.value) == [8_000, 10_000])
        #expect(back.entries.last?.date == now)
    }

    @Test func onlyTheNewestChangesAreKept() {
        var history = BudgetHistory()
        var previous: Decimal? = nil
        for step in 0..<(BudgetHistory.limit + 15) {
            let amount = Decimal(1_000 + step)
            let day = Self.calendar.date(byAdding: .day, value: step, to: Self.at(1, 1, year: 2025))!
            history = record(history, amount, previous: previous, on: day)
            previous = amount
        }
        #expect(history.entries.count == BudgetHistory.limit)
        #expect(history.entries.last?.value == Decimal(1_000 + BudgetHistory.limit + 14))
    }

    // MARK: Lo que llega de iCloud

    @Test func aListThatBeginsTodayDoesNotRestartABudgetThisPhoneAlreadyHad() {
        // Este iPhone: $8,000 desde siempre (sin lista). Un segundo iPhone pasó por la bienvenida
        // el 16 nov y subió «desde hoy $8,000».
        let remote = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(11, 16))
        let merged = BudgetHistory().adopting(remote, localBudget: 8_000)
        #expect(merged.entries.map(\.value) == [8_000])
        #expect(merged.entries.first?.since == nil)
        let now = Self.at(11, 20)
        #expect(terms(merged, month: now, current: 8_000, now: now) == BudgetTerms(budget: 8_000, startDay: 1))
        // Con otra cifra en el segundo iPhone: la de aquí sigue siendo la de los meses pasados.
        let other = record(BudgetHistory(), 9_000, previous: nil, on: Self.at(11, 16))
        let changed = BudgetHistory().adopting(other, localBudget: 8_000)
        #expect(changed.entries.map(\.value) == [8_000, 9_000])
        #expect(terms(changed, month: now, current: 9_000, now: now) == BudgetTerms(budget: 9_000, startDay: 1))
        #expect(terms(changed, month: Self.at(10, 5), current: 9_000, now: now).budget == 8_000)
    }

    @Test func aShorterListNeverTakesAwayWhatThisPhoneKnowsFromBefore() {
        // Aquí: $8,000 siempre, $10,000 desde el 14 oct. Llega una lista que empieza el 16 nov.
        let mine = record(BudgetHistory(), 10_000, previous: 8_000, on: Self.at(10, 14))
        let remote = record(BudgetHistory(), 12_000, previous: nil, on: Self.at(11, 16))
        let merged = mine.adopting(remote, localBudget: 10_000)
        #expect(merged.entries.map(\.value) == [8_000, 10_000, 12_000])
        #expect(merged.entries.first?.since == nil)
        // Lo de aquí posterior al inicio de la que llega no se mezcla: gana la que llega.
        let later = record(mine, 11_000, previous: 10_000, on: Self.at(11, 18))
        #expect(later.adopting(remote, localBudget: 11_000).entries.map(\.value) == [8_000, 10_000, 12_000])
    }

    @Test func aListThatSaysAlwaysOrAnEmptyOneIsTakenAsItIs() {
        let mine = record(BudgetHistory(), 10_000, previous: 8_000, on: Self.at(10, 14))
        // Otro iPhone con su propio «siempre»: el último que escribe gana, como los demás ajustes.
        let remote = record(BudgetHistory(), 9_000, previous: 7_000, on: Self.at(11, 2))
        #expect(mine.adopting(remote, localBudget: 10_000) == remote)
        // Vacía (se restauró un respaldo sin lista): se adopta vacía.
        #expect(mine.adopting(BudgetHistory(), localBudget: 10_000).entries.isEmpty)
        // Sin nada aquí (iPhone nuevo, sin presupuesto): la que llega, tal cual.
        let started = record(BudgetHistory(), 8_000, previous: nil, on: Self.at(11, 16))
        #expect(BudgetHistory().adopting(started, localBudget: nil) == started)
        // Y lo que no se pudo leer de la que llega se conserva.
        let newer = BudgetHistory(stored: #"[{"since":1794700000,"amount":"9000"},{"desde":"x"}]"#)
        #expect(mine.adopting(newer, localBudget: 10_000).stored.contains("desde"))
    }

    // MARK: Como texto

    @Test func itRoundTripsAsText() {
        var history = record(BudgetHistory(), Decimal(string: "8000.50"), previous: 7_000, on: Self.at(11, 14))
        history = record(history, nil, previous: Decimal(string: "8000.50"), on: Self.at(11, 20))
        let read = BudgetHistory(stored: history.stored)
        #expect(read == history)
        #expect(read.entries.map(\.value) == [7_000, Decimal(string: "8000.50"), nil])
        #expect(read.entries.map(\.date) == [nil, Self.at(11, 14), Self.at(11, 20)])
    }

    @Test func entriesAreReadInOrderWhateverOrderTheyWereStoredIn() {
        let stored = #"[{"since":1794700000,"amount":"9000"},{"amount":"8000"},{"since":1790000000,"amount":""}]"#
        #expect(BudgetHistory(stored: stored).entries.map(\.value) == [8_000, nil, 9_000])
    }

    @Test func whatItCannotReadIsKeptAndTheRestStillReads() {
        // Una entrada de una versión más nueva, con otra forma.
        let stored = #"[{"amount":"8000"},{"desde":"2026-11-14","monto":9000},{"since":1794700000,"amount":"9000"}]"#
        let history = BudgetHistory(stored: stored)
        #expect(history.entries.map(\.value) == [8_000, 9_000])
        let written = history.recording(10_000, previous: 9_000, on: Date(timeIntervalSince1970: 1_800_000_000),
                                        calendar: Self.calendar).stored
        #expect(written.contains("2026-11-14"))
        #expect(BudgetHistory(stored: written).entries.map(\.value) == [8_000, 9_000, 10_000])
    }

    @Test func damagedTextIsAnEmptyList() {
        for text in ["", "no es json", "{}", "[1, \"dos\"]"] {
            #expect(BudgetHistory(stored: text).entries.isEmpty)
        }
        let now = Self.at(11, 16)
        #expect(terms(BudgetHistory(stored: "no es json"), month: now, current: 8_000, now: now)
                == BudgetTerms(budget: 8_000, startDay: 1))
    }
}
