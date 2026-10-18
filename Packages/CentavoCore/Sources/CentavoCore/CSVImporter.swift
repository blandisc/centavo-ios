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

        var result = Result(records: [], skipped: 0)
        for row in rows.dropFirst() {
            func field(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let value = undefused(row[index].trimmingCharacters(in: .whitespaces))
                return value.isEmpty ? nil : value
            }
            guard let dateText = field(date), let parsedDate = parseDate(dateText),
                  let amountText = field(amount),
                  let value = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")),
                  let currencyText = field(currency) else {
                result.skipped += 1
                continue
            }
            result.records.append(ExpenseRecord(
                date: parsedDate, merchant: field(merchant) ?? "Sin comercio", amount: value,
                currency: currencyText, card: field(card), category: field(category)
            ))
        }
        return result
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
}
