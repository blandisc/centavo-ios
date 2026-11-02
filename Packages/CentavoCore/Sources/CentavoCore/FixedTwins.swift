import Foundation

/// Two originals of one fixed expense (`fixedID`), from two devices that started it before iCloud
/// brought the other's (2026-11-02, second audit). One goes, and every device must keep the same
/// one: if each kept its own and deleted the other's, the charge would be gone from both.
public enum FixedTwins {
    /// What tells two originals apart, all of it travelling with them: their date first, then
    /// the notice they came from, then what they hold.
    public struct Key: Equatable, Sendable {
        public var date: Date
        public var notice: String?
        public var content: String

        public init(date: Date, notice: String?, content: String) {
            self.date = date
            self.notice = notice
            self.content = content
        }

        fileprivate var parts: (Double, String, String) {
            (date.timeIntervalSinceReferenceDate, notice ?? "", content)
        }
    }

    /// The one to keep: the only smallest. `nil` when nothing tells the smallest apart from
    /// another: this device can't know which one the other keeps, so neither is deleted.
    public static func keeper(_ keys: [Key]) -> Int? {
        guard let smallest = keys.indices.min(by: { keys[$0].parts < keys[$1].parts }) else { return nil }
        let ties = keys.filter { $0.parts == keys[smallest].parts }.count
        return ties == 1 ? smallest : nil
    }
}
