import Foundation

/// A past expense, as far as the category rule cares.
public struct CategorizedExpense: Equatable, Sendable {
    public var merchant: String
    public var category: String?
    public var date: Date
    /// The category was a suggestion nobody confirmed (the on-device model's). It is shown,
    /// but it is not *your* choice, so it is never remembered as one.
    public var isSuggested: Bool

    public init(merchant: String, category: String?, date: Date, isSuggested: Bool = false) {
        self.merchant = merchant
        self.category = category
        self.date = date
        self.isSuggested = isSuggested
    }
}

/// Categories you never have to pick twice: whatever you last filed a merchant
/// under is what the next payment from that merchant gets.
public enum CategoryMemory {
    /// The category to put on a new expense from `merchant`, or `nil` for a merchant
    /// you have never categorized.
    ///
    /// Merchant names match ignoring case, accents and padding, because Wallet is not
    /// consistent about any of the three. They have to match otherwise: guessing that
    /// `OXXO 1234` and `OXXO 5678` are the same place would be a guess, and a wrong
    /// one often enough to be worse than asking.
    public static func category(for merchant: String,
                                in history: [CategorizedExpense]) -> String? {
        let wanted = key(merchant)
        guard !wanted.isEmpty else { return nil }
        return history.enumerated()
            .filter { key($0.element.merchant) == wanted && $0.element.category != nil
                && !$0.element.isSuggested }
            // Newest wins; the index breaks ties so the answer never depends on
            // the order the caller happened to fetch rows in.
            .max { left, right in
                (left.element.date, left.offset) < (right.element.date, right.offset)
            }?
            .element.category
    }

    /// Every category you have used, most-used first, for offering them back to you.
    public static func known(in history: [CategorizedExpense]) -> [String] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for entry in history {
            guard let category = entry.category?.trimmingCharacters(in: .whitespaces),
                  !category.isEmpty else { continue }
            let key = key(category)
            counts[key, default: 0] += 1
            display[key] = category
        }
        return counts.keys
            .sorted { left, right in
                let leftCount = counts[left] ?? 0, rightCount = counts[right] ?? 0
                return leftCount == rightCount ? left < right : leftCount > rightCount
            }
            .compactMap { display[$0] }
    }

    /// Case, accents and padding don't make two names different.
    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
