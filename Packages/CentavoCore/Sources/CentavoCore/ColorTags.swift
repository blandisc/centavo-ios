import Foundation

/// The color each category or way of paying keeps everywhere (owner's request, 2026-10-29):
/// Comida is always the same green, in the list, in «En qué se va» and in the widget.
///
/// Only a position in the app's palette (`0..<count`) is kept, never a color, so the app
/// can tune the palette without touching what someone chose. One of these holds the
/// categories and another the cards; each syncs with the settings.
public struct ColorTags: Codable, Equatable, Sendable {
    /// How many colors the palette has (`Theme.categories`).
    public static let count = 8

    /// Folded name → palette position, only for the ones someone chose (or got when made).
    public private(set) var chosen: [String: Int] = [:]

    public init() {}

    /// From what `stored` wrote; anything unreadable is no choices, never a crash.
    public init(stored: String) {
        self = (try? JSONDecoder().decode(Self.self, from: Data(stored.utf8))) ?? Self()
    }

    public var stored: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// The color of `name`: the one chosen, else `fallback` (the app's own categories have
    /// one), else one worked out from the name, so it never changes between launches.
    public func index(for name: String, fallback: Int? = nil) -> Int {
        let key = Self.key(name)
        if let own = chosen[key] { return own }
        if let fallback { return Self.wrap(fallback) }
        return Self.stableIndex(key)
    }

    /// `name` takes `index`; `nil` forgets it, so it goes back to its usual color.
    public mutating func set(_ index: Int?, for name: String) {
        let key = Self.key(name)
        guard !key.isEmpty else { return }
        chosen[key] = index.map(Self.wrap)
    }

    /// `old` is now called `new`: it keeps its color.
    public mutating func rename(_ old: String, to new: String) {
        let from = Self.key(old), to = Self.key(new)
        guard from != to, let own = chosen[from] else { return }
        chosen[from] = nil
        chosen[to] = own
    }

    /// For a new one: the color the fewest of `names` already have, the first in the palette
    /// on a tie, so the first eight never repeat.
    public func nextFree(among names: [String], fallback: (String) -> Int? = { _ in nil }) -> Int {
        var uses = Array(repeating: 0, count: Self.count)
        for name in names { uses[index(for: name, fallback: fallback(name))] += 1 }
        let fewest = uses.min() ?? 0
        return uses.firstIndex(of: fewest) ?? 0
    }

    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func wrap(_ index: Int) -> Int { ((index % count) + count) % count }

    /// FNV-1a over the name's bytes: the same on every launch and every phone (Swift's own
    /// `hashValue` changes on each launch).
    static func stableIndex(_ key: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(count))
    }
}
