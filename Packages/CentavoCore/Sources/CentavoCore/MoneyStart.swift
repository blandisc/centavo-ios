import Foundation

/// Where «Mi dinero» starts (2026-11-11). The first account makes a finished cut with the
/// opening balances, so the net worth shows at once. That cut is the starting point, not a cut
/// the person made: «Hacer corte» in that month must not ask to replace it, and it stays as
/// what the first real cut is compared with («+$4,200 desde el inicio»).
///
/// Nothing new is stored to tell them apart. A cut made by hand is finished after its accounts
/// were written (they had to be there to be asked for); the starting point is made in the same
/// instant as its first account, and every account added to it later is newer than it. Both
/// dates travel in the backup, so the answer is the same after a restore.
public enum MoneyStart {
    /// How much older than the cut an account may be and still be «of the same instant»: the
    /// account is made a moment before the cut that takes it.
    public static let slack: TimeInterval = 2

    /// A finished cut, with when each of its accounts was created.
    public struct Cut<ID: Hashable> {
        public var id: ID
        public var month: String
        public var date: Date
        public var accountsCreated: [Date]

        public init(id: ID, month: String, date: Date, accountsCreated: [Date]) {
            self.id = id
            self.month = month
            self.date = date
            self.accountsCreated = accountsCreated
        }
    }

    /// Whether a cut made on `cutDate` holds only opening balances: none of its accounts
    /// existed before it, so nobody reviewed them in a cut.
    public static func isStart(cutDate: Date, accountsCreated: [Date]) -> Bool {
        accountsCreated.allSatisfy { $0 >= cutDate.addingTimeInterval(-slack) }
    }

    /// The starting point among the finished cuts: only the very first one (by month, then by
    /// when it was made) can be it.
    public static func start<ID>(among finished: [Cut<ID>]) -> ID? {
        guard let first = finished.min(by: { ($0.month, $0.date) < ($1.month, $1.date) }),
              isStart(cutDate: first.date, accountsCreated: first.accountsCreated) else { return nil }
        return first.id
    }

    /// The cuts of `month` that finishing a new one there would replace, newest first: the ones
    /// the person made. The starting point is never among them; it is kept, not replaced.
    public static func replaced<ID>(byACutOf month: String, among finished: [Cut<ID>]) -> [Cut<ID>] {
        let start = start(among: finished)
        return finished.filter { $0.month == month && $0.id != start }.sorted { $0.date > $1.date }
    }

    /// How many cuts the person made: the starting point isn't one («Corte N.º 001» is the
    /// first one made by hand).
    public static func cutsMade<ID>(among finished: [Cut<ID>]) -> Int {
        finished.count - (start(among: finished) == nil ? 0 : 1)
    }
}
