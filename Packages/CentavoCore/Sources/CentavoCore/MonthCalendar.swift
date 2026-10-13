import Foundation

/// One month laid out as a calendar grid, each day tagged with how heavily it was spent.
public struct MonthCalendar: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            /// Hasn't happened yet.
            case future
            /// Nothing spent (or spending and refunds cancelled out).
            case empty
            /// Spent, from 1 (a little) to 3 (the month's heaviest stretch).
            case spent(level: Int)
            /// More came back than went out.
            case refund
        }

        public let number: Int
        public let state: State
        public let isToday: Bool
        /// Net spend in the primary currency; negative on a refund day.
        public let total: Decimal
    }

    public enum Cell: Equatable, Sendable {
        /// An empty slot before the 1st, so the grid lines up with the weekdays.
        case padding
        case day(Day)
    }

    /// One-letter weekday headers, starting on the calendar's first weekday.
    public let weekdaySymbols: [String]
    public let cells: [Cell]

    /// Builds the month of `reference`.
    ///
    /// Only the primary currency is drawn, for the same reason the month total is: a
    /// euro and a peso are not the same heat. Intensity is relative to the heaviest day
    /// of the month, so the picture reads the same whether you spend 500 or 50,000.
    public static func make(
        _ amounts: [ExpenseAmount],
        inMonthOf reference: Date,
        primary: String,
        today: Date,
        calendar: Calendar = .current
    ) -> MonthCalendar {
        let symbols = Self.symbols(for: calendar)
        guard let interval = calendar.dateInterval(of: .month, for: reference),
              let dayCount = calendar.range(of: .day, in: .month, for: reference)?.count
        else { return MonthCalendar(weekdaySymbols: symbols, cells: []) }

        let primaryCode = CurrencyResolver.isoCode(for: primary, primary: primary) ?? primary
        var totals: [Int: Decimal] = [:]
        for amount in amounts
        where calendar.isDate(amount.date, equalTo: reference, toGranularity: .month) {
            guard CurrencyResolver.isoCode(for: amount.currencyMarker, primary: primaryCode)
                    == primaryCode else { continue }
            totals[calendar.component(.day, from: amount.date), default: 0] += amount.value
        }

        let heaviest = totals.values.filter { $0 > 0 }.max() ?? 0
        let startOfToday = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var cells = [Cell](repeating: .padding, count: leading)
        for number in 1...dayCount {
            let start = calendar.date(byAdding: .day, value: number - 1, to: interval.start)
                ?? interval.start
            let total = totals[number] ?? 0
            let state: Day.State
            if start > startOfToday {
                state = .future
            } else if total < 0 {
                state = .refund
            } else if total == 0 {
                state = .empty
            } else {
                state = .spent(level: level(of: total, heaviest: heaviest))
            }
            cells.append(.day(Day(number: number, state: state,
                                  isToday: calendar.isDate(start, inSameDayAs: today),
                                  total: total)))
        }
        return MonthCalendar(weekdaySymbols: symbols, cells: cells)
    }

    private static func level(of total: Decimal, heaviest: Decimal) -> Int {
        if total * 3 >= heaviest * 2 { return 3 }
        if total * 3 >= heaviest { return 2 }
        return 1
    }

    private static func symbols(for calendar: Calendar) -> [String] {
        let all = calendar.veryShortStandaloneWeekdaySymbols
        guard all.count == 7 else { return all }
        let first = calendar.firstWeekday - 1
        return (0..<7).map { all[(first + $0) % 7] }
    }
}
