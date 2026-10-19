import Foundation

/// How often a fixed expense comes back. The day it comes on is the first charge's own:
/// «cada semana» from a Monday is every Monday, «cada mes» from the 5th is every 5th.
public enum RepeatRule: Equatable, Hashable, Sendable {
    /// Every `n` weeks, on the first charge's weekday.
    case weeks(Int)
    /// The 15th and the last day of every month, like a Mexican pay period.
    case semimonthly
    /// Every `n` months, on the first charge's day (the last one in a shorter month).
    case months(Int)

    public static let monthly = RepeatRule.months(1)

    /// The kinds offered, for a picker; `weeks` and `months` take their count apart.
    public enum Kind: String, CaseIterable, Sendable {
        case weeks, semimonthly, months
    }

    public var kind: Kind {
        switch self {
        case .weeks: .weeks
        case .semimonthly: .semimonthly
        case .months: .months
        }
    }

    /// 1 for «every», 2 for «every other»…; always 1 for the 15th-and-last.
    public var count: Int {
        switch self {
        case .weeks(let n), .months(let n): n
        case .semimonthly: 1
        }
    }

    public init(kind: Kind, count: Int) {
        let n = min(max(count, 1), 12)
        switch kind {
        case .weeks: self = .weeks(n)
        case .semimonthly: self = .semimonthly
        case .months: self = .months(n)
        }
    }

    /// As saved on the expense. Monthly is `nil`: every fixed expense from before this existed
    /// was monthly, and stays so without touching it.
    public var stored: String? {
        switch self {
        case .months(1): nil
        case .weeks(let n): "semanas:\(n)"
        case .semimonthly: "quincena"
        case .months(let n): "meses:\(n)"
        }
    }

    /// Anything unreadable is the old meaning: monthly.
    public init(stored: String?) {
        let parts = (stored ?? "").split(separator: ":").map(String.init)
        let n = parts.count == 2 ? Int(parts[1]) ?? 1 : 1
        switch parts.first {
        case "semanas": self = .weeks(min(max(n, 1), 12))
        case "quincena": self = .semimonthly
        case "meses": self = .months(min(max(n, 1), 12))
        default: self = .monthly
        }
    }

    /// «cada lunes», «cada 2 semanas, en lunes», «cada quincena (15 y último)», «cada mes, el
    /// día 5», «cada 2 meses, el día 5».
    public func describe(anchor: Date, day: Int? = nil, calendar: Calendar = .current) -> String {
        switch self {
        case .weeks(let n):
            let weekday = Self.weekdays[(calendar.component(.weekday, from: anchor) - 1) % 7]
            return n == 1 ? "cada \(weekday)" : "cada \(n) semanas, en \(weekday)"
        case .semimonthly:
            return "cada quincena (15 y último)"
        case .months(let n):
            let onDay = day ?? calendar.component(.day, from: anchor)
            return n == 1 ? "cada mes, el día \(onDay)" : "cada \(n) meses, el día \(onDay)"
        }
    }

    static let weekdays = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
}

extension RecurringSchedule {
    /// The charges of `rule` after `after` and no later than `through`, oldest first.
    ///
    /// Monthly keeps exactly the behavior it always had (`dueDates`). The others count from
    /// the first charge (`anchor`) and keep its time of day.
    public static func dates(rule: RepeatRule, anchor: Date, day: Int? = nil, after: Date,
                             through: Date, calendar: Calendar = .current) -> [Date] {
        switch rule {
        case .months(1):
            return dueDates(anchor: anchor, day: day, after: after, now: through, calendar: calendar)
        case .months(let n):
            return everyFewMonths(n, anchor: anchor, day: day, after: after, through: through, calendar: calendar)
        case .weeks(let n):
            return everyFewWeeks(n, anchor: anchor, after: after, through: through, calendar: calendar)
        case .semimonthly:
            return semimonthly(anchor: anchor, after: after, through: through, calendar: calendar)
        }
    }

    /// A cap so a clock set decades ahead cannot flood the store.
    static let maxDates = 120

    private static func everyFewWeeks(_ n: Int, anchor: Date, after: Date, through: Date,
                                      calendar: Calendar) -> [Date] {
        let period = 7 * n
        // Skip straight to around `after` instead of walking from the first charge.
        let elapsed = calendar.dateComponents([.day], from: anchor, to: after).day ?? 0
        var step = max(0, elapsed / period - 1)
        var dates: [Date] = []
        while dates.count < maxDates, let date = calendar.date(byAdding: .day, value: step * period, to: anchor) {
            if date > through { break }
            if date > after { dates.append(date) }
            step += 1
        }
        return dates
    }

    private static func everyFewMonths(_ n: Int, anchor: Date, day: Int?, after: Date, through: Date,
                                       calendar: Calendar) -> [Date] {
        let day = day ?? calendar.component(.day, from: anchor)
        let time = calendar.dateComponents([.hour, .minute], from: anchor)
        guard let start = calendar.dateInterval(of: .month, for: anchor)?.start else { return [] }
        let elapsed = calendar.dateComponents([.month], from: start, to: after).month ?? 0
        var step = max(0, elapsed / n - 1)
        var dates: [Date] = []
        while dates.count < maxDates, let month = calendar.date(byAdding: .month, value: step * n, to: start) {
            let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
            var parts = calendar.dateComponents([.year, .month], from: month)
            parts.day = min(day, length)
            parts.hour = time.hour
            parts.minute = time.minute
            guard let date = calendar.date(from: parts) else { break }
            if date > through { break }
            if date > after { dates.append(date) }
            step += 1
        }
        return dates
    }

    private static func semimonthly(anchor: Date, after: Date, through: Date, calendar: Calendar) -> [Date] {
        let time = calendar.dateComponents([.hour, .minute], from: anchor)
        guard var month = calendar.dateInterval(of: .month, for: max(after, anchor))?.start else { return [] }
        var dates: [Date] = []
        while dates.count < maxDates, month <= through {
            let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
            for day in [15, length] {
                var parts = calendar.dateComponents([.year, .month], from: month)
                parts.day = day
                parts.hour = time.hour
                parts.minute = time.minute
                if let date = calendar.date(from: parts), date > after, date > anchor, date <= through {
                    dates.append(date)
                }
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return dates
    }
}

extension RecurringSchedule {
    /// The charges still to come this month, after `now`: what «Hoy puedes gastar» sets apart.
    /// Built from the same `dates` the copies are logged by, so what is set apart is exactly
    /// what will arrive.
    public static func comingThisMonth(rule: RepeatRule, anchor: Date, day: Int? = nil, after: Date,
                                       now: Date, calendar: Calendar = .current) -> [Date] {
        guard let end = calendar.dateInterval(of: .month, for: now)?.end else { return [] }
        return dates(rule: rule, anchor: anchor, day: day, after: after,
                     through: end.addingTimeInterval(-1), calendar: calendar).filter { $0 > now }
    }

    /// The next charge after `now`, for «próximo: lun 26 oct».
    public static func next(rule: RepeatRule, anchor: Date, day: Int? = nil, after: Date,
                            now: Date, calendar: Calendar = .current) -> Date? {
        guard let horizon = calendar.date(byAdding: .month, value: 13, to: now) else { return nil }
        return dates(rule: rule, anchor: anchor, day: day, after: max(after, now), through: horizon,
                     calendar: calendar).first
    }
}
