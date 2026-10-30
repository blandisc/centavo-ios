import Foundation

/// The toy month that explains the two rules of «Hoy puedes gastar» on the budget sheet: a
/// week of days with the same amount each, the same spending under both rules, and where
/// what a day leaves over (or overspends) goes.
///
/// - `.carry` («Se acumula»): all of it goes to the next day.
/// - `.spread` («Se reparte»): it is shared evenly over every day still to come.
///
/// Only for the drawing: the real figures come from `BudgetPace`. The week is chosen so that
/// every share is whole money and exact, so what moves always adds up to what was left
/// (a rounded share once gave six days +$7 out of $40).
public struct AllowanceDemo: Equatable, Sendable {
    /// One day of the toy month.
    public struct Day: Equatable, Sendable {
        /// What the day could spend when it began.
        public let allowance: Decimal
        public let spent: Decimal
        /// What it left over (negative: overspent).
        public var left: Decimal { allowance - spent }

        public init(allowance: Decimal, spent: Decimal) {
            self.allowance = allowance
            self.spent = spent
        }
    }

    /// What the day handed on, and to which days: the next one (`.carry`) or all the
    /// ones after it (`.spread`), each getting `each`.
    public struct Move: Equatable, Sendable {
        public let from: Int
        public let to: [Int]
        public let each: Decimal

        public init(from: Int, to: [Int], each: Decimal) {
            self.from = from
            self.to = to
            self.each = each
        }
    }

    public static let perDay: Decimal = 100
    /// A week with light days and heavy ones, so both rules show; with `.spread` every
    /// leftover divides evenly by the days still to come ($30 / 6, −$35 / 5, $28 / 4…).
    public static let spending: [Decimal] = [70, 140, 70, 60, 130, 100, 80]

    public let mode: AllowanceMode
    public let budgetPerDay: Decimal
    public let days: [Day]
    public let moves: [Move]

    public init(mode: AllowanceMode, perDay: Decimal = Self.perDay, spending: [Decimal] = Self.spending) {
        self.mode = mode
        budgetPerDay = perDay
        var allowances = Array(repeating: perDay, count: spending.count)
        var days: [Day] = []
        var moves: [Move] = []
        for (index, spent) in spending.enumerated() {
            let day = Day(allowance: allowances[index], spent: spent)
            days.append(day)
            let later = Array(index + 1 ..< spending.count)
            guard !later.isEmpty else { continue }
            switch mode {
            case .carry:
                moves.append(Move(from: index, to: [index + 1], each: day.left))
                allowances[index + 1] += day.left
            case .spread:
                let each = day.left / Decimal(later.count)
                moves.append(Move(from: index, to: later, each: each))
                for target in later { allowances[target] += each }
            }
        }
        self.days = days
        self.moves = moves
    }

    /// What the week could spend in all (`perDay` × days).
    public var budget: Decimal { budgetPerDay * Decimal(days.count) }
    /// What the week spent in all.
    public var spent: Decimal { days.reduce(0) { $0 + $1.spent } }
}
