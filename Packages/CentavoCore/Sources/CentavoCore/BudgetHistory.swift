import Foundation

/// Which budget judges a month, and from which of its days it counts (`BudgetHistory.terms`).
public struct BudgetTerms: Equatable, Sendable {
    /// The budget the month is measured against; `nil` when it had none.
    public let budget: Decimal?
    /// The day of the month «Hoy puedes gastar» counts from: 1 unless this month's budget was
    /// first set on a later day, with none on the 1st.
    public let startDay: Int

    public init(budget: Decimal?, startDay: Int = 1) {
        self.budget = budget
        self.startDay = startDay
    }
}

/// The budget over time: a short list of «since this moment, this much» (and «since this
/// moment, none» when it is taken off), owner's request, 2026-11-11.
///
/// It answers two things the single saved figure couldn't: a month that is over is judged with
/// the budget it had when it closed, not with today's; and a budget first set halfway through
/// the month counts from that day, so the days before it are not money left over.
///
/// The saved figure (`monthlyBudget`) stays the truth about the budget in force: this list only
/// remembers when it changed. With a budget and no list (everyone before this existed) the
/// budget is taken to have always been that one.
public struct BudgetHistory: Equatable, Sendable {
    /// The UserDefaults key the app keeps the list under, as JSON text (synced and backed up
    /// like the budget).
    public static let key = "budgetHistory"
    /// How many changes are kept: the oldest go first.
    public static let limit = 60

    public struct Entry: Codable, Equatable, Sendable {
        /// When it began, in seconds since 1970; `nil` is «always» (what the budget was before
        /// the first change written down).
        public var since: Double?
        /// The amount as text, to keep the cents exact; empty for «no budget».
        public var amount: String

        public init(since: Date?, amount: Decimal?) {
            self.since = since.map { $0.timeIntervalSince1970.rounded(.down) }
            self.amount = amount.flatMap { $0 > 0 ? "\($0)" : nil } ?? ""
        }

        public var date: Date? { since.map(Date.init(timeIntervalSince1970:)) }

        public var value: Decimal? {
            guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")),
                  value > 0 else { return nil }
            return value
        }
    }

    /// Oldest first; «always», if there, is the first one.
    public private(set) var entries: [Entry]
    /// The text they were read from, to write back what a newer version saved and this one
    /// can't read (`LenientList`).
    private var source: String

    public init(stored: String = "") {
        source = stored
        entries = LenientList.decode(Entry.self, from: stored).items
            .enumerated()
            .sorted { ($0.element.since ?? -.infinity, $0.offset) < ($1.element.since ?? -.infinity, $1.offset) }
            .map(\.element)
    }

    /// The list as JSON text; empty with nothing written down.
    public var stored: String {
        if entries.isEmpty, LenientList.decode(Entry.self, from: source).unread.isEmpty { return "" }
        return LenientList.encode(entries, keepingUnreadFrom: source)
    }

    public static func == (lhs: BudgetHistory, rhs: BudgetHistory) -> Bool { lhs.entries == rhs.entries }

    // MARK: Writing a change down

    /// The list after the budget went from `previous` to `amount` at `date`.
    ///
    /// - Nothing changes when the newest entry already says `amount`.
    /// - The first change ever written keeps `previous` as what the budget «always» was, so
    ///   the months before it go on being judged with it.
    /// - Several changes on the same day leave the last one; one that ends where the day began
    ///   leaves no trace.
    /// - An entry dated after `date`'s day (the clock was moved) is dropped: it can't have
    ///   happened yet. One from later the same day is not from the future: a screen asks with
    ///   the moment it last looked at the clock, minutes before the change it is drawing.
    public func recording(_ amount: Decimal?, previous: Decimal?, on date: Date,
                          calendar: Calendar = .current) -> BudgetHistory {
        let new = Entry(since: date, amount: amount)
        let dayEnd = calendar.dateInterval(of: .day, for: date)?.end ?? date
        var list = entries.filter { ($0.since ?? -.infinity) < dayEnd.timeIntervalSince1970 }
        if list.isEmpty {
            let before = Entry(since: nil, amount: previous)
            guard before.value != new.value else { return with(list) }
            if before.value != nil { list.append(before) }
        } else if list.last?.value == new.value {
            return with(list)
        }
        if let last = list.last?.date, calendar.isDate(last, inSameDayAs: date) { list.removeLast() }
        // Back to what it was when the day began (or to nothing, with nothing before): no entry.
        if list.last?.value != new.value { list.append(new) }
        if list.count > Self.limit { list.removeFirst(list.count - Self.limit) }
        return with(list)
    }

    /// The list made to agree with the budget in force, `current`: if the newest entry says
    /// something else (an older version of the app changed it, or another phone did), that
    /// change is written down as of `date`. With no list, `current` is what it always was.
    public func settled(current: Decimal?, on date: Date, calendar: Calendar = .current) -> BudgetHistory {
        // Already agrees: left exactly as it is, whatever moment is asked about.
        if let last = entries.last, last.value == Entry(since: nil, amount: current).value { return self }
        return recording(current, previous: current, on: date, calendar: calendar)
    }

    /// This phone's list after `remote` arrives from iCloud, where the last one to write wins.
    ///
    /// `remote` is taken as it is when it is empty or says what the budget «always» was. When
    /// it only begins on some day (a second phone that went through the welcome before iCloud
    /// arrived), what this phone knows from before that day is kept in front of it: its older
    /// entries, or, with no list and a budget (`localBudget`, read before the new figure is
    /// adopted), that budget as «always». So a list from elsewhere never makes a budget this
    /// phone already had begin today, nor takes its past months' budget away. An entry that
    /// repeats the one before it is dropped.
    public func adopting(_ remote: BudgetHistory, localBudget: Decimal?) -> BudgetHistory {
        guard let begins = remote.entries.first?.since else { return remote }
        var older = entries.filter { ($0.since ?? -.infinity) < begins }
        if entries.isEmpty {
            let always = Entry(since: nil, amount: localBudget)
            if always.value != nil { older = [always] }
        }
        guard !older.isEmpty else { return remote }
        var list: [Entry] = []
        for entry in older + remote.entries where list.last?.value != entry.value || list.isEmpty {
            list.append(entry)
        }
        return remote.with(list)
    }

    private func with(_ list: [Entry]) -> BudgetHistory {
        var copy = self
        copy.entries = list
        return copy
    }

    // MARK: Reading

    /// The budget `month` is judged with, and the day it counts from. `current` is the budget
    /// in force (the saved figure) and `now` the moment it is asked.
    ///
    /// - **The month `now` is in** (or a later one): `current`. It counts from the 1st unless
    ///   there was no budget on the 1st and it was first set on a later day of this month; then
    ///   from that day. Changing the amount doesn't move that day, and neither does taking the
    ///   budget off and setting it again within the month.
    /// - **A month that is over:** the budget in force when it closed; `nil` if it had been
    ///   taken off. Before the first entry and with no «always», the oldest amount known.
    public func terms(for month: Date, current: Decimal?, now: Date,
                      calendar: Calendar = .current) -> BudgetTerms {
        let current = current.flatMap { $0 > 0 ? $0 : nil }
        let history = settled(current: current, on: now, calendar: calendar)
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return BudgetTerms(budget: current)
        }
        guard interval.end <= now else {
            guard let current else { return BudgetTerms(budget: nil) }
            return BudgetTerms(budget: current, startDay: history.startDay(in: interval, calendar: calendar))
        }
        guard !history.entries.isEmpty else { return BudgetTerms(budget: current) }
        if let closing = history.entry(before: interval.end) { return BudgetTerms(budget: closing.value) }
        return BudgetTerms(budget: history.entries.first { $0.value != nil }?.value)
    }

    /// The newest entry that began before `moment`.
    private func entry(before moment: Date) -> Entry? {
        entries.last { ($0.since ?? -.infinity) < moment.timeIntervalSince1970 }
    }

    /// The day of the month in `interval` its budget counts from.
    private func startDay(in interval: DateInterval, calendar: Calendar) -> Int {
        // A budget at any moment of the 1st was there on the 1st.
        let secondDay = calendar.date(byAdding: .day, value: 1, to: interval.start) ?? interval.start
        if entries.isEmpty || entry(before: secondDay)?.value != nil { return 1 }
        let first = entries.first {
            guard let date = $0.date, $0.value != nil else { return false }
            return date >= secondDay && date < interval.end
        }
        return first?.date.map { calendar.component(.day, from: $0) } ?? 1
    }
}
