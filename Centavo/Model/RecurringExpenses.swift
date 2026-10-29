import CentavoCore
import Foundation
import SwiftData

/// Logs the copy of every fixed expense whose day already came, at whatever it repeats
/// (`RepeatRule`), and starts the fixed expenses whose first charge just arrived.
enum RecurringExpenses {
    /// Safe to call often (launch, coming back to the app): it only writes what is due.
    @discardableResult
    static func logDue(in context: ModelContext, now: Date = .now,
                       calendar: Calendar = .current) throws -> Int {
        var logged = try start(dueBy: now, in: context, calendar: calendar)
        let originals = try context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.repeatsMonthly == true }
        ))
        // Another device on the same iCloud may have logged a copy before `repeatsThrough`
        // synced here: one copy per merchant, amount and month (per day for what repeats more
        // often than monthly).
        let copies = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.isRepeat == true }))
        func key(_ merchant: String, _ amount: Decimal, _ date: Date, byDay: Bool) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let period = "\(parts.year ?? 0)-\(parts.month ?? 0)" + (byDay ? "-\(parts.day ?? 0)" : "")
            return "\(merchant)|\(amount)|\(period)"
        }
        var existing = Set(copies.flatMap { copy in
            [key(copy.merchant, copy.amount, copy.date, byDay: false),
             key(copy.merchant, copy.amount, copy.date, byDay: true)]
        })
        for original in originals {
            let rule = original.rule
            let byDay = rule != .monthly
            let dates = RecurringSchedule.dates(rule: rule, anchor: original.date, day: original.repeatDay,
                                                after: original.repeatsThrough ?? original.date,
                                                through: now, calendar: calendar)
            for date in dates {
                guard existing.insert(key(original.merchant, original.amount, date, byDay: byDay)).inserted
                else { continue }
                let copy = Expense(amount: original.amount, currencyMarker: original.currencyMarker,
                                   merchant: original.merchant, card: original.card,
                                   date: date, category: original.category)
                copy.isRepeat = true
                copy.displayName = original.displayName
                copy.categorySource = original.categorySource
                // A fixed expense that doesn't count (paid by work) doesn't count every month.
                copy.countedAmount = original.countedAmount
                copy.uncountedReason = original.uncountedReason
                context.insert(copy)
                logged += 1
            }
            if let last = dates.last { original.repeatsThrough = last }
        }
        if logged > 0 { try context.save() }
        return logged
    }

    /// The fixed expenses set up to start on a day that has now come: their first charge is
    /// logged, and from then on they repeat like any other.
    private static func start(dueBy now: Date, in context: ModelContext, calendar: Calendar) throws -> Int {
        let plans = FixedPlan.saved
        let due = plans.filter { $0.firstDate <= now }
        guard !due.isEmpty else { return 0 }
        var started = 0
        for plan in due {
            // Another phone may have started it already, and iCloud brought it here.
            let merchant = plan.merchant, first = plan.firstDate
            let already = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate {
                $0.repeatsMonthly == true && $0.merchant == merchant && $0.date == first
            }))
            guard already.isEmpty else { continue }
            context.insert(original(from: plan, calendar: calendar))
            started += 1
        }
        FixedPlan.save(plans.filter { $0.firstDate > now })
        return started
    }

    /// The first charge of a fixed expense, which every later copy repeats.
    static func original(from plan: FixedPlan, calendar: Calendar = .current) -> Expense {
        let expense = Expense(amount: plan.value, currencyMarker: plan.currency, merchant: plan.merchant,
                              card: plan.card, date: plan.firstDate, category: plan.category)
        expense.repeatsMonthly = true
        expense.repeatsThrough = plan.firstDate
        expense.repeatRule = plan.rule
        if plan.repeatRule.kind == .months {
            expense.repeatDay = calendar.component(.day, from: plan.firstDate)
        }
        return expense
    }
}
