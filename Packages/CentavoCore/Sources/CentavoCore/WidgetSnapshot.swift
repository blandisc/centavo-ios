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
        /// The category's own color (`ColorTags`). Optional so a snapshot written before it
        /// existed still reads; without it the widget colors by place.
        public var color: Int?

        public init(name: String?, amount: Decimal, isRest: Bool = false, color: Int? = nil) {
            self.name = name
            self.amount = amount
            self.isRest = isRest
            self.color = color
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
    /// What went each day of the month outside the fixed expenses, in the month's currency, from
    /// the 1st to the day it was taken: the boleto's cells (2026-10-30). Optional so a snapshot
    /// written before it existed still reads (its widgets keep the old bar).
    public var days: [Decimal]?
    /// The day of the month the budget counts from, when it was first set after the 1st
    /// (`BudgetHistory.terms`, 2026-11-11). Optional so a snapshot written before it existed
    /// still reads (as the whole month); what went before that day comes from `days`.
    public var startDay: Int?

    public init(budget: Decimal?, isoCode: String?, label: String, takenAt: Date, spent: Decimal,
                spentToday: Decimal = 0, fixedSpent: Decimal = 0, fixedToday: Decimal = 0,
                reserved: Decimal = 0, slices: [Slice] = [], mode: AllowanceMode = .carry,
                days: [Decimal]? = nil, startDay: Int? = nil) {
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
        self.days = days
        self.startDay = startDay
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
        month.days = days.map { _ in [] }
        // A new month has the budget from its 1st.
        month.startDay = nil
        return month
    }

    /// «Hoy puedes gastar» at `date`. `nil` without a budget.
    public func pace(at date: Date, calendar: Calendar = .current) -> BudgetPace? {
        let month = month(at: date, calendar: calendar)
        let start = max(month.startDay ?? 1, 1)
        // What the days before it spent outside the fixed expenses: the boleto's first cells.
        let before = (month.days ?? []).prefix(start - 1).reduce(Decimal(0), +)
        return BudgetPace(budget: budget, spent: month.spent, spentToday: month.spentToday,
                          fixedSpent: month.fixedSpent, fixedToday: month.fixedToday,
                          reserved: month.reserved, mode: mode ?? .carry, startDay: start,
                          variableBeforeStart: before, on: date, calendar: calendar)
    }

    /// How long a snapshot reads as fresh: after this the widgets say «Actualizado hace X».
    public static let freshFor: TimeInterval = 86_400

    /// Whole days since the app wrote this, once it is a day old or more; `nil` while fresh.
    /// A payment, Siri or opening the app writes it again, so a stale one means the widgets
    /// may be missing something.
    public func daysOld(at date: Date) -> Int? {
        let elapsed = date.timeIntervalSince(takenAt)
        guard elapsed >= Self.freshFor else { return nil }
        return Int(elapsed / Self.freshFor)
    }

    /// How often the widgets are told about a month that says the same: enough to keep
    /// «Actualizado hace X» honest without spending a reload on every save and every return.
    public static let reloadEvery: TimeInterval = 3_600

    /// Whether the widgets must be reloaded when this replaces `old`: something they show
    /// changed, the day did, or `old` is an hour old. The moment alone (`takenAt`, different in
    /// every snapshot) is no reason: WidgetKit gives each app only so many reloads a day.
    public func needsReload(replacing old: WidgetSnapshot?, calendar: Calendar = .current) -> Bool {
        guard var same = old else { return true }
        let before = same.takenAt
        same.takenAt = takenAt
        guard same == self else { return true }
        return !calendar.isDate(takenAt, inSameDayAs: before)
            || abs(takenAt.timeIntervalSince(before)) >= Self.reloadEvery
    }

    /// The shared App Group's key.
    public static let key = "widgetSnapshot"

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> WidgetSnapshot? {
        data.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
    }

    /// The lines for «En qué se va»: the three biggest categories and the rest as «Otras».
    /// `color` gives each category its own color.
    public static func slices(_ categories: [CategoryTotal],
                              color: (String) -> Int? = { _ in nil }) -> [Slice] {
        CategoryShare.top(categories, limit: 4).map {
            Slice(name: $0.isRest ? nil : $0.category, amount: $0.amount, isRest: $0.isRest,
                  color: $0.isRest ? nil : $0.category.flatMap(color))
        }
    }
}
