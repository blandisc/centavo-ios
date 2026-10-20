import CentavoCore
import Foundation

/// A fixed expense whose first charge has not come yet: «$500 cada lunes, desde el lunes 26».
///
/// Nothing in the store has a future date, so until that day it lives here, in the same synced
/// settings as the budget (`BudgetSync`), and is set apart from «Hoy puedes gastar» like any
/// other fixed expense. On its day `RecurringExpenses.logDue` turns it into the real first
/// charge, which then repeats like every fixed expense.
struct FixedPlan: Codable, Hashable, Identifiable {
    var id = UUID()
    var merchant: String
    /// Kept as text so the cents stay exact, like the budget.
    var amount: String
    /// The ISO code it was set up in.
    var currency: String
    var category: String?
    var rule: String?
    var firstDate: Date

    var value: Decimal { Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    var repeatRule: RepeatRule { RepeatRule(stored: rule) }

    static let key = "fijosPorEmpezar"

    static func decode(_ stored: String) -> [FixedPlan] {
        guard let data = stored.data(using: .utf8),
              let list = try? JSONDecoder().decode([FixedPlan].self, from: data) else { return [] }
        return list
    }

    static func encode(_ list: [FixedPlan]) -> String {
        guard let data = try? JSONEncoder().encode(list) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static var saved: [FixedPlan] { decode(UserDefaults.standard.string(forKey: key) ?? "") }

    static func save(_ list: [FixedPlan]) {
        let text = encode(list)
        UserDefaults.standard.set(text, forKey: key)
        if Store.syncsBudget { BudgetSync.push(text, for: key) }
    }
}

/// One line of «Gastos fijos»: a fixed expense already running, or one about to start.
struct FixedItem: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
    let currency: String
    let ruleText: String
    /// The next charge, if any comes within a year.
    let next: Date?
    /// Charges still to come this month: what is set apart.
    let coming: [Date]
    /// The fixed expense's first charge, to edit or stop it; `nil` for one not started yet.
    let original: Expense?
    let plan: FixedPlan?
}

/// What the fixed expenses add up to, for the budget and for «Gastos fijos».
enum FixedOutlook {
    static func items(originals: [Expense], plans: [FixedPlan], now: Date = .now,
                      calendar: Calendar = .current) -> [FixedItem] {
        let running = originals.filter { $0.repeatsMonthly == true }.map { original in
            let rule = original.rule
            let after = original.repeatsThrough ?? original.date
            return FixedItem(
                id: String(describing: original.persistentModelID),
                name: original.shownName,
                amount: original.amount,
                currency: original.currencyMarker ?? CurrencyPreference.current,
                ruleText: rule.describe(anchor: original.date, day: original.repeatDay, calendar: calendar),
                next: RecurringSchedule.next(rule: rule, anchor: original.date, day: original.repeatDay,
                                             after: after, now: now, calendar: calendar),
                coming: RecurringSchedule.comingThisMonth(rule: rule, anchor: original.date,
                                                          day: original.repeatDay, after: after,
                                                          now: now, calendar: calendar),
                original: original, plan: nil
            )
        }
        let starting = plans.map { plan in
            let rule = plan.repeatRule
            return FixedItem(
                id: plan.id.uuidString,
                name: MerchantName.readable(plan.merchant) ?? plan.merchant,
                amount: plan.value,
                currency: plan.currency,
                ruleText: rule.describe(anchor: plan.firstDate, calendar: calendar),
                next: plan.firstDate > now ? plan.firstDate
                    : RecurringSchedule.next(rule: rule, anchor: plan.firstDate, after: plan.firstDate,
                                             now: now, calendar: calendar),
                coming: comingThisMonth(of: plan, now: now, calendar: calendar),
                original: nil, plan: plan
            )
        }
        return (running + starting).sorted { ($0.next ?? .distantFuture) < ($1.next ?? .distantFuture) }
    }

    /// What is set apart from «Hoy puedes gastar»: the main currency's charges still to come
    /// this month. Other currencies are not added to it, as everywhere else.
    static func reserved(originals: [Expense], plans: [FixedPlan], primary: String, now: Date = .now,
                         calendar: Calendar = .current) -> Decimal {
        items(originals: originals, plans: plans, now: now, calendar: calendar)
            .filter { CurrencyResolver.isoCode(for: $0.currency, primary: primary) == primary }
            .reduce(Decimal(0)) { $0 + $1.amount * Decimal($1.coming.count) }
    }

    /// Its first charge is a charge too: the one that comes first.
    private static func comingThisMonth(of plan: FixedPlan, now: Date, calendar: Calendar) -> [Date] {
        guard let end = calendar.dateInterval(of: .month, for: now)?.end else { return [] }
        let first = calendar.isDate(plan.firstDate, equalTo: now, toGranularity: .month) && plan.firstDate > now
            ? [plan.firstDate] : []
        return first + RecurringSchedule.dates(rule: plan.repeatRule, anchor: plan.firstDate,
                                               after: plan.firstDate, through: end.addingTimeInterval(-1),
                                               calendar: calendar).filter { $0 > now }
    }
}
