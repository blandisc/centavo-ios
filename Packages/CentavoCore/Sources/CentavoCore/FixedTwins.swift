import Foundation

/// Two originals of one fixed expense (`fixedID`), from two devices that started it before iCloud
/// brought the other's (2026-11-02, second audit). One goes, and every device must keep the same
/// one: if each kept its own and deleted the other's, the charge would be gone from both.
public enum FixedTwins {
    /// The one to keep, by date alone: the only earliest. `nil` when another has the same exact
    /// date: then what differs is likely an edit not yet synced (Netflix 299 → 329), and deciding
    /// by content would delete it; this device also can't know which one the other keeps. Both stay
    /// (2026-11-02, independent review).
    public static func keeper(_ dates: [Date]) -> Int? {
        guard let earliest = dates.indices.min(by: { dates[$0] < dates[$1] }) else { return nil }
        return dates.filter { $0 == dates[earliest] }.count == 1 ? earliest : nil
    }
}
