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
    /// Merchant names match ignoring case, accents and spaces (`MerchantKey`), because Wallet
    /// is not consistent about any of them. They have to match otherwise: guessing that
    /// `OXXO 1234` and `OXXO 5678` are the same place would be a guess, and a wrong
    /// one often enough to be worse than asking.
    public static func category(for merchant: String,
                                in history: [CategorizedExpense]) -> String? {
        guard let wanted = MerchantKey.memory(merchant) else { return nil }
        return history.enumerated()
            .filter { MerchantKey.memory($0.element.merchant) == wanted && $0.element.category != nil
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
            let key = fold(category)
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

    /// The category you chose for `merchant`: your last decision (`rules`), or else what you
    /// last filed it under (`history`, for what was filed before decisions were kept). `nil`
    /// when you never filed it, decided it goes without one, or chose a category you have since
    /// hidden or deleted (`hidden`): a category you took away is never put back on its own.
    public static func remembered(for merchant: String, rules: CategoryRules,
                                  history: [CategorizedExpense], hidden: [String] = []) -> String? {
        remembered(for: merchant, rules: rules, hidden: hidden) { category(for: merchant, in: history) }
    }

    /// The same, with `history` already reduced by `latest(in:)`, for many merchants at once.
    public static func remembered(for merchant: String, rules: CategoryRules,
                                  latest: [String: String], hidden: [String] = []) -> String? {
        remembered(for: merchant, rules: rules, hidden: hidden) {
            MerchantKey.memory(merchant).flatMap { latest[$0] }
        }
    }

    /// What each merchant was last filed under, by `MerchantKey`. Suggestions don't count.
    public static func latest(in history: [CategorizedExpense]) -> [String: String] {
        var newest: [String: (date: Date, category: String)] = [:]
        for entry in history where !entry.isSuggested {
            guard let category = entry.category, let key = MerchantKey.memory(entry.merchant) else { continue }
            if let known = newest[key], known.date > entry.date { continue }
            newest[key] = (entry.date, category)
        }
        return newest.mapValues(\.category)
    }

    /// The category a new expense from `merchant` starts with: the one you chose, else the
    /// catalog's guess for a merchant you never decided about. Hidden categories are never
    /// filled in.
    public static func suggestion(for merchant: String, rules: CategoryRules,
                                  history: [CategorizedExpense], hidden: [String] = []) -> String? {
        if let mine = remembered(for: merchant, rules: rules, history: history, hidden: hidden) { return mine }
        if rules.choice(for: merchant) == .uncategorized { return nil }
        return MerchantCatalog.category(for: merchant).flatMap { isHidden($0, in: hidden) ? nil : $0 }
    }

    private static func remembered(for merchant: String, rules: CategoryRules, hidden: [String],
                                   fromHistory: () -> String?) -> String? {
        let chosen: String?
        switch rules.choice(for: merchant) {
        case .category(let name): chosen = name
        case .uncategorized: return nil
        case nil: chosen = fromHistory()
        }
        guard let chosen, !chosen.trimmingCharacters(in: .whitespaces).isEmpty,
              !isHidden(chosen, in: hidden) else { return nil }
        return chosen
    }

    private static func isHidden(_ category: String, in hidden: [String]) -> Bool {
        hidden.contains { fold($0) == fold(category) }
    }

    /// Case, accents and padding don't make two names different.
    static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
