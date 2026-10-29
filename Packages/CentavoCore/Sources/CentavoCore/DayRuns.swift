import Foundation

/// Splits a list into runs of the same day, in the order it comes: the list's day dividers.
///
/// One pass that adds to the run being built, instead of copying a day's array on every item
/// (that made a day of n items cost n², and the whole history was split on every redraw).
public enum DayRuns {
    public struct Run<Item> {
        public let day: Date
        public let items: [Item]
    }

    /// A day that shows up again after another one starts a new run, as the list draws it.
    public static func split<Item>(_ items: [Item], calendar: Calendar = .current,
                                   date: (Item) -> Date) -> [Run<Item>] {
        var runs: [Run<Item>] = []
        var day: Date?
        var current: [Item] = []
        for item in items {
            let start = calendar.startOfDay(for: date(item))
            if start != day {
                if let day, !current.isEmpty { runs.append(Run(day: day, items: current)) }
                day = start
                current = []
            }
            current.append(item)
        }
        if let day, !current.isEmpty { runs.append(Run(day: day, items: current)) }
        return runs
    }
}
