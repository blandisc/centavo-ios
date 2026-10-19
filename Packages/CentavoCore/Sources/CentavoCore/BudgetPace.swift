import Foundation

/// Where the month stands against a budget: what was spent, what is left, and how
/// far along the month the spending ought to be by now.
public struct BudgetPace: Equatable, Sendable {
    public let budget: Decimal
    public let spent: Decimal
    /// Budget minus spent. Negative once the budget is blown.
    public let remaining: Decimal
    /// What an even daily spend would have reached by the end of `date`'s day.
    public let expectedToDate: Decimal
    /// Spent as a share of the budget, held to 0...1 so it can size a bar.
    public let spentFraction: Double
    /// How much of the month has gone by, 0...1.
    public let paceFraction: Double
    /// What is left spread over the days still to come, today included, in whole units:
    /// "hoy puedes gastar $185". Zero once the budget is gone. Fixed expenses still to come
    /// this month (`reserved`) are set apart first: the rent's money is not today's money.
    public let dailyAllowance: Decimal
    /// Fixed expenses that will come before the month ends and are not spent yet.
    public let reserved: Decimal
    /// Days left in the month, today included.
    public let daysLeft: Int

    public var isOverBudget: Bool { spent > budget }

    /// `nil` when there is no budget to measure against (unset, zero or negative).
    ///
    /// The budget is spread evenly over the days of the month, the simplest reading of
    /// "how much should I have spent by now" and the one that needs no explaining.
    public init?(budget: Decimal?, spent: Decimal, reserved: Decimal = 0, on date: Date,
                 calendar: Calendar = .current) {
        guard let budget, budget > 0,
              let days = calendar.range(of: .day, in: .month, for: date)?.count,
              days > 0 else { return nil }
        let day = calendar.component(.day, from: date)
        self.budget = budget
        self.spent = spent
        self.remaining = budget - spent
        self.expectedToDate = Self.cents(budget * Decimal(day) / Decimal(days))
        let ratio = NSDecimalNumber(decimal: spent / budget).doubleValue
        self.spentFraction = min(max(ratio, 0), 1)
        self.paceFraction = Double(day) / Double(days)
        self.daysLeft = days - day + 1
        self.reserved = max(reserved, 0)
        let perDay = (budget - spent - self.reserved) / Decimal(days - day + 1)
        self.dailyAllowance = perDay > 0 ? Self.whole(perDay) : 0
    }

    /// Rounded down: telling someone they can spend a peso more than they have is worse.
    private static func whole(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, .down)
        return output
    }

    private static func cents(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }
}
