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
    /// What can still go today, in whole units: "hoy puedes gastar $185". What was left when
    /// the day began is spread over the days still to come, today included, and what today
    /// already spent comes off today's share only (spreading it over the rest of the month
    /// made the figure barely move after a purchase). Fixed expenses still to come this month
    /// (`reserved`) are set apart first: the rent's money is not today's money. Zero once
    /// today's share is gone.
    public let dailyAllowance: Decimal
    /// Today's share before anything was spent today: what was left when the day began, minus
    /// `reserved`, over `daysLeft`. Not rounded.
    public let todayShare: Decimal
    /// What today spent (part of `spent`).
    public let spentToday: Decimal
    /// Fixed expenses that will come before the month ends and are not spent yet.
    public let reserved: Decimal
    /// What is left once the fixed expenses still to come are set apart: «te quedan $X
    /// libres». Never below zero.
    public var free: Decimal { max(0, remaining - reserved) }
    /// Days left in the month, today included.
    public let daysLeft: Int

    public var isOverBudget: Bool { spent > budget }

    /// `nil` when there is no budget to measure against (unset, zero or negative).
    ///
    /// The budget is spread evenly over the days of the month, the simplest reading of
    /// "how much should I have spent by now" and the one that needs no explaining.
    /// `spentToday` is the part of `spent` that went on `date`'s day.
    public init?(budget: Decimal?, spent: Decimal, spentToday: Decimal = 0, reserved: Decimal = 0,
                 on date: Date, calendar: Calendar = .current) {
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
        self.spentToday = spentToday
        let beforeToday = spent - spentToday
        self.todayShare = (budget - beforeToday - self.reserved) / Decimal(days - day + 1)
        let left = todayShare - spentToday
        self.dailyAllowance = left > 0 ? Self.whole(left) : 0
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
