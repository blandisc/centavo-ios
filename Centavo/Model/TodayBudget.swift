import CentavoCore
import Foundation

/// The one place that turns the expenses into a `BudgetPace`, so the screen, the bar, the
/// budget sheet, Siri and the widgets all say the same «Hoy puedes gastar».
enum TodayBudget {
    /// `month`'s sums as the widgets keep them. `rows` may hold any months: only `month`'s
    /// count. `originals` are the fixed expenses' first charges (`repeatsMonthly`), whatever
    /// their month, to know what is still to come. A month that is over is taken at its last
    /// second: all of the budget was due.
    static func snapshot(budget: Decimal?, rows: [Expense], originals: [Expense], plans: [FixedPlan],
                         primary: String, month: Date, now: Date = .now) -> WidgetSnapshot {
        let isCurrent = MonthNavigator.isSameMonth(month, as: now)
        let all = rows.map(\.amountLine)
        let fixed = rows.filter(\.isFixed).map(\.amountLine)
        let summary = MonthSummarizer.summarize(all, inMonthOf: month, primary: primary)
        let fixedSpent = MonthSummarizer.summarize(fixed, inMonthOf: month, primary: primary).primary.amount
        // The fixed expenses still to come come off the month's daily amount, like the charged ones.
        let reserved = isCurrent ? FixedOutlook.reserved(originals: originals, plans: plans,
                                                         primary: primary, now: now) : 0
        return WidgetSnapshot(
            budget: budget, isoCode: summary.primary.isoCode, label: summary.primary.label,
            takenAt: isCurrent ? now : MonthNavigator.closingMoment(of: month),
            spent: summary.primary.amount,
            spentToday: isCurrent ? MonthSummarizer.dayTotal(all, onDayOf: now, primary: primary) : 0,
            fixedSpent: fixedSpent,
            fixedToday: isCurrent ? MonthSummarizer.dayTotal(fixed, onDayOf: now, primary: primary) : 0,
            reserved: reserved, slices: WidgetSnapshot.slices(summary.categories))
    }

    static func pace(budget: Decimal?, rows: [Expense], originals: [Expense], plans: [FixedPlan],
                     primary: String, month: Date, now: Date = .now) -> BudgetPace? {
        guard budget != nil else { return nil }
        let snapshot = snapshot(budget: budget, rows: rows, originals: originals, plans: plans,
                                primary: primary, month: month, now: now)
        return snapshot.pace(at: snapshot.takenAt)
    }
}

extension Expense {
    /// As the month's sums see it.
    var amountLine: ExpenseAmount {
        ExpenseAmount(value: amount, currencyMarker: currencyMarker, date: date, category: category)
    }
}
