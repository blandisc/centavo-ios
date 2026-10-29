import Foundation

/// Picking one of the person's own categories by name (Siri's «¿cuánto llevo en…?»).
///
/// Only a category in the list comes back, spelled as offered; «Ninguna» or anything else is
/// no category at all.
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

    /// The answer, only if it is one of the offered categories (spelled as offered).
    /// «Ninguna», empty or anything else is no category at all.
    public static func validate(_ answer: String?, among candidates: [String]) -> String? {
        guard let answer else { return nil }
        let wanted = fold(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !wanted.isEmpty, wanted != fold(none) else { return nil }
        return candidates.first { fold($0) == wanted }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
