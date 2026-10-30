import Foundation

/// The month as the barcode under the budget bar draws it (owner's choice, 2026-10-29): one
/// bar per day, as tall as what went that day, and the figures printed under it.
///
/// The app hands each day's sums in the month's currency; this decides what each bar means
/// (a day of fixed charges, a day past the daily limit, today, one still to come) and the
/// figures: how many payments, the average a day and the limit a day.
public struct MonthCode: Equatable, Sendable {
    /// One day as the app adds it up.
    public struct DayInput: Equatable, Sendable {
        public var total: Decimal
        /// What went that day that is not a fixed charge: what the daily limit is measured by.
        public var variable: Decimal
        public var payments: Int
        public var fixedPayments: Int
        /// The biggest payment's name and amount, for the day's card.
        public var biggest: (name: String, amount: Decimal)?

        public init(total: Decimal = 0, variable: Decimal = 0, payments: Int = 0, fixedPayments: Int = 0,
                    biggest: (name: String, amount: Decimal)? = nil) {
            self.total = total
            self.variable = variable
            self.payments = payments
            self.fixedPayments = fixedPayments
            self.biggest = biggest
        }

        public static func == (lhs: DayInput, rhs: DayInput) -> Bool {
            lhs.total == rhs.total && lhs.variable == rhs.variable && lhs.payments == rhs.payments
                && lhs.fixedPayments == rhs.fixedPayments && lhs.biggest?.name == rhs.biggest?.name
                && lhs.biggest?.amount == rhs.biggest?.amount
        }
    }

    public enum Kind: Equatable, Sendable {
        /// A day like any other.
        case plain
        /// A day with a fixed charge (the rent): brass.
        case fixed
        /// What went that day, fixed charges aside, passed the limit a day: red.
        case over
        case today
        /// Still to come.
        case future
    }

    public struct Day: Equatable, Sendable {
        public let number: Int
        public let kind: Kind
        public let input: DayInput
        /// 0…1: the bar's height against the month's biggest day, by its square root so a day
        /// of rent doesn't flatten the rest. 0 for a day still to come.
        public let height: Double
    }

    public let days: [Day]
    /// Every payment of the month, counted or not: the ticket's folio.
    public let payments: Int
    /// What went a day so far, on average; `nil` before the first day is over.
    public let averagePerDay: Decimal?
    /// What a day may spend besides the fixed charges (`BudgetPace.dailyBase`); `nil` without
    /// a budget.
    public let limitPerDay: Decimal?

    /// `days[0]` is the 1st. `today` is the day of the month for this month, `nil` for one that
    /// is over (every day happened).
    public init(days input: [DayInput], today: Int?, limitPerDay limit: Decimal?) {
        let count = input.count
        let lastDay = today.map { min(max($0, 1), count) } ?? count
        let biggest = input.prefix(lastDay).map(\.total).max() ?? 0
        let biggestValue = NSDecimalNumber(decimal: biggest).doubleValue
        days = input.enumerated().map { index, day in
            let number = index + 1
            let kind: Kind
            if let today, number > today {
                kind = .future
            } else if number == today {
                kind = .today
            } else if let limit, day.variable > limit {
                kind = .over
            } else if day.fixedPayments > 0 {
                kind = .fixed
            } else {
                kind = .plain
            }
            let value = NSDecimalNumber(decimal: max(day.total, 0)).doubleValue
            let height = kind == .future || biggestValue <= 0 ? 0 : (value / biggestValue).squareRoot()
            return Day(number: number, kind: kind, input: day, height: height)
        }
        payments = input.reduce(0) { $0 + $1.payments }
        let spent = input.prefix(lastDay).reduce(Decimal(0)) { $0 + $1.total }
        averagePerDay = lastDay > 0 ? spent / Decimal(lastDay) : nil
        limitPerDay = limit
    }
}
