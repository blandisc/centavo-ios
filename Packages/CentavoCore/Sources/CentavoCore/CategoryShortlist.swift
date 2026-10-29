import Foundation

/// The categories the expense sheet shows before «Ver todas»: what it suggests or already has
/// first, then the ones used most, and the rest behind one tap.
public enum CategoryShortlist {
    /// Splits `offered` (every category that may be picked, in the sheet's order) in two.
    /// `pinned` (the suggestion, the one chosen) go first; then up to `count` from `mostUsed`
    /// (most used first); with fewer used than `count`, the first offered fill in. A name not
    /// in `offered` (hidden) is never shown. `rest` keeps `offered`'s order.
    public static func split(offered: [String], mostUsed: [String], pinned: [String],
                             count: Int = 5) -> (shown: [String], rest: [String]) {
        var shown: [String] = []
        func add(_ name: String) {
            guard let match = offered.first(where: { fold($0) == fold(name) }),
                  !shown.contains(where: { fold($0) == fold(match) }) else { return }
            shown.append(match)
        }
        pinned.forEach(add)
        let start = shown.count
        for name in mostUsed where shown.count - start < count { add(name) }
        for name in offered where shown.count - start < count { add(name) }
        let rest = offered.filter { name in !shown.contains { fold($0) == fold(name) } }
        return (shown, rest)
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
