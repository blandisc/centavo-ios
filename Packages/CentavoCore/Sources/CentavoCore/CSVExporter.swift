import Foundation

/// One expense, flattened for export.
public struct ExpenseRecord: Equatable, Sendable {
    public var date: Date
    public var merchant: String
    public var amount: Decimal
    /// ISO 4217 code when known, otherwise whatever marker Wallet sent.
    public var currency: String
    public var card: String?

    public init(date: Date, merchant: String, amount: Decimal,
                currency: String, card: String? = nil) {
        self.date = date
        self.merchant = merchant
        self.amount = amount
        self.currency = currency
        self.card = card
    }
}

/// Writes expenses as RFC 4180 CSV — the format Numbers, Excel and every
/// spreadsheet on the planet opens without asking questions.
public enum CSVExporter {
    public static let header = ["Fecha", "Comercio", "Monto", "Moneda", "Tarjeta"]

    /// Oldest first, so the file reads like a ledger.
    ///
    /// Dates carry their UTC offset and amounts use a dot for decimals, both so a
    /// spreadsheet in any locale reads them the same way. Refunds keep their minus.
    public static func csv(from records: [ExpenseRecord],
                           timeZone: TimeZone = .current) -> String {
        let dateStyle = Date.ISO8601FormatStyle(timeZone: timeZone)
            .timeZoneSeparator(.colon)
        let rows = records.sorted { $0.date < $1.date }.map { record in
            [
                record.date.formatted(dateStyle),
                record.merchant,
                amountText(record.amount),
                record.currency,
                record.card ?? "",
            ]
        }
        return ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    /// Plain `1234.56`: no grouping, dot decimals, always two places.
    private static func amountText(_ amount: Decimal) -> String {
        amount.formatted(
            .number.precision(.fractionLength(2)).grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
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
