import Foundation

/// A payment already saved, as far as duplicate detection cares.
public struct RecentCapture: Equatable, Sendable {
    public var amount: Decimal
    public var merchant: String
    public var card: String?
    public var date: Date
    /// The currency it was saved in («MXN»), when known.
    public var currency: String?
    /// It came from a Wallet notification («Notificación», iOS 27), not from «Transacción».
    public var fromNotice: Bool

    public init(amount: Decimal, merchant: String, card: String?, date: Date,
                currency: String? = nil, fromNotice: Bool = false) {
        self.amount = amount
        self.merchant = merchant
        self.card = card
        self.date = date
        self.currency = currency
        self.fromNotice = fromNotice
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

    /// How close the same payment arrives through both automations («Transacción» and
    /// «Notificación»), each with its own text («OXXO ROBLE MTY» and «Oxxo», «Amex» and
    /// «American Express México»): only the amount and currency are compared (2026-11-02).
    public static let otherSourceWindow: TimeInterval = 2 * 60

    public static func check(amount: Decimal, merchant: String, card: String?,
                             at date: Date, recent: [RecentCapture],
                             currency: String? = nil, fromNotice: Bool = false) -> Verdict {
        if amount == 0 { return .empty }
        let isRepeat = recent.contains { previous in
            guard previous.amount == amount else { return false }
            let apart = abs(previous.date.timeIntervalSince(date))
            if previous.fromNotice != fromNotice {
                return apart <= otherSourceWindow && key(previous.currency ?? "") == key(currency ?? "")
            }
            return key(previous.merchant) == key(merchant)
                && key(previous.card ?? "") == key(card ?? "")
                && apart <= duplicateWindow
        }
        return isRepeat ? .duplicate : .save
    }

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
