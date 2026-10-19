import Foundation

/// The places you already paid at, offered back while you type a merchant's name.
public enum MerchantSuggestions {
    /// Up to `limit` merchants from the history, most visited first. With something typed,
    /// only those that contain it (the ones that start with it first) and not the exact
    /// name already typed.
    public static func matches(for typed: String, history: [CategorizedExpense],
                               limit: Int = 4) -> [String] {
        var counts: [String: Int] = [:]
        var display: [String: (name: String, date: Date)] = [:]
        for entry in history {
            let name = entry.merchant.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "Sin comercio" else { continue }
            let key = fold(name)
            counts[key, default: 0] += 1
            // The newest spelling is the one shown.
            if display[key].map({ entry.date > $0.date }) ?? true { display[key] = (name, entry.date) }
        }
        let wanted = fold(typed)
        let candidates = counts.keys.filter { key in
            wanted.isEmpty || (key.contains(wanted) && key != wanted)
        }
        return candidates
            .sorted { left, right in
                let leftPrefix = left.hasPrefix(wanted), rightPrefix = right.hasPrefix(wanted)
                if leftPrefix != rightPrefix { return leftPrefix }
                if counts[left]! != counts[right]! { return counts[left]! > counts[right]! }
                return left < right
            }
            .prefix(limit)
            .compactMap { display[$0]?.name }
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
