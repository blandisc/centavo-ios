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
    /// The day the person said it was spent («230 de tacos el 30»), when it isn't the day it
    /// arrived. `date` stays the arrival, which orders the list and ages it out; the sheet
    /// starts on this day. Absent in what earlier versions kept.
    public var spentOn: Date?
    /// A notice that read as a charge whose amount didn't make it (`unread(always: true)`):
    /// money Wallet charged, kept until the person removes it, whatever its text looks like
    /// («American Express México» has no figure). Absent (`nil`) in what earlier versions kept
    /// (independent review, 2026-11-19).
    public var isCharge: Bool?

    public init(id: UUID = UUID(), kind: Kind, text: String, date: Date,
                amount: String? = nil, merchant: String? = nil, card: String? = nil, spentOn: Date? = nil,
                isCharge: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.card = card
        self.spentOn = spentOn
        self.isCharge = isCharge
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
        return PendingPayment(id: id, kind: .unread, text: String(first.prefix(maxText)), date: date,
                              isCharge: always)
    }

    /// A payment that read and couldn't be saved: «$319 en Google». `nil` with nothing to show.
    /// `spentOn`: the day that was said, when one was (see `spentOn`).
    public static func unsaved(amount: String, merchant: String?, card: String?, date: Date,
                               spentOn: Date? = nil, id: UUID = UUID()) -> PendingPayment? {
        // The piece the amount was read from, when the whole payment was connected to «Importe»
        // («American Express México⏎Google⏎MXN 319.00»): its first line, or the first 80 of a long
        // one, lost the figure and «Anotar» opened with no amount (2026-11-18). As it came when
        // nothing reads (a currency with figures that don't, kept all the same).
        let source = CaptureText.figure(in: amount)?.text ?? amount
        let amountLine = clean(source).first.map { String($0.prefix(maxText)) }
        let shop = clean(merchant ?? "").first.map { String($0.prefix(maxText)) }
        let cardName = clean(card ?? "").first.map { String($0.prefix(maxText)) }
        let text: String
        switch (amountLine, shop) {
        case (let amount?, let shop?): text = line(amount: amount, merchant: shop)
        case (let amount?, nil): text = amount
        case (nil, let shop?): text = shop
        case (nil, nil): return nil
        }
        return PendingPayment(id: id, kind: .unsaved, text: text, date: date,
                              amount: amountLine, merchant: shop, card: cardName, spentOn: spentOn)
    }

    /// «$319 en Google», in the language of the screen that shows it.
    public static func line(amount: String, merchant: String) -> String {
        String(localized: "\(amount) en \(merchant)", bundle: .main,
               comment: "Pago pendiente de anotar: el monto y el comercio («$319 en Google»)")
    }

    /// What the person sees, put together when shown (2026-11-18): `text` was written in the
    /// language of the moment it was kept, and after a change of the iPhone's language it read
    /// «$319 en Google» in English. One kept before has its parts, so it is put together too.
    public var display: String {
        guard kind == .unsaved, let amount, let merchant else { return text }
        return Self.line(amount: amount, merchant: merchant)
    }

    /// Only a name arrived, with no figure and no currency («Oxxo»): the one kind of notice a
    /// good payment from the same shop may take away by itself (`PendingPayments.settling`).
    /// One with a figure or a currency is money that didn't read, and only the person removes it.
    public var isNameOnly: Bool {
        kind == .unread && !text.contains(where: \.isNumber) && !WalletNotice.mentionsMoney(text)
    }

    /// Whether it may age out of the list or make room in it: only a notice that brought just a
    /// name and wasn't read as a charge. Anything else is something the capture received and
    /// couldn't write down, and only the person removes it (CLAUDE.md; independent review,
    /// 2026-11-19: a charge whose figure didn't read went after 30 days).
    /// Only what is known not to be a charge: one kept by an earlier version (`nil`) stays, as
    /// a charge would (independent review, 2026-11-19).
    public var mayAgeOut: Bool { isNameOnly && isCharge == false }

    /// What the sheet of a new expense starts with for this payment: all that was read of one
    /// that couldn't be saved; of a notice with no amount, its text as the shop when it looks
    /// like a name. `primary`: the currency a bare «$» stands for.
    public func prefill(primary: String) -> ExpensePrefill {
        var fill = ExpensePrefill(date: spentOn ?? date)
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

/// A Wallet payment that already took a name-only notice as its own (`PendingPayments`): its
/// shops and when they were paired. Kept a couple of minutes, so a payment takes one notice
/// only (2026-11-19).
public struct NoticePairing: Codable, Equatable, Sendable {
    public let shops: [String]
    public let date: Date

    public init(shops: [String], date: Date) {
        self.shops = shops
        self.date = date
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

/// The list of payments waiting to be written down, newest first. Only the notices that brought
/// just a name (`mayAgeOut`) last `keepDays` and make room past `limit`, oldest first. A
/// payment that couldn't be saved (`.unsaved`), a notice with a figure or a currency, and a
/// charge whose amount didn't read (`isCharge`) are real money that Wallet charged: they never
/// age out and never make room, only the person removes them («Anotar» or «Descartar»;
/// 2026-11-18, «un pago nunca se pierde»: a week of a failing store, or a month without opening
/// «Hoy», used to drop them with no warning; 2026-11-19, the notices too).
public enum PendingPayments {
    public static let limit = 20
    public static let keepDays = 30

    /// What is still waiting at `now`, newest first.
    public static func current(_ list: [PendingPayment], now: Date) -> [PendingPayment] {
        let oldest = now.addingTimeInterval(-TimeInterval(keepDays) * 24 * 3600)
        var seen = Set<UUID>()
        let kept = list.filter { payment in
            let fresh = !payment.mayAgeOut || payment.date >= oldest
            return fresh && seen.insert(payment.id).inserted
        }
        // Stable: two that arrived in the same instant keep the order they came in.
        var sorted = kept.enumerated().sorted {
            $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset
        }.map(\.element)
        while sorted.count > limit, let notice = sorted.lastIndex(where: \.mayAgeOut) {
            sorted.remove(at: notice)
        }
        return sorted
    }

    /// A good payment was saved at `date` in `merchants` (as sent and as it ended up named):
    /// a notice that brought only a name, from a shop that starts alike and within the two
    /// minutes the two automations take (`CaptureGuard.otherSourceWindow`), was that same
    /// payment and goes by itself. Anything with a figure or a currency stays.
    ///
    /// One notice at most, the closest in time: one payment comes with one notice, and a
    /// second one from the same shop is another purchase whose amount didn't arrive
    /// (2026-11-19: two purchases at the same Oxxo, and the second was lost with no pending).
    public static func settling(_ list: [PendingPayment], savedIn merchants: [String], at date: Date) -> [PendingPayment] {
        let matching = list.indices.filter { isSettled(list[$0], by: merchants, at: date) }
        guard let closest = matching.min(by: { first, second in
            abs(list[first].date.timeIntervalSince(date)) < abs(list[second].date.timeIntervalSince(date))
        }) else { return list }
        var left = list
        left.remove(at: closest)
        return left
    }

    /// Whether a notice could be the same payment as one saved in `merchants` (see `settling`).
    public static func isSettled(_ payment: PendingPayment, by merchants: [String], at date: Date) -> Bool {
        // Charges too (2026-11-19): every capture keeps its notices as charges, so leaving them
        // out would undo this pairing and every Wallet notice would stay beside its payment.
        payment.isNameOnly
            && abs(payment.date.timeIntervalSince(date)) <= CaptureGuard.otherSourceWindow
            && merchants.contains { CaptureGuard.shopsAlike(payment.text, $0) }
    }

    /// Whether a notice that just arrived is the payment of one of `saved` (the shops of each
    /// Wallet payment saved in the last two minutes) and is not kept. One to one (2026-11-19):
    /// a payment that already took a notice (`paired`) takes no other, so the second purchase
    /// at the same shop whose amount didn't arrive stays pending. With doubt, it is kept.
    public static func isSettled(_ payment: PendingPayment, among saved: [[String]],
                                 paired: [NoticePairing], at date: Date) -> Bool {
        let payments = saved.filter { isSettled(payment, by: $0, at: date) }.count
        let taken = paired.filter { pairing in
            abs(pairing.date.timeIntervalSince(date)) <= CaptureGuard.otherSourceWindow
                && isSettled(payment, by: pairing.shops, at: date)
        }.count
        return payments > taken
    }

    /// The pairings still inside the two minutes at `date`, plus `new` if given: what is kept.
    public static func pairings(_ list: [NoticePairing], adding new: NoticePairing? = nil,
                                at date: Date) -> [NoticePairing] {
        let recent = list.filter { abs($0.date.timeIntervalSince(date)) <= CaptureGuard.otherSourceWindow }
        return recent + (new.map { [$0] } ?? [])
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
            if count == 1 {
                return String(localized: "1 pago sin anotar", bundle: .main,
                              comment: "Hoy: pagos de Wallet que esperan, de los dos tipos")
            }
            return String(localized: "\(count) pagos sin anotar", bundle: .main,
                          comment: "Hoy: pagos de Wallet que esperan, de los dos tipos")
        }
        if kind == .unread {
            if count == 1 {
                return String(localized: "1 pago no se pudo leer", bundle: .main,
                              comment: "Hoy: avisos de Wallet sin monto legible")
            }
            return String(localized: "\(count) pagos no se pudieron leer", bundle: .main,
                          comment: "Hoy: avisos de Wallet sin monto legible")
        }
        if count == 1 {
            return String(localized: "1 pago no se pudo guardar", bundle: .main,
                          comment: "Hoy: pagos que se leyeron y no se pudieron guardar")
        }
        return String(localized: "\(count) pagos no se pudieron guardar", bundle: .main,
                      comment: "Hoy: pagos que se leyeron y no se pudieron guardar")
    }
}
