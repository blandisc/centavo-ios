import CentavoCore
import Foundation

/// The one place that turns the expenses into a `BudgetPace`, so the screen, the bar, the
/// budget sheet, Siri and the widgets all say the same «Hoy puedes gastar».
enum TodayBudget {
    /// `month`'s sums as the widgets keep them. `rows` may hold any months: only `month`'s
    /// count. `originals` are the fixed expenses' first charges (`repeatsMonthly`), whatever
    /// their month, to know what is still to come. A month that is over is taken at its last
    /// second: all of the budget was due. `mode` is the rule chosen in the budget sheet.
    static func snapshot(budget: Decimal?, rows: [Expense], originals: [Expense], plans: [FixedPlan],
                         primary: String, month: Date, now: Date = .now,
                         mode: AllowanceMode = .saved) -> WidgetSnapshot {
        let isCurrent = MonthNavigator.isSameMonth(month, as: now)
        // What counts (`Expense.asAmount`): «no cuenta» stays out of today, the month and the widgets.
        let all = rows.map(\.asAmount)
        let fixed = rows.filter(\.isFixed).map(\.asAmount)
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
            reserved: reserved, slices: WidgetSnapshot.slices(summary.categories), mode: mode)
    }

    static func pace(budget: Decimal?, rows: [Expense], originals: [Expense], plans: [FixedPlan],
                     primary: String, month: Date, now: Date = .now,
                     mode: AllowanceMode = .saved) -> BudgetPace? {
        guard budget != nil else { return nil }
        let snapshot = snapshot(budget: budget, rows: rows, originals: originals, plans: plans,
                                primary: primary, month: month, now: now, mode: mode)
        return snapshot.pace(at: snapshot.takenAt)
    }
}

extension AllowanceMode {
    /// The choice saved in the budget sheet; «Acumular día a día» until one is made.
    static var saved: AllowanceMode { AllowanceMode(stored: UserDefaults.standard.string(forKey: key)) }

    var title: String {
        switch self {
        case .carry: "Acumular día a día"
        case .spread: "Repartir entre los días que quedan"
        }
    }

    var explanation: String {
        switch self {
        case .carry: "Lo que te sobra o te pasas hoy se suma o se resta completo mañana."
        case .spread: "Lo que queda del mes se divide parejo entre los días que faltan."
        }
    }
}

