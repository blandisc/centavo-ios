import Foundation

/// The names the owner gave merchants by hand: a payment that comes from Wallet with the old
/// name is saved with the new one (owner's request, 2026-10-25).
///
/// Keyed by `MerchantKey`, so «OXXO 1234» and «oxxo 1234 » are the same, but «OXXO 5678» is
/// another place. Kept small (one entry per merchant) to sync with the settings.
public struct MerchantRenames: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// `MerchantKey.normalized` of the name Wallet sends.
        public var from: String
        /// The name the owner typed, as they typed it.
        public var to: String
    }

    /// Oldest first. Past `limit`, the oldest names are forgotten.
    public private(set) var entries: [Entry] = []
    public static let limit = 1_000

    public init() {}

    /// From what `stored` wrote; anything unreadable is no renames, never a crash.
    public init(stored: String) {
        self = (try? JSONDecoder().decode(Self.self, from: Data(stored.utf8))) ?? Self()
    }

    public var stored: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// The name to save a payment from `merchant` under, or `nil` if it was never renamed.
    public func name(for merchant: String) -> String? {
        guard let key = MerchantKey.memory(merchant) else { return nil }
        return entries.last { $0.from == key }?.to
    }

    /// `old` is now called `new`. What was renamed to `old` follows it, so renaming twice
    /// still lands on the last name; renaming back to the original forgets it.
    public mutating func rename(_ old: String, to new: String) {
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = MerchantKey.memory(old), let target = MerchantKey.memory(clean),
              key != target else { return }
        for index in entries.indices where MerchantKey.normalized(entries[index].to) == key {
            entries[index].to = clean
        }
        entries.removeAll { $0.from == key || $0.from == target }
        entries.append(Entry(from: key, to: clean))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }
}
