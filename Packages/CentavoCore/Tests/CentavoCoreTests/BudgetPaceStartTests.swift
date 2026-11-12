import Foundation
import Testing
@testable import CentavoCore

/// Un presupuesto fijado a mitad de mes (2026-11-11): «Hoy puedes gastar» cuenta desde ese día.
/// Noviembre de 2026 tiene 30 días: $30,000 son $1,000 al día.
@Suite struct BudgetPaceStartTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, month: Int = 11, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func pace(budget: Decimal = 30_000, spent: Decimal, spentToday: Decimal = 0, fixedSpent: Decimal = 0,
                      fixedToday: Decimal = 0, reserved: Decimal = 0, mode: AllowanceMode = .carry,
                      startDay: Int, before: Decimal, on date: Date) throws -> BudgetPace {
        try #require(BudgetPace(budget: budget, spent: spent, spentToday: spentToday, fixedSpent: fixedSpent,
                                fixedToday: fixedToday, reserved: reserved, mode: mode, startDay: startDay,
                                variableBeforeStart: before, on: date, calendar: Self.calendar))
    }

    // MARK: El hueco (H2)

    @Test func theDaysBeforeTheBudgetAreNotMoneyLeftOver() throws {
        // Fija $30,000 el 16 de noviembre; del 1 al 15 llevaba $2,000.
        // Antes: 16 días × $1,000 − $2,000 = «Hoy puedes gastar $14,000».
        let old = try #require(BudgetPace(budget: 30_000, spent: 2_000, on: Self.day(16), calendar: Self.calendar))
        #expect(old.dailyAllowance == 14_000)
        // Ahora: su primer día, lo de un día.
        let pace = try pace(spent: 2_000, startDay: 16, before: 2_000, on: Self.day(16))
        #expect(pace.dailyAllowance == 1_000)
        #expect(pace.dailyBase == 1_000)
        #expect(pace.carriedOver == 0)
        #expect(pace.heldBack == 0)
        #expect(pace.startDay == 16)
        #expect(pace.countedDays == 1)
        #expect(pace.countsFrom == Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 16)))
        // Lo de antes sigue contando en «Llevas» y en lo que queda.
        #expect(pace.spent == 2_000)
        #expect(pace.remaining == 28_000)
        // «Podrías llevar»: lo que ya iba más lo de hoy; la barra sigue restando a la cifra.
        #expect(pace.expectedToDate == 3_000)
        #expect(pace.expectedShown - pace.spentShown == pace.dailyAllowance)
        #expect(!pace.isAheadOfPace)
    }

    @Test func whatWentBeforeTheBudgetIsNotHeldAgainstIt() throws {
        // Del 1 al 15 llevaba $20,000. Antes: 16,000 − 20,000 = «Hoy te pasaste $4,000» el día
        // que fija el presupuesto.
        let old = try #require(BudgetPace(budget: 30_000, spent: 20_000, on: Self.day(16), calendar: Self.calendar))
        #expect(old.dailyAllowance == -4_000)
        let pace = try pace(spent: 20_000, startDay: 16, before: 20_000, on: Self.day(16))
        #expect(pace.dailyAllowance == 1_000)
        #expect(!pace.isOverToday)
        #expect(pace.carriedOver == 0)
        #expect(pace.remaining == 10_000)
        #expect(!pace.isAheadOfPace)
    }

    @Test func fromThatDayOnItCarriesLikeAnyMonth() throws {
        // Fijado el 16; el 16 gasta $400 y el 17 $1,900; lo de antes, $2,000.
        let second = try pace(spent: 2_400, startDay: 16, before: 2_000, on: Self.day(17))
        #expect(second.carriedOver == 600)
        #expect(second.dailyAllowance == 1_600)
        #expect(second.countedDays == 2)
        let third = try pace(spent: 4_300, startDay: 16, before: 2_000, on: Self.day(18))
        #expect(third.carriedOver == -300)
        #expect(third.dailyAllowance == 700)
        // Gastando hoy $900: se pasa de hoy por $200.
        let over = try pace(spent: 5_200, spentToday: 900, startDay: 16, before: 2_000, on: Self.day(18))
        #expect(over.dailyAllowance == -200)
        #expect(over.isOverToday)
        #expect(over.expectedShown - over.spentShown == -200)
    }

    @Test func theLastDayGetsItsDaysNotTheWholeMonth() throws {
        // Fijado el 16, sin gastar nada desde entonces: el 30 son 15 días, $15,000 (antes $30,000).
        let pace = try pace(spent: 0, startDay: 16, before: 0, on: Self.day(30))
        #expect(pace.dailyAllowance == 15_000)
        #expect(pace.countedDays == 15)
    }

    // MARK: Nunca más de lo que queda

    @Test func todayIsNeverOfferedMoreThanWhatIsLeft() throws {
        // Llevaba $29,500 antes de fijar $30,000: quedan $500, no los $1,000 de un día.
        let pace = try pace(spent: 29_500, startDay: 16, before: 29_500, on: Self.day(16))
        #expect(pace.dailyAllowance == 500)
        #expect(pace.heldBack == 500)
        #expect(pace.expectedShown - pace.spentShown == 500)
        let sum = pace.sum
        #expect(sum.perDay == 1_000)
        #expect(sum.heldBack == 500)
        #expect(sum.perDay + sum.carriedOver - sum.heldBack - sum.variableToday == pace.dailyAllowance)
        // Al día siguiente, sin gastar: siguen quedando $500, aunque sus dos días sumen $2,000.
        let next = try self.pace(spent: 29_500, startDay: 16, before: 29_500, on: Self.day(17))
        #expect(next.dailyAllowance == 500)
        #expect(next.sum.perDay + next.sum.carriedOver - next.sum.heldBack - next.sum.variableToday == 500)
    }

    @Test func whatIsLeftSetsTheFixedExpensesStillToComeApart() throws {
        // $30,000, $6,000 de fijos por venir: $800 al día. Llevaba $23,700: quedan $300 libres.
        let pace = try pace(spent: 23_700, reserved: 6_000, startDay: 16, before: 23_700, on: Self.day(16))
        #expect(pace.dailyBase == 800)
        #expect(pace.dailyAllowance == 300)
        #expect(pace.free == 300)
        // Llevaba $25,000: lo que queda no cubre los fijos. Hoy $0, no «te pasaste».
        let short = try self.pace(spent: 25_000, reserved: 6_000, startDay: 16, before: 25_000, on: Self.day(16))
        #expect(short.dailyAllowance == 0)
        #expect(!short.isOverToday)
        #expect(short.isShortForFixed)
        // Y si hoy gasta $200, sí: se pasó de hoy.
        let spentToday = try self.pace(spent: 25_200, spentToday: 200, reserved: 6_000, startDay: 16, before: 25_000,
                                       on: Self.day(16))
        #expect(spentToday.dailyAllowance == -200)
    }

    @Test func pastTheBudgetIsStillPastTheBudget() throws {
        // Llevaba $31,000 antes de fijar $30,000: «Te pasaste $1,000», como siempre.
        let pace = try pace(spent: 31_000, startDay: 16, before: 31_000, on: Self.day(16))
        #expect(pace.isOverspent)
        #expect(pace.overspentShown == 1_000)
        #expect(pace.dailyAllowance == 0)
    }

    // MARK: Fijos

    @Test func fixedExpensesComeOffTheMonthWheneverTheyWereCharged() throws {
        // $30,000; $3,000 de fijos cobrados el día 5 y $3,000 por venir: $800 al día.
        // Fuera de fijos llevaba $1,000 antes del 16.
        let first = try pace(spent: 4_000, fixedSpent: 3_000, reserved: 3_000, startDay: 16, before: 1_000, on: Self.day(16))
        #expect(first.dailyBase == 800)
        #expect(first.dailyAllowance == 800)
        #expect(first.expectedToDate == 4_800)
        // El 18 cobran los $3,000 que faltaban: no le quitan nada a hoy.
        let charged = try pace(spent: 7_000, spentToday: 3_000, fixedSpent: 6_000, fixedToday: 3_000, startDay: 16,
                               before: 1_000, on: Self.day(18))
        #expect(charged.dailyBase == 800)
        #expect(charged.dailyAllowance == 2_400)
    }

    @Test func fixedExpensesPastTheBudgetStayTheirOwnState() throws {
        let pace = try pace(budget: 10_000, spent: 500, reserved: 13_000, startDay: 16, before: 500, on: Self.day(16))
        #expect(pace.fixedOverBudget == 3_000)
        #expect(pace.dailyAllowance == 0)
        #expect(!pace.isOverToday)
    }

    // MARK: «Se reparte»

    @Test func spreadGivesTheSameWithOrWithoutAStartDay() throws {
        // Ya reparte lo que queda entre los días que faltan: la cifra no cambia.
        for (spent, today) in [(Decimal(2_000), Decimal(0)), (20_000, 0), (2_300, 300), (29_500, 0)] {
            let whole = try #require(BudgetPace(budget: 30_000, spent: spent, spentToday: today, reserved: 3_000,
                                                mode: .spread, on: Self.day(16), calendar: Self.calendar))
            let started = try pace(spent: spent, spentToday: today, reserved: 3_000, mode: .spread, startDay: 16,
                                   before: spent - today, on: Self.day(16))
            #expect(started.dailyAllowance == whole.dailyAllowance)
            #expect(started.dailyBase == whole.dailyBase)
            #expect(started.todayShare == whole.todayShare)
            #expect(started.sum.forToday == whole.sum.forToday)
        }
    }

    @Test func spreadsRhythmDoesNotCountTheDaysBeforeEither() throws {
        // Antes: «Vas $14,000 abajo del ritmo» el día que fija el presupuesto.
        let whole = try #require(BudgetPace(budget: 30_000, spent: 2_000, mode: .spread, on: Self.day(16),
                                            calendar: Self.calendar))
        #expect(whole.rhythm == 14_000)
        let started = try pace(spent: 2_000, mode: .spread, startDay: 16, before: 2_000, on: Self.day(16))
        #expect(started.rhythm == 1_000)
        #expect(started.expectedToDate == 3_000)
    }

    // MARK: Lo que no cambia

    @Test func countingFromTheFirstIsTheSameAsBefore() throws {
        for mode in AllowanceMode.allCases {
            for day in [1, 2, 16, 30] {
                let before = try #require(BudgetPace(budget: 30_000, spent: 9_876.54, spentToday: 321.09,
                                                     fixedSpent: 4_000, fixedToday: 100, reserved: 2_500, mode: mode,
                                                     on: Self.day(day), calendar: Self.calendar))
                // Lo de «antes del día 1» no existe: se ignora aunque llegue.
                let now = try pace(spent: 9_876.54, spentToday: 321.09, fixedSpent: 4_000, fixedToday: 100,
                                   reserved: 2_500, mode: mode, startDay: 1, before: 777, on: Self.day(day))
                #expect(now == before)
                #expect(now.sum == before.sum)
                #expect(now.countsFrom == nil)
                #expect(now.heldBack == 0)
                #expect(now.countedDays == day)
            }
        }
    }

    @Test func aStartDayAfterTodayBeginsToday() throws {
        // El reloj se movió hacia atrás: «desde el 20» visto el 16 empieza hoy, sin nada antes.
        let pace = try pace(spent: 2_300, spentToday: 300, startDay: 20, before: 0, on: Self.day(16))
        #expect(pace.startDay == 16)
        #expect(pace.dailyAllowance == 700)
        #expect(pace.carriedOver == 0)
        let zero = try self.pace(spent: 0, startDay: 0, before: 0, on: Self.day(16))
        #expect(zero.startDay == 1)
        #expect(zero.dailyAllowance == 16_000)
    }

    // MARK: La cuenta

    @Test func theSumAddsUpToThePeso() throws {
        // $8,000 en noviembre: $266.66… al día. Fijado el 14; el 14 gastó $100.40 y hoy $50.25.
        let first = try pace(budget: 8_000, spent: 1_300.40, spentToday: 100.40, startDay: 14, before: 1_200, on: Self.day(14))
        // El primer día no hay «Sobró»: el peso suelto va a «Por día».
        #expect(first.sum.carriedOver == 0)
        #expect(first.sum.perDay - first.sum.variableToday == first.dailyAllowance)
        let second = try pace(budget: 8_000, spent: 1_350.65, spentToday: 50.25, startDay: 14, before: 1_200, on: Self.day(15))
        let sum = second.sum
        #expect(sum.perDay == 267)
        #expect(sum.heldBack == 0)
        #expect(sum.perDay + sum.carriedOver - sum.variableToday == second.dailyAllowance)
        #expect(second.dailyAllowance == 382)
        #expect(sum.budget - sum.spent == sum.remaining)
    }

    // MARK: Meses de 28 y 31 días, fin de año

    @Test func shortAndLongMonths() throws {
        // Febrero de 2027, 28 días: $28,000 son $1,000 al día. Fijado el último día.
        let february = try pace(budget: 28_000, spent: 5_000, startDay: 28, before: 5_000, on: Self.day(28, month: 2, year: 2027))
        #expect(february.dailyAllowance == 1_000)
        #expect(february.daysLeft == 1)
        // Diciembre, 31 días: $31,000. Fijado el 30; el 31, sin gastar, dos días.
        let december = try pace(budget: 31_000, spent: 9_000, startDay: 30, before: 9_000, on: Self.day(31, month: 12))
        #expect(december.dailyAllowance == 2_000)
        #expect(december.countsFrom == Self.calendar.date(from: DateComponents(year: 2026, month: 12, day: 30)))
    }
}
