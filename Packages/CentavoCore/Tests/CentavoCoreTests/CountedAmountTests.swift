import Foundation
import Testing
@testable import CentavoCore

/// «No cuenta»: an expense that stays in the list with its real amount but adds up to nothing.
@Suite struct CountedAmountTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func day(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// As the app builds it from an expense (`Expense.asAmount`): what counts, and what doesn't.
    private func amount(_ value: Decimal, counted: Decimal? = nil, day: Int = 10, marker: String = "$",
                        category: String? = nil) -> ExpenseAmount {
        ExpenseAmount(value: CountedAmount.effective(amount: value, counted: counted), currencyMarker: marker,
                      date: Self.day(day), category: category,
                      excluded: CountedAmount.excluded(amount: value, counted: counted))
    }

    private func summarize(_ amounts: [ExpenseAmount]) -> MonthSummary {
        MonthSummarizer.summarize(amounts, inMonthOf: Self.day(15), primary: "MXN", calendar: Self.calendar)
    }

    // MARK: The amount that counts

    @Test func nothingSaidCountsAllOfIt() {
        #expect(CountedAmount.effective(amount: 230, counted: nil) == 230)
        #expect(CountedAmount.effective(amount: -230, counted: nil) == -230)
        #expect(CountedAmount.excluded(amount: 230, counted: nil) == 0)
        #expect(!CountedAmount.isUncounted(nil))
    }

    @Test func zeroCountsNothing() {
        #expect(CountedAmount.effective(amount: 230, counted: 0) == 0)
        #expect(CountedAmount.excluded(amount: 230, counted: 0) == 230)
        #expect(CountedAmount.isUncounted(0))
    }

    @Test func aShareKeepsTheAmountsSign() {
        #expect(CountedAmount.effective(amount: 1000, counted: 500) == 500)
        // A refund's share is money back too; the sign stored doesn't matter.
        #expect(CountedAmount.effective(amount: -1000, counted: 500) == -500)
        #expect(CountedAmount.effective(amount: -1000, counted: -500) == -500)
        #expect(CountedAmount.effective(amount: 1000, counted: -500) == 500)
        #expect(CountedAmount.excluded(amount: -1000, counted: 500) == -500)
        #expect(!CountedAmount.isUncounted(500))
    }

    @Test func neverCountsMoreThanTheAmount() {
        // The amount was edited down after the share was set.
        #expect(CountedAmount.effective(amount: 300, counted: 500) == 300)
        #expect(CountedAmount.effective(amount: -300, counted: 500) == -300)
        #expect(CountedAmount.excluded(amount: 300, counted: 500) == 0)
    }

    @Test func reasonsReadByTheirStableValueOrTheirTitle() {
        #expect(UncountedReason(text: "reembolso") == .reimbursed)
        #expect(UncountedReason(text: " ME LO REEMBOLSAN ") == .reimbursed)
        #expect(UncountedReason(text: "entre-cuentas") == .betweenAccounts)
        #expect(UncountedReason(text: "Entre mis cuentas") == .betweenAccounts)
        #expect(UncountedReason(text: "otro") == .other)
        #expect(UncountedReason(text: "del trabajo") == nil)
        #expect(UncountedReason(text: nil) == nil)
        // What is stored never changes, whatever the screen calls it.
        #expect(UncountedReason.allCases.map(\.rawValue) == ["reembolso", "entre-cuentas", "otro"])
    }

    // MARK: The month

    @Test func theMonthLeavesItOutButSaysHowMuchWasLeftOut() {
        let summary = summarize([
            amount(500, category: "Despensa"),
            amount(230, counted: 0, category: "Transporte"),
            amount(1000, counted: 0),
        ])
        #expect(summary.primary.amount == 500)
        #expect(summary.outside == 1230)
        #expect(summary.categories.map(\.category) == ["Despensa"])
    }

    @Test func whatIsLeftOutInAnotherCurrencyStaysOutOfItsTotalAndOfOutside() {
        let summary = summarize([amount(20, counted: 0, marker: "USD"), amount(5, marker: "USD")])
        #expect(summary.others.first?.amount == 5)
        #expect(summary.outside == 0)
    }

    @Test func aMonthWithNothingLeftOutHasNothingOutside() {
        #expect(summarize([amount(500), amount(-100)]).outside == 0)
    }

    @Test func aShareAddsUpItsPart() {
        let summary = summarize([amount(1000, counted: 500, category: "Comida")])
        #expect(summary.primary.amount == 500)
        #expect(summary.outside == 500)
        #expect(summary.categories.first?.amount == 500)
    }

    @Test func markingTodaysExpenseRaisesWhatCanGoTodayByItsAmount() throws {
        let before = summarize([amount(2000), amount(310)])
        let after = summarize([amount(2000), amount(310, counted: 0)])
        let paceBefore = try #require(BudgetPace(budget: 8000, spent: before.primary.amount,
                                                 on: Self.day(15), calendar: Self.calendar))
        let paceAfter = try #require(BudgetPace(budget: 8000, spent: after.primary.amount,
                                                on: Self.day(15), calendar: Self.calendar))
        #expect(paceAfter.remaining - paceBefore.remaining == 310)
        // 17 days left, today included: (8000 − 2000) / 17 = 352.94 against (8000 − 2310) / 17 = 334.70.
        #expect(paceBefore.dailyAllowance == 334)
        #expect(paceAfter.dailyAllowance == 352)
    }

    @Test func whereItGoesHasNoRefundLineWhenTheTripIsLeftOutInsteadOfCompensated() {
        // The old trick: the trip and its own refund, which left «Transporte» at zero.
        let compensated = CategoryShare.top(summarize([
            amount(500, category: "Despensa"), amount(230, category: "Transporte"),
            amount(-230, category: "Transporte"),
        ]).categories)
        let leftOut = CategoryShare.top(summarize([
            amount(500, category: "Despensa"), amount(230, counted: 0, category: "Transporte"),
        ]).categories)
        #expect(leftOut.map(\.category) == ["Despensa"])
        #expect(leftOut.map(\.share) == [1])
        #expect(leftOut == compensated)
    }

    @Test func aDayWithOnlyWhatDoesNotCountIsEmptyInTheCalendar() {
        let month = MonthCalendar.make([amount(230, counted: 0, day: 5), amount(100, day: 6)],
                                       inMonthOf: Self.day(1), primary: "MXN", today: Self.day(12),
                                       calendar: Self.calendar)
        let days = month.cells.compactMap { cell -> MonthCalendar.Day? in
            if case .day(let day) = cell { return day }
            return nil
        }
        #expect(days.first { $0.number == 5 }?.state == .empty)
        #expect(days.first { $0.number == 6 }?.state == .spent(level: 3))
    }

    // MARK: The month's note

    private func money(_ value: Decimal) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
    }

    private func facts(_ records: [SpendingRecord], budget: Decimal? = nil) -> [SpendingFact] {
        SpendingFacts.detect(records, now: Self.day(19), primary: "MXN", budget: budget, money: money,
                             calendar: Self.calendar)
    }

    @Test func aDoubleChargeIsStillFoundWhenItDoesNotCount() throws {
        let fact = try #require(facts([
            SpendingRecord(amount: 650, currencyMarker: "$", merchant: "Uber", date: Self.day(18, hour: 9),
                           counted: 0),
            SpendingRecord(amount: 650, currencyMarker: "$", merchant: "Uber",
                           date: Self.day(18, hour: 9).addingTimeInterval(600), counted: 0),
        ]).first)
        #expect(fact.kind == .doubleCharge)
        #expect(fact.line.contains("$650.00"))
    }

    @Test func theProjectionLeavesOutWhatDoesNotCount() {
        // 12,500 by the 19th ends the month near 20,400, over 15,000; without the 12,000 trip, near 800.
        let records = [
            SpendingRecord(amount: 500, currencyMarker: "$", merchant: "Varios", date: Self.day(10)),
            SpendingRecord(amount: 12_000, currencyMarker: "$", merchant: "Vuelo", date: Self.day(10), counted: 0),
        ]
        #expect(!facts(records, budget: 15_000).contains { $0.kind == .projection })
        let counted = records.map { SpendingRecord(amount: $0.amount, currencyMarker: $0.currencyMarker,
                                                   merchant: $0.merchant, date: $0.date) }
        #expect(facts(counted, budget: 15_000).contains { $0.kind == .projection })
    }
}
