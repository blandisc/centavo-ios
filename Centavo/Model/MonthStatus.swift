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
        guard let pace = BudgetPace(budget: budget, spent: summary.primary.amount, on: now) else {
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
        let amounts = rows.map {
            ExpenseAmount(value: $0.amount, currencyMarker: $0.currencyMarker,
                          date: $0.date, category: $0.category)
        }
        return MonthSummarizer.summarize(amounts, inMonthOf: now, primary: primary)
    }

    private static func money(_ amount: Decimal, _ total: MoneyTotal) -> String {
        formatMoney(amount, isoCode: total.isoCode, label: total.label)
    }
}
