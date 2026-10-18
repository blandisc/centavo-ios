import CentavoCore
import Foundation
import SwiftData

/// Logs this month's copy of every fixed expense whose day already came.
enum RecurringExpenses {
    /// Safe to call often (launch, coming back to the app): it only writes what is due.
    @discardableResult
    static func logDue(in context: ModelContext, now: Date = .now,
                       calendar: Calendar = .current) throws -> Int {
        let originals = try context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.repeatsMonthly == true }
        ))
        // Another device on the same iCloud may have logged this month's copy before
        // `repeatsThrough` synced here: one copy per merchant, amount and month.
        let copies = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.isRepeat == true }))
        func monthKey(_ merchant: String, _ amount: Decimal, _ date: Date) -> String {
            let month = calendar.dateComponents([.year, .month], from: date)
            return "\(merchant)|\(amount)|\(month.year ?? 0)-\(month.month ?? 0)"
        }
        var logged = 0
        var existing = Set(copies.map { monthKey($0.merchant, $0.amount, $0.date) })
        for original in originals {
            let dates = RecurringSchedule.dueDates(anchor: original.date, day: original.repeatDay,
                                                   after: original.repeatsThrough ?? original.date,
                                                   now: now, calendar: calendar)
            for date in dates {
                guard existing.insert(monthKey(original.merchant, original.amount, date)).inserted else { continue }
                let copy = Expense(amount: original.amount, currencyMarker: original.currencyMarker,
                                   merchant: original.merchant, card: original.card,
                                   date: date, category: original.category)
                copy.isRepeat = true
                context.insert(copy)
                logged += 1
            }
            if let last = dates.last { original.repeatsThrough = last }
        }
        if logged > 0 { try context.save() }
        return logged
    }
}
