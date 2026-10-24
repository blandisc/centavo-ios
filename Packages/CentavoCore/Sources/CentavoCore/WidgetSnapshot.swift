import Foundation

/// What the app leaves for its widgets: the month's sums at the moment of the last change.
///
/// The widgets cannot open the app's store, so the app writes this to the shared App Group
/// after every change, and the widget works out «Hoy puedes gastar» for any later moment with
/// the same `BudgetPace`: at midnight, today's spending becomes "before today" without the
/// app running. A new month starts from zero, with last month's fixed expenses set apart
/// (they repeat) until the app runs again and counts the real ones.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// One line of «En qué se va»: a category, or «Otras» (`name == nil`, `isRest`).
    public struct Slice: Codable, Equatable, Sendable {
        public var name: String?
        public var amount: Decimal
        public var isRest: Bool

        public init(name: String?, amount: Decimal, isRest: Bool = false) {
            self.name = name
            self.amount = amount
            self.isRest = isRest
        }
    }

    public var budget: Decimal?
    /// The month's currency, to write the figures: an ISO code when known, else the marker.
    public var isoCode: String?
    public var label: String
    /// When the sums were taken.
    public var takenAt: Date
    public var spent: Decimal
    public var spentToday: Decimal
    public var fixedSpent: Decimal
    public var fixedToday: Decimal
    public var reserved: Decimal
    /// Biggest first: the three biggest categories and «Otras».
    public var slices: [Slice]
    /// The rule chosen in the budget sheet. Optional so a snapshot written before it existed
    /// still reads (as `.carry`).
    public var mode: AllowanceMode?

    public init(budget: Decimal?, isoCode: String?, label: String, takenAt: Date, spent: Decimal,
                spentToday: Decimal = 0, fixedSpent: Decimal = 0, fixedToday: Decimal = 0,
                reserved: Decimal = 0, slices: [Slice] = [], mode: AllowanceMode = .carry) {
        self.budget = budget
        self.isoCode = isoCode
        self.label = label
        self.takenAt = takenAt
        self.spent = spent
        self.spentToday = spentToday
        self.fixedSpent = fixedSpent
        self.fixedToday = fixedToday
        self.reserved = reserved
        self.slices = slices
        self.mode = mode
    }

    /// The month as it stands at `date`, which may be days after `takenAt`.
    public func month(at date: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        var month = self
        month.takenAt = date
        if calendar.isDate(date, inSameDayAs: takenAt) { return month }
        month.spentToday = 0
        month.fixedToday = 0
        guard !calendar.isDate(date, equalTo: takenAt, toGranularity: .month) else { return month }
        month.reserved = fixedSpent + reserved
        month.spent = 0
        month.fixedSpent = 0
        month.slices = []
        return month
    }

    /// «Hoy puedes gastar» at `date`. `nil` without a budget.
    public func pace(at date: Date, calendar: Calendar = .current) -> BudgetPace? {
        let month = month(at: date, calendar: calendar)
        return BudgetPace(budget: budget, spent: month.spent, spentToday: month.spentToday,
                          fixedSpent: month.fixedSpent, fixedToday: month.fixedToday,
                          reserved: month.reserved, mode: mode ?? .carry, on: date, calendar: calendar)
    }

    /// The shared App Group's key.
    public static let key = "widgetSnapshot"

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> WidgetSnapshot? {
        data.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
    }

    /// The lines for «En qué se va»: the three biggest categories and the rest as «Otras».
    public static func slices(_ categories: [CategoryTotal]) -> [Slice] {
        CategoryShare.top(categories, limit: 4).map {
            Slice(name: $0.isRest ? nil : $0.category, amount: $0.amount, isRest: $0.isRest)
        }
    }
}
