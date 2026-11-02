import Foundation
import Testing
@testable import CentavoCore

/// Revisión independiente de la segunda auditoría (2026-11-02).
@Suite struct SecondAuditReviewTests {
    private func mxn(_ value: Decimal, _ kind: MoneyKind = .account) -> MoneyLine {
        MoneyLine(kind: kind, currency: "MXN", balance: value)
    }

    @Test func anAccountClosedAndArchivedBeforeTheCutCountsAsZero() {
        // Caja pasa a Nu y se archiva antes del corte de octubre.
        let sep = MoneyChange.Cut(lines: ["nu": mxn(10_000), "caja": mxn(5_000)], main: "MXN", rates: [:])
        let oct = MoneyChange.Cut(lines: ["nu": mxn(15_000)], main: "MXN", rates: [:])
        #expect(MoneyChange.since(previous: sep, latest: oct, counting: ["nu", "caja"], closed: ["caja"]) == 0)
    }

    @Test func aDebtPaidAndArchivedBeforeTheCutCountsAsZero() {
        let sep = MoneyChange.Cut(lines: ["nu": mxn(10_000), "amex": mxn(3_000, .debt)], main: "MXN", rates: [:])
        let oct = MoneyChange.Cut(lines: ["nu": mxn(7_000)], main: "MXN", rates: [:])
        #expect(MoneyChange.since(previous: sep, latest: oct, counting: ["nu", "amex"], closed: ["amex"]) == 0)
    }

    @Test func aMissingAccountThatIsNotClosedStaysOut() {
        let sep = MoneyChange.Cut(lines: ["nu": mxn(10_000), "caja": mxn(5_000)], main: "MXN", rates: [:])
        let oct = MoneyChange.Cut(lines: ["nu": mxn(10_500)], main: "MXN", rates: [:])
        #expect(MoneyChange.since(previous: sep, latest: oct, counting: ["nu", "caja"]) == 500)
    }

    // MARK: Fijos sobre el presupuesto: «te pasaste» solo por lo variable

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private static func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    @Test func chargingTheFixedIsNotOverspending() throws {
        // $13,000 de fijos ya cobrados, presupuesto $10,000, nada variable.
        let pace = try #require(BudgetPace(budget: 10_000, spent: 13_000, fixedSpent: 13_000,
                                           on: Self.day(5), calendar: Self.calendar))
        #expect(pace.isFixedOverBudget)
        #expect(!pace.isOverspent)
        #expect(pace.fixedOverBudgetShown == 3_000)
    }

    @Test func spendingPastWhatWasLeftIsOverspending() throws {
        let pace = try #require(BudgetPace(budget: 10_000, spent: Decimal(string: "13050.40")!, fixedSpent: 13_000,
                                           on: Self.day(5), calendar: Self.calendar))
        #expect(pace.isOverspent)
        #expect(pace.overspentShown == 51)
    }

    @Test func withoutFixedOverItIsTheBudget() throws {
        let pace = try #require(BudgetPace(budget: 1_000, spent: Decimal(string: "1000.40")!,
                                           on: Self.day(5), calendar: Self.calendar))
        #expect(pace.isOverspent)
        #expect(pace.overspentShown == 1)
        let within = try #require(BudgetPace(budget: 1_000, spent: 999, on: Self.day(5), calendar: Self.calendar))
        #expect(!within.isOverspent)
    }

    // MARK: Tipo de cambio pendiente, con su mes

    @Test func aPendingRateKeepsItsMonth() {
        let text = MoneyMath.encodePending(["USD": (rate: 20, month: "2026-11")])
        let back = MoneyMath.decodePending(text)
        #expect(back["USD"]?.rate == 20 && back["USD"]?.month == "2026-11")
        #expect(MoneyMath.pendingRates(back, for: "2026-10").isEmpty, "No va a un corte de un mes anterior")
        #expect(MoneyMath.pendingRates(back, for: "2026-11") == ["USD": 20])
        #expect(MoneyMath.pendingRates(back, for: "2026-12") == ["USD": 20])
    }
}
