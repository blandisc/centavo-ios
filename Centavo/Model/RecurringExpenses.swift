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
        let started = try start(dueBy: now, in: context, calendar: calendar)
        let originals = try context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.repeatsMonthly == true }
        ))
        var changed = false
        // Each original gets its own id the first time, so two that look the same («Colegio»,
        // $5,000 twice) each log their copy.
        for original in originals where original.fixedID == nil {
            original.fixedID = UUID().uuidString
            changed = true
        }
        let ids = Set(originals.compactMap(\.fixedID))
        let copies = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.isRepeat == true },
                                                                sortBy: [SortDescriptor(\.date)]))
        // A copy is known by its original and its exact day. Two of the same (another device on
        // the same iCloud logged it before `repeatsThrough` synced here) leave one.
        var logged = started
        var existing = Set<String>()
        var legacy: [Expense] = []
        for copy in copies {
            guard let of = copy.fixedOf, ids.contains(of) else { legacy.append(copy); continue }
            if existing.insert(key(of, copy.date)).inserted { continue }
            context.delete(copy)
            changed = true
        }
        // Copies from before ids (or from an original whose id came from another device) are
        // matched by merchant, amount and period, each one used up by a single original.
        func period(_ date: Date, byDay: Bool) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(parts.year ?? 0)-\(parts.month ?? 0)" + (byDay ? "-\(parts.day ?? 0)" : "")
        }
        func takeLegacy(_ original: Expense, _ date: Date, byDay: Bool) -> Bool {
            let wanted = period(date, byDay: byDay)
            guard let index = legacy.firstIndex(where: {
                $0.merchant == original.merchant && $0.amount == original.amount && period($0.date, byDay: byDay) == wanted
            }) else { return false }
            legacy.remove(at: index)
            return true
        }
        for original in originals {
            guard let id = original.fixedID else { continue }
            let rule = original.rule
            let byDay = rule != .monthly
            let dates = RecurringSchedule.dates(rule: rule, anchor: original.date, day: original.repeatDay,
                                                after: original.repeatsThrough ?? original.date,
                                                through: now, calendar: calendar)
            for date in dates {
                guard !existing.contains(key(id, date)), !takeLegacy(original, date, byDay: byDay) else { continue }
                existing.insert(key(id, date))
                let copy = Expense(amount: original.amount, currencyMarker: original.currencyMarker,
                                   merchant: original.merchant, card: original.card,
                                   date: date, category: original.category)
                copy.isRepeat = true
                copy.fixedOf = id
                copy.displayName = original.displayName
                copy.categorySource = original.categorySource
                // A fixed expense that doesn't count (paid by work) doesn't count every month.
                copy.countedAmount = original.countedAmount
                copy.uncountedReason = original.uncountedReason
                context.insert(copy)
                logged += 1
            }
            // Every date up to the last one is now logged or was already there.
            if let last = dates.last { original.repeatsThrough = last }
        }
        if logged > 0 || changed { try context.save() }
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

    private static func key(_ id: String, _ date: Date) -> String { "\(id)|\(date.timeIntervalSinceReferenceDate)" }

    /// The first charge of a fixed expense, which every later copy repeats.
    static func original(from plan: FixedPlan, calendar: Calendar = .current) -> Expense {
        let expense = Expense(amount: plan.value, currencyMarker: plan.currency, merchant: plan.merchant,
                              card: plan.card, date: plan.firstDate, category: plan.category)
        expense.repeatsMonthly = true
        expense.fixedID = UUID().uuidString
        expense.repeatsThrough = plan.firstDate
        expense.repeatRule = plan.rule
        if plan.repeatRule.kind == .months {
            expense.repeatDay = calendar.component(.day, from: plan.firstDate)
        }
        return expense
    }
}
