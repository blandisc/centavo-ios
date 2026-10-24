import Foundation

/// How much of an expense counts toward the budget and every total.
///
/// An expense keeps its real amount (what the card was charged, what the CSV exports) and may
/// say how much of it counts: `nil` is all of it, as every expense from before this existed;
/// `0` is none («No cuenta»: a work trip that gets paid back, money between your own accounts).
/// A share in between is kept for later («solo cuenta mi mitad»), so the stored value already
/// allows it without another change to the iCloud schema.
public enum CountedAmount {
    /// What adds up: never more than the amount, and always with the amount's sign, so editing
    /// the amount later or turning it into a refund can't leave the two out of step.
    public static func effective(amount: Decimal, counted: Decimal?) -> Decimal {
        guard let counted else { return amount }
        let part = min(counted.magnitude, amount.magnitude)
        return amount < 0 ? -part : part
    }

    /// The part that is left out of the budget: what «Fuera del presupuesto» adds up.
    public static func excluded(amount: Decimal, counted: Decimal?) -> Decimal {
        amount - effective(amount: amount, counted: counted)
    }

    /// «No cuenta»: none of it adds up.
    public static func isUncounted(_ counted: Decimal?) -> Bool {
        counted == 0
    }
}

/// Why an expense doesn't count. Stored by `rawValue`, which never changes; `title` is what
/// the screen and the CSV say.
public enum UncountedReason: String, CaseIterable, Identifiable, Sendable {
    /// Work expenses and the like: someone else pays it back. The default.
    case reimbursed = "reembolso"
    /// A transfer to one of your own accounts: the money didn't leave.
    case betweenAccounts = "entre-cuentas"
    case other = "otro"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reimbursed: "Me lo reembolsan"
        case .betweenAccounts: "Entre mis cuentas"
        case .other: "Otro"
        }
    }

    /// From what was stored or written in a CSV: the stable value or the title, case and
    /// accents aside. Anything else is no reason at all, never a guess.
    public init?(text: String?) {
        guard let text else { return nil }
        let key = Self.fold(text)
        guard let match = Self.allCases.first(where: { Self.fold($0.rawValue) == key || Self.fold($0.title) == key })
        else { return nil }
        self = match
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
