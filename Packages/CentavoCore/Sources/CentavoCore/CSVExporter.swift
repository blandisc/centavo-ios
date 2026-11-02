import Foundation

/// One expense, flattened for export.
public struct ExpenseRecord: Equatable, Sendable {
    public var date: Date
    public var merchant: String
    public var amount: Decimal
    /// ISO 4217 code when known, otherwise whatever marker Wallet sent.
    public var currency: String
    public var card: String?
    public var category: String?
    /// Whether it counts toward the budget. `amount` is always the real amount.
    public var counts: Bool
    /// Only part of it counts («solo cuenta mi mitad»): how much, as `Expense.countedAmount`
    /// stores it. `nil` when `counts` says it all (all of it, or none).
    public var countedAmount: Decimal?
    /// Why it doesn't count, when it doesn't and someone said.
    public var uncountedReason: UncountedReason?

    public init(date: Date, merchant: String, amount: Decimal,
                currency: String, card: String? = nil, category: String? = nil,
                counts: Bool = true, countedAmount: Decimal? = nil, uncountedReason: UncountedReason? = nil) {
        self.date = date
        self.merchant = merchant
        self.amount = amount
        self.currency = currency
        self.card = card
        self.category = category
        self.counts = counts
        self.countedAmount = countedAmount
        self.uncountedReason = uncountedReason
    }
}

/// Writes expenses as RFC 4180 CSV — the format Numbers, Excel and every
/// spreadsheet on the planet opens without asking questions.
public enum CSVExporter {
    public static let header = ["Fecha", "Comercio", "Monto", "Moneda", "Tarjeta", "Categoría",
                                "Cuenta", "Motivo"]

    /// What «Cuenta» says: whether the expense counts toward the budget. When only part of it
    /// counts, «Cuenta» holds that part as an amount (`600.00`): an older importer reads it as
    /// «Sí», this one gets the part back.
    public static let countsText = "Sí", uncountedText = "No"

    /// Oldest first, so the file reads like a ledger.
    ///
    /// Dates carry their UTC offset and amounts use a dot for decimals, both so a
    /// spreadsheet in any locale reads them the same way. Refunds keep their minus. An
    /// expense that doesn't count keeps its real amount, with «No» under «Cuenta».
    public static func csv(from records: [ExpenseRecord],
                           timeZone: TimeZone = .current) -> String {
        let dateStyle = Date.ISO8601FormatStyle(timeZone: timeZone)
            .timeZoneSeparator(.colon)
        let rows = records.sorted { $0.date < $1.date }.map { record in
            [
                record.date.formatted(dateStyle),
                defused(record.merchant),
                amountText(record.amount),
                defused(record.currency),
                defused(record.card ?? ""),
                defused(record.category ?? ""),
                countText(record),
                record.counts && part(of: record) == nil ? "" : record.uncountedReason?.title ?? "",
            ]
        }
        return ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    /// «Sí», «No», or the part that counts when it is only a part.
    private static func countText(_ record: ExpenseRecord) -> String {
        guard record.counts else { return uncountedText }
        return part(of: record).map(amountText) ?? countsText
    }

    /// The part that counts, when it is neither all nor nothing.
    private static func part(of record: ExpenseRecord) -> Decimal? {
        guard record.counts, let counted = record.countedAmount, counted != 0,
              counted.magnitude < record.amount.magnitude else { return nil }
        return counted
    }

    /// Spreadsheets run a cell that starts with `=`, `+`, `-` or `@` as a formula, and
    /// merchant names come from outside (Wallet, a shared card): `=HYPERLINK(...)` as a shop
    /// would be code running on the owner's machine. A leading apostrophe makes it plain text.
    /// A text that already starts with one gets another, so the importer can always take
    /// exactly one off. Only text columns go through this; amounts are numbers and keep their minus.
    static let defusedStarts = "=+-@\t\r'"

    private static func defused(_ text: String) -> String {
        guard let first = text.unicodeScalars.first,
              defusedStarts.unicodeScalars.contains(first) else { return text }
        return "'" + text
    }

    /// Plain `1234.56`: no grouping, dot decimals, at least two places and every one it has
    /// (`0.125` stays `0.125`: rounding here would change the money on the way back in).
    private static func amountText(_ amount: Decimal) -> String {
        let text = BackupNumber.text(amount)
        guard let point = text.firstIndex(of: ".") else { return text + ".00" }
        return text.distance(from: point, to: text.endIndex) == 2 ? text + "0" : text
    }

    /// Quotes a field only when it needs it, and doubles any quote inside.
    ///
    /// Checked by scalar, not by `Character`: Swift reads a CRLF as one grapheme, so
    /// a `Set<Character>` would miss both a lone `\n` and a real CRLF.
    private static func escape(_ field: String) -> String {
        let needsQuotes = field.unicodeScalars.contains {
            $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n"
        }
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
