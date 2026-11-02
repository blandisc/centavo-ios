import CentavoCore
import Foundation
import SwiftData

/// This month in a sentence or two, for the places with no screen: the notice Atajos shows
/// after a payment, and Siri. Lives apart from the intents so it can be tested.
enum MonthStatus {
    /// The currency the month is added up in (see `CurrencyPreference`).
    static var primaryCurrency: String { CurrencyPreference.current }

    /// The saved budget, if there is one.
    static var savedBudget: Decimal? {
        BudgetStore.amount(from: UserDefaults.standard.string(forKey: BudgetStore.key) ?? "")
    }

    /// "Te quedan $1,000.00 libres (más $5,000.00 apartados para fijos). Hoy puedes gastar $100."
    /// or "Te pasaste del presupuesto por $230.00." The same figures as the screen: what is
    /// left once the fixed expenses still to come are set apart, and today's «Hoy puedes gastar».
    /// `nil` with no budget: nothing to measure against.
    static func budgetSentence(in context: ModelContext, budget: Decimal?, now: Date = AppClock.now,
                               primary: String = primaryCurrency) throws -> String? {
        let rows = try monthRows(in: context, now: now)
        let summary = MonthSummarizer.summarize(rows.map(\.asAmount), inMonthOf: now, primary: primary)
        let originals = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.repeatsMonthly == true }))
        guard let pace = TodayBudget.pace(budget: budget, rows: rows, originals: originals, plans: FixedPlan.saved,
                                          primary: primary, month: now, now: now) else {
            return nil
        }
        if pace.isOverspent { return overspentSentence(pace, primary: primary, total: summary.primary) }
        // Fixed expenses past the budget and already charged: what's left is below zero, but
        // nothing was overspent; that's all there is to say.
        if pace.remaining < 0, let excess = fixedSentence(pace, primary: primary, total: summary.primary) { return excess }
        let today = pace.dailyAllowance.magnitude.formatted(currencyStyle(summary.primary.isoCode ?? primary)
                                                             .precision(.fractionLength(0)))
        // What is left never promises more than it has: with the fixed ones still to come
        // above it, both are said as they are (second audit, 2026-11-02).
        let left: String
        if pace.isShortForFixed {
            left = "Te quedan \(money(pace.remaining, summary.primary)) y faltan "
                + "\(money(pace.reserved, summary.primary)) de fijos."
        } else if pace.reserved > 0 {
            left = "Te quedan \(money(pace.free, summary.primary)) libres "
                + "(más \(money(pace.setAside, summary.primary)) apartados para fijos)."
        } else {
            left = "Te quedan \(money(pace.remaining, summary.primary)) del presupuesto."
        }
        if let excess = fixedSentence(pace, primary: primary, total: summary.primary) { return left + " " + excess }
        return left + (pace.isOverToday ? " Hoy ya te pasaste por \(today)." : " Hoy puedes gastar \(today).")
    }

    /// «Te pasaste del presupuesto por $231.»: whole and rounded up, the same figure as the
    /// screen and the widgets (independent review: Siri said «$0.40» where they said «$1»).
    static func overspentSentence(_ pace: BudgetPace, primary: String, total: MoneyTotal) -> String {
        let figure = pace.overspentShown.formatted(currencyStyle(total.isoCode ?? primary).precision(.fractionLength(0)))
        return "Te pasaste del presupuesto por \(figure)."
    }

    /// «Tus fijos pasan el presupuesto por $3,000.»: the fixed expenses take the whole budget,
    /// so there is no figure for today and nothing to say «te pasaste» about (second audit).
    static func fixedSentence(_ pace: BudgetPace, primary: String, total: MoneyTotal) -> String? {
        guard let excess = pace.fixedOverBudgetShown else { return nil }
        guard excess > 0 else { return "Tus fijos se llevan todo el presupuesto." }
        let figure = excess.formatted(currencyStyle(total.isoCode ?? primary).precision(.fractionLength(0)))
        return "Tus fijos pasan el presupuesto por \(figure)."
    }

    /// «¿Cuánto puedo gastar hoy?»: "Hoy puedes gastar $290." The screen's big figure, out loud,
    /// with nothing else; "Hoy ya te pasaste por $120." or "Te pasaste del presupuesto por
    /// $230.00." past it, and how to get there with no budget.
    static func todaySentence(in context: ModelContext, budget: Decimal?, now: Date = AppClock.now,
                              primary: String = primaryCurrency) throws -> String {
        let rows = try monthRows(in: context, now: now)
        let summary = MonthSummarizer.summarize(rows.map(\.asAmount), inMonthOf: now, primary: primary)
        let originals = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.repeatsMonthly == true }))
        guard let pace = TodayBudget.pace(budget: budget, rows: rows, originals: originals, plans: FixedPlan.saved,
                                          primary: primary, month: now, now: now) else {
            return "Aún no tienes presupuesto. Fíjalo en Al día para saber cuánto puedes gastar cada día."
        }
        if pace.isOverspent { return overspentSentence(pace, primary: primary, total: summary.primary) }
        if let excess = fixedSentence(pace, primary: primary, total: summary.primary) { return excess }
        let today = pace.dailyAllowance.magnitude.formatted(currencyStyle(summary.primary.isoCode ?? primary)
                                                             .precision(.fractionLength(0)))
        return pace.isOverToday ? "Hoy ya te pasaste por \(today)." : "Hoy puedes gastar \(today)."
    }

    /// "Llevas $2,366.00 este mes, más USD 24.99 en otra moneda. Te quedan $5,634.00 del presupuesto. Hoy…"
    static func totalSentence(in context: ModelContext, budget: Decimal?, now: Date = AppClock.now,
                              primary: String = primaryCurrency) throws -> String {
        let summary = try summarize(in: context, now: now, primary: primary)
        var sentence = "Llevas \(money(summary.primary.amount, summary.primary)) este mes"
        if !summary.others.isEmpty {
            let others = summary.others
                .map { "\($0.label) \($0.amount.formatted(.number.precision(.fractionLength(2))))" }
                .formatted(.list(type: .and))
            sentence += ", más \(others) en \(summary.others.count > 1 ? "otras monedas" : "otra moneda")"
        }
        sentence += "."
        if let budgetLine = try budgetSentence(in: context, budget: budget, now: now, primary: primary) {
            sentence += " " + budgetLine
        }
        return sentence
    }

    /// "Llevas $1,240.00 en Café este mes." The category's share of the month's total, in the
    /// main currency like everything else on the screen.
    static func categorySentence(_ category: String, in context: ModelContext, now: Date = AppClock.now,
                                 primary: String = primaryCurrency) throws -> String {
        let summary = try summarize(in: context, now: now, primary: primary)
        let wanted = UserCatalog.fold(category)
        let match = summary.categories.first { $0.category.map(UserCatalog.fold) == wanted }
        guard let match, match.amount != 0, let name = match.category else {
            return "Este mes no llevas nada en \(category)."
        }
        return "Llevas \(money(match.amount, summary.primary)) en \(name) este mes."
    }

    private static func summarize(in context: ModelContext, now: Date,
                                  primary: String) throws -> MonthSummary {
        MonthSummarizer.summarize(try monthAmounts(in: context, now: now), inMonthOf: now, primary: primary)
    }

    private static func monthAmounts(in context: ModelContext, now: Date) throws -> [ExpenseAmount] {
        try monthRows(in: context, now: now).map(\.asAmount)
    }

    private static func monthRows(in context: ModelContext, now: Date) throws -> [Expense] {
        // Only this month's rows: the notice runs at every payment and should stay quick.
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: now, duration: 0)
        let start = interval.start, end = interval.end
        return try context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))
    }

    private static func money(_ amount: Decimal, _ total: MoneyTotal) -> String {
        formatMoney(amount, isoCode: total.isoCode, label: total.label)
    }
}
