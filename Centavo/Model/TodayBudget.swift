import CentavoCore
import Foundation

/// The one place that turns the expenses into a `BudgetPace`, so the screen, the bar, the
/// budget sheet, Siri and the widgets all say the same «Hoy puedes gastar».
enum TodayBudget {
    /// `rows` may hold any months: only `month`'s count. `originals` are the fixed expenses'
    /// first charges (`repeatsMonthly`), whatever their month, to know what is still to come.
    /// A month that is over is measured at its last second: all of the budget was due.
    static func pace(budget: Decimal?, rows: [Expense], originals: [Expense], plans: [FixedPlan],
                     primary: String, month: Date, now: Date = .now) -> BudgetPace? {
        guard let budget else { return nil }
        let isCurrent = MonthNavigator.isSameMonth(month, as: now)
        let all = rows.map(\.amountLine)
        let fixed = rows.filter(\.isFixed).map(\.amountLine)
        let spent = MonthSummarizer.summarize(all, inMonthOf: month, primary: primary).primary.amount
        let fixedSpent = MonthSummarizer.summarize(fixed, inMonthOf: month, primary: primary).primary.amount
        let spentToday = isCurrent ? MonthSummarizer.dayTotal(all, onDayOf: now, primary: primary) : 0
        let fixedToday = isCurrent ? MonthSummarizer.dayTotal(fixed, onDayOf: now, primary: primary) : 0
        // The fixed expenses still to come come off the month's daily amount, like the charged ones.
        let reserved = isCurrent ? FixedOutlook.reserved(originals: originals, plans: plans,
                                                         primary: primary, now: now) : 0
        return BudgetPace(budget: budget, spent: spent, spentToday: spentToday, fixedSpent: fixedSpent,
                          fixedToday: fixedToday, reserved: reserved,
                          on: isCurrent ? now : MonthNavigator.closingMoment(of: month))
    }
}

extension Expense {
    /// As the month's sums see it.
    var amountLine: ExpenseAmount {
        ExpenseAmount(value: amount, currencyMarker: currencyMarker, date: date, category: category)
    }
}
