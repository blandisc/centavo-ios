import Foundation

/// What the on-device model is given to file a merchant, and how its answer is checked.
///
/// The model only ever chooses: from the person's own categories, or «Ninguna». Whatever it
/// answers goes through `validate`, so a word outside the list can never reach an expense.
public enum CategoryPick {
    /// The answer for «the name doesn't say what was bought».
    public static let none = "Ninguna"

    /// Every name once, in the order given (the usual ones, yours, then the ones you used).
    public static func candidates(_ lists: [String]...) -> [String] {
        var names: [String] = []
        for name in lists.joined() {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, fold(clean) != fold(none),
                  !names.contains(where: { fold($0) == fold(clean) }) else { continue }
            names.append(clean)
        }
        return names
    }

    /// How this person files things, for the prompt: one merchant they categorized
    /// themselves per category, the most recent first. Suggestions are not examples.
    public static func examples(from history: [CategorizedExpense],
                                limit: Int = 8) -> [(merchant: String, category: String)] {
        var seen: Set<String> = []
        var picked: [(merchant: String, category: String)] = []
        for entry in history.sorted(by: { $0.date > $1.date }) where !entry.isSuggested {
            guard let category = entry.category?.trimmingCharacters(in: .whitespaces),
                  !category.isEmpty, !seen.contains(fold(category)) else { continue }
            let merchant = entry.merchant.trimmingCharacters(in: .whitespaces)
            guard !merchant.isEmpty, merchant != "Sin comercio" else { continue }
            seen.insert(fold(category))
            picked.append((merchant, category))
            if picked.count == limit { break }
        }
        return picked
    }

    /// The model's answer, only if it is one of the offered categories (spelled as offered).
    /// «Ninguna», empty or anything else is no category at all.
    public static func validate(_ answer: String?, among candidates: [String]) -> String? {
        guard let answer else { return nil }
        let wanted = fold(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !wanted.isEmpty, wanted != fold(none) else { return nil }
        return candidates.first { fold($0) == wanted }
    }

    /// The prompt for one merchant: its name as it came, a cleaner reading if there is one,
    /// and the person's own examples. Short on purpose: the model's context is small.
    public static func prompt(merchant: String, readable: String?,
                              examples: [(merchant: String, category: String)]) -> String {
        var lines = ["Comercio: «\(merchant)»"]
        if let readable { lines.append("Lectura limpia: «\(readable)»") }
        if !examples.isEmpty {
            lines.append("Así archiva esta persona otros comercios:")
            lines += examples.map { "- \($0.merchant) → \($0.category)" }
        }
        return lines.joined(separator: "\n")
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
