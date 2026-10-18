import Foundation

/// When a monthly fixed expense (rent, a subscription) is due again.
///
/// The expense repeats on its own day of the month, or on the last day when the month is
/// shorter (the 31st becomes the 30th, or the 28th in February). Only days that already
/// came count: next month's rent is not spent yet.
public enum RecurringSchedule {
    /// The dates to log, oldest first: one per month after `after`'s month, up to `now`.
    ///
    /// - Parameters:
    ///   - anchor: the original expense's date; its day of the month is the one that repeats.
    ///   - after: the last month already logged (the original's own month at first).
    public static func dueDates(anchor: Date, after: Date, now: Date,
                                calendar: Calendar = .current) -> [Date] {
        let day = calendar.component(.day, from: anchor)
        let time = calendar.dateComponents([.hour, .minute], from: anchor)
        guard let start = calendar.dateInterval(of: .month, for: after)?.start,
              var month = calendar.date(byAdding: .month, value: 1, to: start) else { return [] }
        var dates: [Date] = []
        // A cap so a clock set decades ahead cannot flood the store.
        while month <= now, dates.count < 120 {
            let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
            var parts = calendar.dateComponents([.year, .month], from: month)
            parts.day = min(day, length)
            parts.hour = time.hour
            parts.minute = time.minute
            if let date = calendar.date(from: parts), date <= now { dates.append(date) }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return dates
    }

    /// Where a fixed expense set up today on `day` of the month starts: this month if that
    /// day already came, last month otherwise, so this month's copy logs itself when the day
    /// arrives and nothing is ever dated in the future.
    public static func firstDate(day: Int, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.component(.day, from: now)
        let month = day <= today ? now : (calendar.date(byAdding: .month, value: -1, to: now) ?? now)
        let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        var parts = calendar.dateComponents([.year, .month], from: month)
        parts.day = min(max(day, 1), length)
        parts.hour = 9
        return calendar.date(from: parts) ?? now
    }
}
