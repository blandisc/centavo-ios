import Foundation

/// Where the month stands against a budget: what was spent, what is left, and what can go
/// today.
///
/// «Hoy puedes gastar» carries every day over whole (owner's decision, 2026-10-22): the month
/// gives a fixed amount per day, `dailyBase` = (budget − the month's fixed expenses) ÷ days in
/// the month, and today can spend every day's amount so far, today included, minus what those
/// days already spent outside the fixed expenses. What a day leaves over goes whole to the
/// next one, and so does what it overspends; nothing is spread over the days still to come.
/// With $700 a day: spend $300 on the 1st and the 2nd can spend $1,100; spend $1,500 on the
/// 2nd and the 3rd can spend $300.
public struct BudgetPace: Equatable, Sendable {
    public let budget: Decimal
    public let spent: Decimal
    /// Budget minus spent. Negative once the budget is blown.
    public let remaining: Decimal
    /// What the month could have spent by the end of `date`'s day: the fixed expenses already
    /// charged plus one `dailyBase` per day so far, today included. «Podrías llevar».
    public let expectedToDate: Decimal
    /// Spent as a share of the budget, held to 0...1 so it can size a bar.
    public let spentFraction: Double
    /// How much of the month has gone by, 0...1.
    public let paceFraction: Double
    /// The month's amount per day: (budget − `fixedMonth`) ÷ days in the month. Not rounded.
    public let dailyBase: Decimal
    /// Fixed expenses of the month: the ones already charged (`fixedSpent`) and the ones still
    /// to come (`reserved`). They come off the budget before it is cut into days.
    public var fixedMonth: Decimal { fixedSpent + reserved }
    /// What the days before today left over (positive) or overspent (negative), outside the
    /// fixed expenses: «vas $400 abajo del ritmo». Zero on the 1st.
    public let carriedOver: Decimal
    /// What today could spend before anything was spent today: `dailyBase` + `carriedOver`.
    /// Not rounded.
    public let todayShare: Decimal
    /// What can still go today, in whole units: `todayShare` minus what today spent outside the
    /// fixed expenses, rounded down (telling someone they can spend a peso more than they have
    /// is worse). Negative once today went past it: «hoy te pasaste $300».
    public let dailyAllowance: Decimal
    /// What today spent (part of `spent`), fixed expenses included.
    public let spentToday: Decimal
    /// What today spent outside the fixed expenses: what comes off `todayShare`.
    public let variableToday: Decimal
    /// Fixed expenses already charged this month (part of `spent`).
    public let fixedSpent: Decimal
    /// Fixed expenses that will come before the month ends and are not spent yet.
    public let reserved: Decimal
    /// What is left once the fixed expenses still to come are set apart: «te quedan $X
    /// libres». Never below zero.
    public var free: Decimal { max(0, remaining - reserved) }
    /// Days left in the month, today included.
    public let daysLeft: Int
    /// The day of the month `date` falls on, and how many days the month has.
    public let day: Int
    public let daysInMonth: Int

    public var isOverBudget: Bool { spent > budget }
    /// Today already spent more than it could.
    public var isOverToday: Bool { dailyAllowance < 0 }

    /// `nil` when there is no budget to measure against (unset, zero or negative).
    ///
    /// `spentToday` is the part of `spent` that went on `date`'s day. `fixedSpent` is the part
    /// of `spent` that went on fixed expenses this month, and `fixedToday` the part of that
    /// charged today. `reserved` is what the fixed expenses still to come add up to.
    public init?(budget: Decimal?, spent: Decimal, spentToday: Decimal = 0,
                 fixedSpent: Decimal = 0, fixedToday: Decimal = 0, reserved: Decimal = 0,
                 on date: Date, calendar: Calendar = .current) {
        guard let budget, budget > 0,
              let days = calendar.range(of: .day, in: .month, for: date)?.count,
              days > 0 else { return nil }
        let day = calendar.component(.day, from: date)
        self.budget = budget
        self.spent = spent
        self.remaining = budget - spent
        self.day = day
        self.daysInMonth = days
        self.daysLeft = days - day + 1
        let ratio = NSDecimalNumber(decimal: spent / budget).doubleValue
        self.spentFraction = min(max(ratio, 0), 1)
        self.paceFraction = Double(day) / Double(days)
        self.reserved = max(reserved, 0)
        self.fixedSpent = fixedSpent
        self.spentToday = spentToday
        self.variableToday = spentToday - fixedToday
        // Multiplied before dividing: 1,000 ÷ 31 × 31 is 999.99… in Decimal, and the last day
        // has to get exactly what is left.
        let pool = budget - fixedSpent - self.reserved
        let length = Decimal(days)
        self.dailyBase = pool / length
        let variableBefore = (spent - spentToday) - (fixedSpent - fixedToday)
        let throughToday = pool * Decimal(day) / length
        self.carriedOver = pool * Decimal(day - 1) / length - variableBefore
        self.todayShare = throughToday - variableBefore
        self.dailyAllowance = Self.whole(todayShare - variableToday)
        self.expectedToDate = Self.cents(fixedSpent + throughToday)
    }

    /// Rounded down, toward less money: $189.70 is $189 and −$300.20 is −$301.
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
