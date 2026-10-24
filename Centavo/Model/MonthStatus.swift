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

    /// "Te quedan $5,586.50 del presupuesto." or "Te pasaste del presupuesto por $230.00."
    /// `nil` with no budget: nothing to measure against.
    static func budgetSentence(in context: ModelContext, budget: Decimal?, now: Date = .now,
                               primary: String = primaryCurrency) throws -> String? {
        let summary = try summarize(in: context, now: now, primary: primary)
        // The fixed expenses still to come are set apart, as on the screen.
        let originals = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.repeatsMonthly == true }))
        let reserved = FixedOutlook.reserved(originals: originals, plans: FixedPlan.saved, primary: primary, now: now)
        guard let pace = BudgetPace(budget: budget, spent: summary.primary.amount, reserved: reserved, on: now) else {
            return nil
        }
        let left = money(pace.remaining.magnitude, summary.primary)
        if pace.remaining < 0 { return "Te pasaste del presupuesto por \(left)." }
        let perDay = pace.dailyAllowance.formatted(currencyStyle(summary.primary.isoCode ?? primary)
                                                    .precision(.fractionLength(0)))
        return "Te quedan \(left) del presupuesto: \(perDay) al día."
    }

    /// "Llevas $2,366.00 este mes, más USD 24.99 aparte. Te quedan $5,634.00 del presupuesto."
    static func totalSentence(in context: ModelContext, budget: Decimal?, now: Date = .now,
                              primary: String = primaryCurrency) throws -> String {
        let summary = try summarize(in: context, now: now, primary: primary)
        var sentence = "Llevas \(money(summary.primary.amount, summary.primary)) este mes"
        if !summary.others.isEmpty {
            let others = summary.others
                .map { "\($0.label) \($0.amount.formatted(.number.precision(.fractionLength(2))))" }
                .formatted(.list(type: .and))
            sentence += ", más \(others) aparte"
        }
        sentence += "."
        if let budgetLine = try budgetSentence(in: context, budget: budget, now: now, primary: primary) {
            sentence += " " + budgetLine
        }
        return sentence
    }

    /// "Llevas $1,240.00 en Café este mes." The category's share of the month's total, in the
    /// main currency like everything else on the screen.
    static func categorySentence(_ category: String, in context: ModelContext, now: Date = .now,
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
        // Only this month's rows: the notice runs at every payment and should stay quick.
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: now, duration: 0)
        let start = interval.start, end = interval.end
        let rows = try context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))
        // The same amounts the screen adds up (`Expense.asAmount`), so Siri never says another figure.
        return MonthSummarizer.summarize(rows.map(\.asAmount), inMonthOf: now, primary: primary)
    }

    private static func money(_ amount: Decimal, _ total: MoneyTotal) -> String {
        formatMoney(amount, isoCode: total.isoCode, label: total.label)
    }
}
