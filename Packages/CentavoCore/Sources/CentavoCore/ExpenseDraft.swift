import Foundation

/// What the sheet of a new expense held when the app went to the background (2026-11-19): iOS
/// may close the app while it is away, and what was typed (half an amount, a merchant) was gone
/// when it came back. Kept on this iPhone only, never in the backup nor in iCloud; it goes on
/// «Guardar», on «Cancelar» or «Descartar». Never for an expense already saved: that one is in
/// the store.
public struct ExpenseDraft: Codable, Equatable, Sendable {
    /// As the amount field writes it: «1,234.5».
    public var amountText: String
    /// ISO code.
    public var currency: String
    public var merchant: String
    public var card: String
    public var category: String
    /// The category came from the merchant, not picked: another merchant still changes it.
    public var categoryAutofilled: Bool
    /// The date picked; `nil` when it was left alone, so it is the moment of «Guardar».
    public var date: Date?
    /// `date` is only the one proposed for the month being browsed (its last second).
    public var dateProposed: Bool
    public var isRefund: Bool
    public var counts: Bool
    /// `UncountedReason`'s raw value.
    public var reason: String
    public var repeats: Bool
    /// `RepeatRule.stored`: `nil` is monthly.
    public var rule: String?
    /// «Más detalles» was open.
    public var showsDetails: Bool

    public init(amountText: String = "", currency: String, merchant: String = "", card: String = "",
                category: String = "", categoryAutofilled: Bool = false, date: Date? = nil,
                dateProposed: Bool = false, isRefund: Bool = false, counts: Bool = true,
                reason: String = UncountedReason.reimbursed.rawValue, repeats: Bool = false,
                rule: String? = nil, showsDetails: Bool = false) {
        self.amountText = amountText
        self.currency = currency
        self.merchant = merchant
        self.card = card
        self.category = category
        self.categoryAutofilled = categoryAutofilled
        self.date = date
        self.dateProposed = dateProposed
        self.isRefund = isRefund
        self.counts = counts
        self.reason = reason
        self.repeats = repeats
        self.rule = rule
        self.showsDetails = showsDetails
    }

    /// Why the expense doesn't count; anything unreadable is the default.
    public var uncountedReason: UncountedReason { UncountedReason(rawValue: reason) ?? .reimbursed }
    public var repeatRule: RepeatRule { RepeatRule(stored: rule) }

    /// The date the sheet opens with: only one picked, and only while it is in the month on
    /// screen (`visible`, what «+» proposes for). One only proposed is never taken back: «+» in
    /// October left the 31st at 23:59, the app reopened in November and «Guardar» sent the
    /// expense to October, out of view (2026-11-19). `nil`: the sheet keeps its own.
    public func restoredDate(visible: Date, calendar: Calendar = .current) -> Date? {
        guard let date, !dateProposed else { return nil }
        guard calendar.isDate(date, equalTo: visible, toGranularity: .month) else { return nil }
        return date
    }

    /// As kept in `UserDefaults`: JSON text.
    public var encoded: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `nil` for nothing kept, or for what doesn't read (an older or broken draft is let go:
    /// it is only what was being typed, never a saved expense).
    public static func decode(_ stored: String?) -> ExpenseDraft? {
        guard let stored, !stored.isEmpty, let data = stored.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ExpenseDraft.self, from: data)
    }
}
