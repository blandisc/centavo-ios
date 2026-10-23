import Foundation

/// A merchant's name as the category memory compares it: case, accents and spaces (around
/// or between words) don't make two merchants. Everything else does: «OXXO 1234» and
/// «OXXO 5678» are still two places.
public enum MerchantKey {
    public static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The key to remember a category under, or `nil` for a name that is no merchant at all:
    /// empty, or the «Sin comercio» the app writes when Wallet sent none.
    static func memory(_ name: String) -> String? {
        let key = normalized(name)
        return key.isEmpty || key == normalized(placeholder) ? nil : key
    }

    static let placeholder = "Sin comercio"
}

/// The category the owner last chose for each merchant, in the order they chose it.
///
/// The history of expenses says what each one is filed under, but not *when* that was
/// decided: correcting last month's Oxxo must win over this week's Oxxo, which only got its
/// category from the memory. So every choice made by hand is also written down here, and
/// the newest one wins. Kept small (one entry per merchant) to sync with the settings.
public struct CategoryRules: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// `MerchantKey.normalized`.
        public var merchant: String
        /// `nil`: the owner took the category off, so nothing is filled in for it.
        public var category: String?
    }

    public enum Choice: Equatable, Sendable {
        case category(String)
        /// The owner decided this merchant goes without a category.
        case uncategorized
    }

    /// Oldest first. Past `limit`, the oldest choices are forgotten (the history still has them).
    public private(set) var entries: [Entry] = []
    public static let limit = 1_000

    public init() {}

    /// From what `stored` wrote; anything unreadable is no rules, never a crash.
    public init(stored: String) {
        self = (try? JSONDecoder().decode(Self.self, from: Data(stored.utf8))) ?? Self()
    }

    public var stored: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// What the owner last decided for `merchant`, or `nil` if they never did here.
    public func choice(for merchant: String) -> Choice? {
        guard let key = MerchantKey.memory(merchant),
              let entry = entries.last(where: { $0.merchant == key }) else { return nil }
        return entry.category.map(Choice.category) ?? .uncategorized
    }

    /// The owner filed `merchant` under `category` (`nil` or blank: under none). Replaces
    /// whatever was there before.
    public mutating func learn(_ category: String?, for merchant: String) {
        guard let key = MerchantKey.memory(merchant) else { return }
        let clean = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.removeAll { $0.merchant == key }
        entries.append(Entry(merchant: key, category: (clean?.isEmpty ?? true) ? nil : clean))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    /// A category of their own got a new name: what was filed under it follows.
    public mutating func renameCategory(_ old: String, to new: String) {
        let wanted = CategoryMemory.fold(old)
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, !clean.isEmpty else { return }
        for index in entries.indices where entries[index].category.map(CategoryMemory.fold) == wanted {
            entries[index].category = clean
        }
    }
}
