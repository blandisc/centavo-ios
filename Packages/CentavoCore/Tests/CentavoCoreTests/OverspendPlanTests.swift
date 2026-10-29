import CentavoCore
import Foundation
import Testing

@Suite("Te pasaste: cómo cerrar el mes")
struct OverspendPlanTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    @Test("Sin pasarse no hay plan")
    func underBudget() {
        let pace = BudgetPace(budget: 3_100, spent: 1_000, on: day(29), calendar: calendar)!
        #expect(OverspendPlan(pace: pace) == nil)
    }

    @Test("Los tres caminos: parar, ritmo del presupuesto y ritmo actual")
    func threePaths() throws {
        // October has 31 days: $3,100 is $100 a day. Day 29, $3,480 spent, nothing fixed.
        let pace = BudgetPace(budget: 3_100, spent: 3_480, on: day(29), calendar: calendar)!
        let plan = try #require(OverspendPlan(pace: pace))
        #expect(plan.over == 380)
        #expect(plan.daysAfterToday == 2)
        #expect(plan.stop == .init(perDay: 0, closesOver: 380))
        #expect(plan.budgetRate == .init(perDay: 100, closesOver: 580))
        // $3,480 over 29 days = $120 a day.
        #expect(plan.currentRate == .init(perDay: 120, closesOver: 620))
    }

    @Test("Los fijos que faltan llegan aunque no gastes nada")
    func fixedToCome() throws {
        let pace = BudgetPace(budget: 3_100, spent: 3_200, fixedSpent: 1_000, reserved: 300,
                              on: day(30), calendar: calendar)!
        let plan = try #require(OverspendPlan(pace: pace))
        #expect(plan.fixedToCome == 300)
        #expect(plan.stop.closesOver == 400)
        // Outside fixed: $2,200 over 30 days = $73.33 → $73 a day, one day left.
        #expect(plan.currentRate.perDay == 73)
        #expect(plan.currentRate.closesOver == 473)
    }

    @Test("El último día no quedan días por repartir")
    func lastDay() throws {
        let pace = BudgetPace(budget: 3_100, spent: 3_150.40, on: day(31), calendar: calendar)!
        let plan = try #require(OverspendPlan(pace: pace))
        #expect(plan.daysAfterToday == 0)
        #expect(plan.over == 51)
        #expect(plan.budgetRate.closesOver == plan.stop.closesOver)
    }
}
