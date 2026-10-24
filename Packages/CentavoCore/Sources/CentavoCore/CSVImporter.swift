import Foundation

/// Reads back the CSV that `CSVExporter` writes, so the expenses survive a lost phone or a
/// reinstall even without iCloud.
public enum CSVImporter {
    public struct Result: Equatable, Sendable {
        public var records: [ExpenseRecord]
        /// Rows that could not be read (bad date or amount). Never guessed.
        public var skipped: Int
    }

    public enum Failure: Error, Equatable {
        /// The first row is not the header Al día writes.
        case notOurFile
    }

    /// Columns are found by their header name, so a file whose columns were reordered in a
    /// spreadsheet still reads. Blank lines are ignored.
    public static func records(from text: String) throws -> Result {
        let rows = parse(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = rows.first else { throw Failure.notOurFile }
        let names = header.map { $0.trimmingCharacters(in: .whitespaces) }
        func column(_ name: String) -> Int? { names.firstIndex(of: name) }
        guard let date = column("Fecha"), let merchant = column("Comercio"),
              let amount = column("Monto"), let currency = column("Moneda") else {
            throw Failure.notOurFile
        }
        let card = column("Tarjeta"), category = column("Categoría")
        // Added later: a file from before has neither, and everything in it counts.
        let counts = column("Cuenta"), reason = column("Motivo")

        var result = Result(records: [], skipped: 0)
        for row in rows.dropFirst() {
            func field(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let value = undefused(row[index].trimmingCharacters(in: .whitespaces))
                return value.isEmpty ? nil : value
            }
            guard let dateText = field(date), let parsedDate = parseDate(dateText),
                  let amountText = field(amount),
                  let value = number(amountText),
                  let currencyText = field(currency) else {
                result.skipped += 1
                continue
            }
            result.records.append(ExpenseRecord(
                date: parsedDate, merchant: field(merchant) ?? "Sin comercio", amount: value,
                currency: currencyText, card: field(card), category: field(category),
                counts: !isNo(field(counts)),
                uncountedReason: isNo(field(counts)) ? UncountedReason(text: field(reason)) : nil
            ))
        }
        return result
    }

    /// «No» under «Cuenta». Anything else (blank, «Sí», a typo) counts, as it did before the
    /// column existed: leaving an expense out of the budget is never a guess.
    private static func isNo(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            == CSVExporter.uncountedText.lowercased()
    }

    /// The exporter's dates (`2026-10-17T15:52:11-06:00`), with or without fractions.
    private static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions.insert(.withFractionalSeconds)
        return fractional.date(from: text)
    }

    /// Undoes the exporter's formula guard: `'=SUM` was `=SUM`.
    private static func undefused(_ text: String) -> String {
        guard text.hasPrefix("'"), let next = text.dropFirst().unicodeScalars.first,
              "=+-@".unicodeScalars.contains(next) else { return text }
        return String(text.dropFirst())
    }

    /// RFC 4180: quoted fields may hold commas, quotes (doubled) and line breaks.
    private static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var scalars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return scalars.next()
        }
        while let c = next() {
            if quoted {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { quoted = false; pending = n }
                    } else { quoted = false }
                } else {
                    field.unicodeScalars.append(c)
                }
                continue
            }
            switch c {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\r":
                if let n = next(), n != "\n" { pending = n }
                row.append(field); rows.append(row); row = []; field = ""
            case "\n": row.append(field); rows.append(row); row = []; field = ""
            default: field.unicodeScalars.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Only a number: "12abc" is a broken row, not 12. A spreadsheet may have re-saved it
    /// with grouping ("1,234.56"), which `AmountParser` reads.
    static func number(_ text: String) -> Decimal? {
        // Our own export: a plain decimal, read exactly as written.
        if text.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil {
            return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        }
        guard text.range(of: #"^[-−]?[\d.,]+$"#, options: .regularExpression) != nil else { return nil }
        return AmountParser.parse(text)?.value
    }
}
