import Foundation

/// Browsing the months: which ones exist, and what "the end of that month" means.
public enum MonthNavigator {
    /// A date inside the month `offset` months from `now` (0 = this month, -1 = last).
    /// Only its month and year mean anything; the day is whatever `now`'s day lands on.
    public static func month(offsetBy offset: Int, from now: Date,
                             calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: offset, to: now) ?? now
    }

    /// How far back you can go: as many months as lie between the oldest expense and now.
    /// Never positive, and 0 when there is nothing older than this month.
    public static func earliestOffset(oldest: Date?, now: Date,
                                      calendar: Calendar = .current) -> Int {
        guard let oldest,
              let from = calendar.dateInterval(of: .month, for: oldest)?.start,
              let to = calendar.dateInterval(of: .month, for: now)?.start,
              let months = calendar.dateComponents([.month], from: from, to: to).month
        else { return 0 }
        return -max(months, 0)
    }

    /// The last second of the month `date` falls in. A budget measured at that moment has
    /// the whole month behind it: the full budget "should" have been spent by then.
    public static func closingMoment(of date: Date, calendar: Calendar = .current) -> Date {
        guard let end = calendar.dateInterval(of: .month, for: date)?.end else { return date }
        return end.addingTimeInterval(-1)
    }

    /// Whether `date` is in the same month as `reference`.
    public static func isSameMonth(_ date: Date, as reference: Date,
                                   calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: reference, toGranularity: .month)
    }
}
