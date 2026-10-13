import Foundation

/// A payment already saved, as far as duplicate detection cares.
public struct RecentCapture: Equatable, Sendable {
    public var amount: Decimal
    public var merchant: String
    public var card: String?
    public var date: Date

    public init(amount: Decimal, merchant: String, card: String?, date: Date) {
        self.amount = amount
        self.merchant = merchant
        self.card = card
        self.date = date
    }
}

/// Decides whether a payment handed over by the Wallet automation should be saved.
///
/// Two known misbehaviors of the trigger (see docs/research/atajos-wallet.md):
/// it sometimes passes an empty payment (amount 0, blank merchant), and it can
/// fire more than once for the same tap.
public enum CaptureGuard {
    public enum Verdict: Equatable, Sendable {
        case save
        /// Wallet sent a zero amount: almost certainly a glitch, not a free purchase.
        case empty
        /// The same payment was saved a moment ago.
        case duplicate
    }

    /// How close two identical payments must be to count as one.
    public static let duplicateWindow: TimeInterval = 5 * 60

    public static func check(amount: Decimal, merchant: String, card: String?,
                             at date: Date, recent: [RecentCapture]) -> Verdict {
        if amount == 0 { return .empty }
        let isRepeat = recent.contains { previous in
            previous.amount == amount
                && key(previous.merchant) == key(merchant)
                && key(previous.card ?? "") == key(card ?? "")
                && abs(previous.date.timeIntervalSince(date)) <= duplicateWindow
        }
        return isRepeat ? .duplicate : .save
    }

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
