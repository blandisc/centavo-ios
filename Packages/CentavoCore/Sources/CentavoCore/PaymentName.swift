import Foundation

/// A way of paying as the list writes it: short, so it never takes a line of its own
/// (owner, 2026-10-29). Wallet names the card in full («American Express México»); the
/// list says «Amex». The expense keeps the full name.
public enum PaymentName {
    /// Country words Wallet adds after the issuer's name.
    private static let countrySuffixes = ["méxico", "mexico", "mx"]
    /// Issuers people call by a shorter name.
    private static let nicknames = ["american express": "Amex"]

    public static func short(_ name: String) -> String {
        var words = name.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last,
              countrySuffixes.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            words.removeLast()
        }
        let joined = words.joined(separator: " ")
        let folded = joined.lowercased()
        for (full, nickname) in nicknames where folded.hasPrefix(full) {
            return nickname + joined.dropFirst(full.count)
        }
        return joined.isEmpty ? name : joined
    }
}
