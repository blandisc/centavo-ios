import Foundation

/// The month already went past its budget: what is left to decide is how far past it closes.
///
/// Three ways to spend the days after today, each with what it allows a day and how far over
/// the month would close:
/// - **stop**: nothing more (only the fixed expenses still to come);
/// - **budget rate**: the day's amount the budget gave (`dailyBase`), as if the month were fine;
/// - **current rate**: what this month has been spending a day so far, outside fixed expenses.
///
/// Whole money, rounded up for what goes over (it is worse to promise a peso less of excess).
public struct OverspendPlan: Equatable, Sendable {
    public struct Path: Equatable, Sendable {
        /// What it spends each day after today.
        public let perDay: Decimal
        /// How far over the budget the month closes.
        public let closesOver: Decimal

        public init(perDay: Decimal, closesOver: Decimal) {
            self.perDay = perDay
            self.closesOver = closesOver
        }
    }

    /// How far over the budget it is right now.
    public let over: Decimal
    /// Days of the month after today.
    public let daysAfterToday: Int
    /// Fixed expenses still to come this month: they arrive even if nothing else is spent.
    public let fixedToCome: Decimal
    public let stop: Path
    public let budgetRate: Path
    public let currentRate: Path

    /// `nil` unless the month is over its budget.
    public init?(pace: BudgetPace) {
        guard pace.spent > pace.budget else { return nil }
        let after = max(pace.daysLeft - 1, 0)
        let now = pace.spent + pace.reserved - pace.budget
        over = Self.up(pace.spent - pace.budget)
        daysAfterToday = after
        fixedToCome = Self.up(pace.reserved)
        let days = Decimal(after)
        stop = Path(perDay: 0, closesOver: Self.up(now))
        let base = max(Self.down(pace.dailyBase), 0)
        budgetRate = Path(perDay: base, closesOver: Self.up(now + base * days))
        let variable = max(pace.spent - pace.fixedSpent, 0)
        let average = Self.down(variable / Decimal(max(pace.day, 1)))
        currentRate = Path(perDay: average, closesOver: Self.up(now + average * days))
    }

    private static func up(_ value: Decimal) -> Decimal { rounded(value, .up) }
    private static func down(_ value: Decimal) -> Decimal { rounded(value, .down) }

    private static func rounded(_ value: Decimal, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, mode)
        return output
    }
}
