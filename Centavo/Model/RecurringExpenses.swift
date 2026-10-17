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
        var logged = 0
        for original in originals {
            let dates = RecurringSchedule.dueDates(anchor: original.date,
                                                   after: original.repeatsThrough ?? original.date,
                                                   now: now, calendar: calendar)
            for date in dates {
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
