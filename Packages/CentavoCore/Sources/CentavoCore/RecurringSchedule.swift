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
    ///   - day: the day asked for, when it differs from the anchor's: a fixed expense on the
    ///     31st that started in a 30-day month is still on the 31st where the month has one.
    ///   - after: the last month already logged (the original's own month at first).
    public static func dueDates(anchor: Date, day: Int? = nil, after: Date, now: Date,
                                calendar: Calendar = .current) -> [Date] {
        let day = day ?? calendar.component(.day, from: anchor)
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

    /// The last charge of `rule` that already came by `through`: the anchor itself if none
    /// since. An expense marked as fixed after the fact repeats from here, so a charge already
    /// lived isn't logged again, and this month's still to come is (2026-11-02, second audit:
    /// Netflix of Oct 25 marked on Nov 10 skipped Nov 25 when it started from Nov 10).
    public static func lastCharge(rule: RepeatRule, anchor: Date, day: Int? = nil, through: Date,
                                  calendar: Calendar = .current) -> Date {
        guard through > anchor else { return anchor }
        return dates(rule: rule, anchor: anchor, day: day, after: anchor, through: through, calendar: calendar).last
            ?? anchor
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
        // Today before 9:00 would be a moment that has not come yet.
        return min(calendar.date(from: parts) ?? now, now)
    }
}
