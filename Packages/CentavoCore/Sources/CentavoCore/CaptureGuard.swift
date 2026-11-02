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
    /// Already marked «¿repetida?»: from the other automation, it's the pair of an earlier one.
    public var markedRepeated: Bool

    public init(amount: Decimal, merchant: String, card: String?, date: Date,
                currency: String? = nil, fromNotice: Bool = false, markedRepeated: Bool = false) {
        self.amount = amount
        self.merchant = merchant
        self.card = card
        self.date = date
        self.currency = currency
        self.fromNotice = fromNotice
        self.markedRepeated = markedRepeated
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
    /// «American Express México»): same amount and currency, and a shop that starts alike or the
    /// same card (2026-11-02; the shop or card since the independent review).
    public static let otherSourceWindow: TimeInterval = 2 * 60

    /// Only Wallet captures are ever `recent` (one typed or said by hand never enters).
    public static func check(amount: Decimal, merchant: String, card: String?,
                             at date: Date, recent: [RecentCapture],
                             currency: String? = nil, fromNotice: Bool = false) -> Verdict {
        if amount == 0 { return .empty }
        let new = RecentCapture(amount: amount, merchant: merchant, card: card, date: date,
                                currency: currency, fromNotice: fromNotice)
        let sameSource = recent.contains { previous in
            previous.fromNotice == fromNotice && previous.amount == amount
                && key(previous.merchant) == key(merchant)
                && key(previous.card ?? "") == key(card ?? "")
                && abs(previous.date.timeIntervalSince(date)) <= duplicateWindow
        }
        if sameSource { return .duplicate }
        // One to one: a pair already made (the later one marked) takes both out.
        var free = recent.sorted { $0.date < $1.date }
        for marked in free.filter({ $0.markedRepeated }) where free.contains(marked) {
            guard let partner = free.firstIndex(where: {
                $0 != marked && $0.fromNotice != marked.fromNotice && $0.date <= marked.date && alike($0, marked)
            }) else { continue }
            let partnerCapture = free[partner]
            free.removeAll { $0 == partnerCapture || $0 == marked }
        }
        return free.contains { $0.fromNotice != fromNotice && alike($0, new) } ? .duplicate : .save
    }

    /// The same payment told by the other automation.
    private static func alike(_ one: RecentCapture, _ other: RecentCapture) -> Bool {
        guard one.amount == other.amount, key(one.currency ?? "") == key(other.currency ?? ""),
              abs(one.date.timeIntervalSince(other.date)) <= otherSourceWindow else { return false }
        let sameCard = !key(one.card ?? "").isEmpty && key(one.card ?? "") == key(other.card ?? "")
        return sameCard || shopsAlike(one.merchant, other.merchant)
    }

    /// «OXXO ROBLE MTY» and «Oxxo»: one starts with the other, or both with the same word.
    static func shopsAlike(_ one: String, _ other: String) -> Bool {
        let a = words(one), b = words(other)
        guard let first = a.first, let second = b.first else { return false }
        let joinedA = a.joined(), joinedB = b.joined()
        return first == second || joinedA.hasPrefix(joinedB) || joinedB.hasPrefix(joinedA)
    }

    private static func words(_ text: String) -> [String] {
        key(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
