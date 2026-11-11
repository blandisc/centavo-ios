import Foundation

/// Which rows marked as copies of a fixed expense may stand in for a charge that an original is
/// about to log (2026-11-11).
///
/// Before ids, a copy was matched to its original by merchant, amount and period, and that match
/// is still needed for copies with no `fixedOf`, and for copies whose `fixedOf` names an id no
/// original here has (two devices each gave the same old original its own id and one of them
/// won: the other's copies point at an id that no longer exists). But the copies of a fixed
/// expense that was stopped («Dejar de repetir») are known: matching them made another fixed
/// expense with the same merchant and amount skip its charge of that period, for good.
public enum FixedCopies {
    public enum Kind: Equatable, Sendable {
        /// A copy of an original that still repeats, by its id.
        case of(String)
        /// A fixed expense that was stopped, or one of its copies: it stands in for nothing.
        case stopped
        /// From before ids, or with an id nothing here explains: matched by merchant, amount and period.
        case legacy
    }

    /// The ids of the fixed expenses that were stopped: `stopRepeating` leaves the original as a
    /// copy of itself (`fixedOf` is its own `fixedID`), which no real copy ever is.
    public static func stoppedIDs(_ copies: [(fixedID: String?, fixedOf: String?)]) -> Set<String> {
        Set(copies.compactMap { copy in copy.fixedOf != nil && copy.fixedOf == copy.fixedID ? copy.fixedOf : nil })
    }

    /// An id that still repeats wins over a stopped one: if another device brought the original
    /// back, its copies count again.
    public static func kind(fixedOf: String?, active: Set<String>, stopped: Set<String>) -> Kind {
        guard let fixedOf else { return .legacy }
        if active.contains(fixedOf) { return .of(fixedOf) }
        return stopped.contains(fixedOf) ? .stopped : .legacy
    }
}
