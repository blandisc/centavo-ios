import Foundation
import Testing
@testable import CentavoCore

/// Segunda auditoría (2026-11-02): los cálculos de «Hoy».
@Suite struct TodayMathAuditTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    // MARK: Fijos mayores que el presupuesto (#16)

    @Test func fixedOverTheBudgetIsItsOwnStateNotOverspending() throws {
        // $10,000 de presupuesto y $13,000 de fijos por venir: el día 1, sin gastar nada.
        for mode in AllowanceMode.allCases {
            let pace = try #require(BudgetPace(budget: 10_000, spent: 0, reserved: 13_000, mode: mode,
                                               on: Self.day(1), calendar: Self.calendar))
            #expect(pace.fixedOverBudget == 3_000)
            #expect(pace.isFixedOverBudget)
            #expect(!pace.isOverToday, "No dice «te pasaste» sin haber gastado")
            #expect(pace.dailyAllowance == 0)
            #expect(pace.dailyBase >= 0)
        }
    }

    @Test func fixedOverTheBudgetAgreesInBothModesAfterSpending() throws {
        let carry = try #require(BudgetPace(budget: 10_000, spent: 500, spentToday: 200, reserved: 13_000,
                                            mode: .carry, on: Self.day(5), calendar: Self.calendar))
        let spread = try #require(BudgetPace(budget: 10_000, spent: 500, spentToday: 200, reserved: 13_000,
                                             mode: .spread, on: Self.day(5), calendar: Self.calendar))
        #expect(carry.dailyAllowance == spread.dailyAllowance)
        #expect(carry.dailyBase >= 0 && spread.dailyBase >= 0)
        #expect(carry.fixedOverBudget == 3_000)
    }

    @Test func fixedJustTheBudgetIsTheStateToo() throws {
        let pace = try #require(BudgetPace(budget: 10_000, spent: 0, reserved: 10_000,
                                           on: Self.day(1), calendar: Self.calendar))
        #expect(pace.fixedOverBudget == 0)
        #expect(pace.isFixedOverBudget)
    }

    @Test func fixedUnderTheBudgetIsNotTheState() throws {
        let pace = try #require(BudgetPace(budget: 10_000, spent: 0, reserved: 9_000,
                                           on: Self.day(1), calendar: Self.calendar))
        #expect(pace.fixedOverBudget == nil)
        #expect(!pace.isFixedOverBudget)
    }

    @Test func fixedExcessWithCentsRoundsUp() throws {
        let pace = try #require(BudgetPace(budget: 10_000, spent: 0, reserved: Decimal(string: "10000.30")!,
                                           on: Self.day(1), calendar: Self.calendar))
        #expect(pace.fixedOverBudgetShown == 1)
    }

    // MARK: Siri y lo apartado (#17)

    @Test func whatIsSetAsideNeverPromisesMoreThanIsLeft() throws {
        // Quedan $4,000 y faltan $5,000 de fijos.
        let pace = try #require(BudgetPace(budget: 10_000, spent: 6_000, reserved: 5_000,
                                           on: Self.day(20), calendar: Self.calendar))
        #expect(pace.free == 0)
        #expect(pace.setAside == 4_000)
        #expect(pace.isShortForFixed)
        let enough = try #require(BudgetPace(budget: 10_000, spent: 1_000, reserved: 5_000,
                                             on: Self.day(20), calendar: Self.calendar))
        #expect(enough.setAside == 5_000)
        #expect(!enough.isShortForFixed)
    }

    // MARK: «Te pasaste $0» (#19)

    @Test func centsOverTheBudgetAreNeverZero() throws {
        let pace = try #require(BudgetPace(budget: 1_000, spent: Decimal(string: "1000.40")!,
                                           on: Self.day(20), calendar: Self.calendar))
        #expect(pace.isOverBudget)
        #expect(pace.overBudgetShown == 1)
        #expect(pace.sum.remaining == -1)
        #expect(pace.sum.budget - pace.sum.spent == pace.sum.remaining, "La cuenta cuadra")
    }

    @Test func wholeOverspendStaysAsIs() throws {
        let pace = try #require(BudgetPace(budget: 1_000, spent: 1_366, on: Self.day(20), calendar: Self.calendar))
        #expect(pace.overBudgetShown == 366)
        #expect(pace.sum.remaining == -366)
    }

    // MARK: La proyección y los fijos que faltan (#18)

    private func money(_ value: Decimal) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
    }

    @Test func theProjectionCountsTheFixedStillToCome() throws {
        // Día 10 de 31: $2,000 variables → $6,200 al mes. Con $5,000 de fijos por venir, $11,200.
        let records = [SpendingRecord(amount: 2_000, currencyMarker: "$", merchant: "Super", date: Self.day(3))]
        let without = SpendingFacts.detect(records, now: Self.day(10), primary: "MXN", budget: 10_000,
                                           money: money, calendar: Self.calendar)
        #expect(!without.contains { $0.kind == .projection })
        let with = SpendingFacts.detect(records, now: Self.day(10), primary: "MXN", budget: 10_000,
                                        reserved: 5_000, money: money, calendar: Self.calendar)
        let fact = try #require(with.first { $0.kind == .projection })
        #expect(fact.figures == ["$11,200", "$1,200"])
    }
}
