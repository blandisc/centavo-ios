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
        // Said, not shown: «290 Mexican pesos» in English, the screen's «$290» in Spanish.
        let today = spokenWholeMoney(pace.dailyAllowance.magnitude, isoCode: summary.primary.isoCode ?? primary)
        // What is left never promises more than it has: with the fixed ones still to come
        // above it, both are said as they are (second audit, 2026-11-02).
        let left: String
        if pace.isShortForFixed {
            let remaining = money(pace.remaining, summary.primary)
            let reserved = money(pace.reserved, summary.primary)
            left = String(localized: "Te quedan \(remaining) y faltan \(reserved) de fijos.")
        } else if pace.reserved > 0 {
            let free = money(pace.free, summary.primary)
            let setAside = money(pace.setAside, summary.primary)
            left = String(localized: "Te quedan \(free) libres (más \(setAside) apartados para fijos).")
        } else {
            let remaining = money(pace.remaining, summary.primary)
            left = String(localized: "Te quedan \(remaining) del presupuesto.")
        }
        if let excess = fixedSentence(pace, primary: primary, total: summary.primary) { return left + " " + excess }
        return left + " " + todayLine(today, isOver: pace.isOverToday)
    }

    /// «Te pasaste del presupuesto por $231.»: whole and rounded up, the same figure as the
    /// screen and the widgets (independent review: Siri said «$0.40» where they said «$1»).
    static func overspentSentence(_ pace: BudgetPace, primary: String, total: MoneyTotal) -> String {
        let figure = spokenWholeMoney(pace.overspentShown, isoCode: total.isoCode ?? primary)
        return String(localized: "Te pasaste del presupuesto por \(figure).")
    }

    /// «Tus fijos pasan el presupuesto por $3,000.»: the fixed expenses take the whole budget,
    /// so there is no figure for today and nothing to say «te pasaste» about (second audit).
    static func fixedSentence(_ pace: BudgetPace, primary: String, total: MoneyTotal) -> String? {
        guard let excess = pace.fixedOverBudgetShown else { return nil }
        guard excess > 0 else { return String(localized: "Tus fijos se llevan todo el presupuesto.") }
        let figure = spokenWholeMoney(excess, isoCode: total.isoCode ?? primary)
        return String(localized: "Tus fijos pasan el presupuesto por \(figure).")
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
            return String(localized: "Aún no tienes presupuesto. Fíjalo en Al día para saber cuánto puedes gastar cada día.")
        }
        if pace.isOverspent { return overspentSentence(pace, primary: primary, total: summary.primary) }
        if let excess = fixedSentence(pace, primary: primary, total: summary.primary) { return excess }
        // Said, not shown: «290 Mexican pesos» in English, the screen's «$290» in Spanish.
        let today = spokenWholeMoney(pace.dailyAllowance.magnitude, isoCode: summary.primary.isoCode ?? primary)
        return todayLine(today, isOver: pace.isOverToday)
    }

    /// «Hoy puedes gastar $290.» or «Hoy ya te pasaste por $120.», with `today` already written.
    private static func todayLine(_ today: String, isOver: Bool) -> String {
        if isOver { return String(localized: "Hoy ya te pasaste por \(today).") }
        return String(localized: "Hoy puedes gastar \(today).")
    }

    /// "Llevas $2,366.00 este mes, más USD 24.99 en otra moneda. Te quedan $5,634.00 del presupuesto. Hoy…"
    static func totalSentence(in context: ModelContext, budget: Decimal?, now: Date = AppClock.now,
                              primary: String = primaryCurrency) throws -> String {
        let summary = try summarize(in: context, now: now, primary: primary)
        let spent = money(summary.primary.amount, summary.primary)
        var sentence: String
        if summary.others.isEmpty {
            sentence = String(localized: "Llevas \(spent) este mes.")
        } else {
            let others = summary.others
                .map { otherMoney($0.amount, isoCode: $0.isoCode, label: $0.label) }
                .formatted(.list(type: .and))
            if summary.others.count > 1 {
                sentence = String(localized: "Llevas \(spent) este mes, más \(others) en otras monedas.")
            } else {
                sentence = String(localized: "Llevas \(spent) este mes, más \(others) en otra moneda.")
            }
        }
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
        // Said in the iPhone's language («Groceries»), it is the one stored in Spanish, and it
        // is said back in that language (2026-11-18).
        let stored = CategoryStyle.stored(category)
        let wanted = UserCatalog.fold(stored)
        let match = summary.categories.first { $0.category.map(UserCatalog.fold) == wanted }
        guard let match, match.amount != 0, let name = match.category else {
            let said = CategoryStyle.shown(stored)
            return String(localized: "Este mes no llevas nada en \(said).")
        }
        let spent = money(match.amount, summary.primary)
        let shownName = CategoryStyle.shown(name)
        return String(localized: "Llevas \(spent) en \(shownName) este mes.")
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

    /// Money in another currency, as Siri says it: in Spanish «USD 24.99», as always; in English
    /// by its name, «24.99 US dollars» (2026-11-19: Siri read the code letter by letter).
    static func otherMoney(_ amount: Decimal, isoCode: String?, label: String,
                           asWritten: Bool = saysMoneyAsWritten) -> String {
        guard !asWritten, let isoCode else { return "\(label) \(plainAmount(amount))" }
        return amount.formatted(spokenStyle(isoCode))
    }

    /// Every figure here is said (Siri, the notice after a payment, VoiceOver): `spokenMoney`,
    /// the screen's own in Spanish (2026-11-19).
    private static func money(_ amount: Decimal, _ total: MoneyTotal) -> String {
        spokenMoney(amount, isoCode: total.isoCode, label: total.label)
    }
}
