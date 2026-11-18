import Foundation

/// The places you already paid at, offered back while you type a merchant's name.
public enum MerchantSuggestions {
    /// The history folded once, by merchant: how often each was visited and its newest
    /// spelling. Built when the sheet opens, so each key typed only looks through the names,
    /// not the whole history (2026-11-18, with 5,000 expenses).
    public struct Index: Equatable, Sendable {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]

        public init() {}

        public init(_ history: [CategorizedExpense]) {
            var newest: [String: Date] = [:]
            for entry in history {
                let name = entry.merchant.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name != "Sin comercio" else { continue }
                let key = MerchantSuggestions.fold(name)
                counts[key, default: 0] += 1
                // The newest spelling is the one shown.
                if newest[key].map({ entry.date > $0 }) ?? true {
                    newest[key] = entry.date
                    display[key] = name
                }
            }
        }
    }

    /// Up to `limit` merchants from the history, most visited first. With something typed,
    /// only those that contain it (the ones that start with it first) and not the exact
    /// name already typed.
    public static func matches(for typed: String, history: [CategorizedExpense],
                               limit: Int = 4) -> [String] {
        matches(for: typed, in: Index(history), limit: limit)
    }

    /// The same, from an index built once (`Index`).
    public static func matches(for typed: String, in index: Index, limit: Int = 4) -> [String] {
        let counts = index.counts
        let wanted = fold(typed)
        let candidates = counts.keys.filter { key in
            wanted.isEmpty || (key.contains(wanted) && key != wanted)
        }
        return candidates
            .sorted { left, right in
                let leftPrefix = left.hasPrefix(wanted), rightPrefix = right.hasPrefix(wanted)
                if leftPrefix != rightPrefix { return leftPrefix }
                let leftCount = counts[left] ?? 0, rightCount = counts[right] ?? 0
                if leftCount != rightCount { return leftCount > rightCount }
                return left < right
            }
            .prefix(limit)
            .compactMap { index.display[$0] }
    }

    fileprivate static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
