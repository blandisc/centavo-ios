import Foundation

/// A Wallet payment the capture received and could not write down: its amount didn't read, or
/// the app couldn't open or save its expenses right then (2026-11-11, the map of states).
///
/// Kept outside the store, so it survives the store failing, until the person writes it down
/// or discards it. A payment that comes in right after it does not take it away.
public struct PendingPayment: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The notice arrived without an amount that could be read.
        case unread
        /// It read, and the app couldn't open or save the expenses.
        case unsaved
    }

    public let id: UUID
    public let kind: Kind
    /// What the person sees: «Google», «$319 en Google».
    public let text: String
    public let date: Date
    /// What was read of a payment that couldn't be saved, to fill the sheet with.
    public var amount: String?
    public var merchant: String?
    public var card: String?

    public init(id: UUID = UUID(), kind: Kind, text: String, date: Date,
                amount: String? = nil, merchant: String? = nil, card: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.card = card
    }

    /// The longest text kept of a notice: a line of a notification, not a document.
    public static let maxText = 80

    /// A notice the capture couldn't read, if it is worth keeping.
    ///
    /// Not every Wallet notification is a charge: a pass or a promotion comes as title and
    /// body and is let go. One line with no figure looks like a wrong wiring in Atajos (only
    /// the merchant arrived) and is kept. `always`: it read as a charge whose amount still
    /// didn't make it, so it is kept whatever it looks like.
    public static func unread(_ notice: String, always: Bool = false, date: Date, id: UUID = UUID()) -> PendingPayment? {
        let lines = clean(notice)
        guard let first = lines.first,
              always || (lines.count == 1 && !first.contains(where: \.isNumber)) else { return nil }
        return PendingPayment(id: id, kind: .unread, text: String(first.prefix(maxText)), date: date)
    }

    /// A payment that read and couldn't be saved: «$319 en Google». `nil` with nothing to show.
    public static func unsaved(amount: String, merchant: String?, card: String?, date: Date,
                               id: UUID = UUID()) -> PendingPayment? {
        let amountLine = clean(amount).first.map { String($0.prefix(maxText)) }
        let shop = clean(merchant ?? "").first.map { String($0.prefix(maxText)) }
        let cardName = clean(card ?? "").first.map { String($0.prefix(maxText)) }
        let text: String
        switch (amountLine, shop) {
        case (let amount?, let shop?): text = "\(amount) en \(shop)"
        case (let amount?, nil): text = amount
        case (nil, let shop?): text = shop
        case (nil, nil): return nil
        }
        return PendingPayment(id: id, kind: .unsaved, text: text, date: date,
                              amount: amountLine, merchant: shop, card: cardName)
    }

    /// Only a name arrived, with no figure and no currency («Oxxo»): the one kind of notice a
    /// good payment from the same shop may take away by itself (`PendingPayments.settling`).
    /// One with a figure or a currency is money that didn't read, and only the person removes it.
    public var isNameOnly: Bool {
        kind == .unread && !text.contains(where: \.isNumber) && !WalletNotice.mentionsMoney(text)
    }

    /// What the sheet of a new expense starts with for this payment: all that was read of one
    /// that couldn't be saved; of a notice with no amount, its text as the shop when it looks
    /// like a name. `primary`: the currency a bare «$» stands for.
    public func prefill(primary: String) -> ExpensePrefill {
        var fill = ExpensePrefill(date: date)
        switch kind {
        case .unsaved:
            if let amount, let read = CaptureText.amount(in: amount), read.value != 0 {
                fill.amountText = AmountTyping.grouped(read.value.magnitude
                    .formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(AmountTyping.written)))
                fill.isRefund = read.value < 0
                fill.currency = CurrencyResolver.isoCode(for: read.currencyMarker, primary: primary)
            }
            fill.merchant = merchant
            fill.card = card
        case .unread:
            if isNameOnly { fill.merchant = text }
        }
        return fill
    }

    private static func clean(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// What a pending payment fills the sheet of a new expense with (`PendingPayment.prefill`).
/// `nil` is «not known»: the sheet keeps its own start for it.
public struct ExpensePrefill: Equatable, Sendable {
    /// As the amount field writes it: «1,234.50».
    public var amountText: String?
    public var isRefund = false
    /// ISO code, when the payment said its currency.
    public var currency: String?
    public var merchant: String?
    public var card: String?
    public var date: Date?

    public init(amountText: String? = nil, isRefund: Bool = false, currency: String? = nil,
                merchant: String? = nil, card: String? = nil, date: Date? = nil) {
        self.amountText = amountText
        self.isRefund = isRefund
        self.currency = currency
        self.merchant = merchant
        self.card = card
        self.date = date
    }
}

/// The list of payments waiting to be written down: newest first, at most `limit`, none older
/// than `keepDays`, so it can't grow without end. Past the limit the notices that didn't read
/// go first, oldest first: a payment that couldn't be saved is real money, and none of those
/// is dropped while a notice is left.
public enum PendingPayments {
    public static let limit = 20
    public static let keepDays = 30

    /// What is still waiting at `now`, newest first.
    public static func current(_ list: [PendingPayment], now: Date) -> [PendingPayment] {
        let oldest = now.addingTimeInterval(-TimeInterval(keepDays) * 24 * 3600)
        var seen = Set<UUID>()
        let kept = list.filter { $0.date >= oldest && seen.insert($0.id).inserted }
        // Stable: two that arrived in the same instant keep the order they came in.
        var sorted = kept.enumerated().sorted {
            $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset
        }.map(\.element)
        while sorted.count > limit {
            sorted.remove(at: sorted.lastIndex { $0.kind == .unread } ?? sorted.count - 1)
        }
        return sorted
    }

    /// A good payment was saved at `date` in `merchants` (as sent and as it ended up named):
    /// a notice that brought only a name, from a shop that starts alike and within the two
    /// minutes the two automations take (`CaptureGuard.otherSourceWindow`), was that same
    /// payment and goes by itself. Anything with a figure or a currency stays.
    public static func settling(_ list: [PendingPayment], savedIn merchants: [String], at date: Date) -> [PendingPayment] {
        list.filter { !isSettled($0, by: merchants, at: date) }
    }

    /// Whether a notice is the same payment as one already saved (see `settling`).
    public static func isSettled(_ payment: PendingPayment, by merchants: [String], at date: Date) -> Bool {
        payment.isNameOnly
            && abs(payment.date.timeIntervalSince(date)) <= CaptureGuard.otherSourceWindow
            && merchants.contains { CaptureGuard.shopsAlike(payment.text, $0) }
    }

    public static func adding(_ payment: PendingPayment, to list: [PendingPayment], now: Date) -> [PendingPayment] {
        current(list + [payment], now: now)
    }

    public static func removing(_ id: UUID, from list: [PendingPayment]) -> [PendingPayment] {
        list.filter { $0.id != id }
    }

    /// The list as it is kept (JSON text). One item that doesn't read doesn't empty the rest.
    public static func decode(_ stored: String) -> [PendingPayment] {
        LenientList.decode(PendingPayment.self, from: stored).items
    }

    public static func encode(_ list: [PendingPayment]) -> String {
        list.isEmpty ? "" : LenientList.encode(list)
    }

    /// «1 pago no se pudo guardar», «2 pagos no se pudieron leer»; mixed, «3 pagos sin anotar».
    public static func title(for list: [PendingPayment]) -> String {
        let count = list.count
        let kinds = Set(list.map(\.kind))
        guard kinds.count == 1, let kind = kinds.first else {
            return count == 1 ? "1 pago sin anotar" : "\(count) pagos sin anotar"
        }
        let what = kind == .unread ? "leer" : "guardar"
        return count == 1 ? "1 pago no se pudo \(what)" : "\(count) pagos no se pudieron \(what)"
    }
}
