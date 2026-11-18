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
    ///
    /// Separated by «;» or tabs it reads too (2026-11-18): a spreadsheet in a region with a
    /// decimal comma saves it that way, and it used to be refused as a file without the header.
    /// With «;» the amounts are read with a decimal comma (`commaDecimal`).
    public static func records(from text: String) throws -> Result {
        // A UTF-8 mark at the start would stick to «Fecha» and the header wouldn't be found.
        let text = text.unicodeScalars.first == "\u{FEFF}" ? String(text.unicodeScalars.dropFirst()) : text
        let delimiter = separator(of: text)
        let rows = parse(text, delimiter: delimiter).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
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
        let commaDecimals = readsWithDecimalComma(rows.dropFirst(), delimiter: delimiter, columns: [amount, counts])
        // Spelled out: a ternary between two of these functions crashed the CI's compiler
        // («failed to produce diagnostic for expression», 2026-11-18).
        let tab: Unicode.Scalar = "\t"
        let number: (String) -> Decimal?
        if commaDecimals {
            number = { Self.commaDecimal($0) }
        } else if delimiter == tab {
            number = { Self.pointDecimal($0) }
        } else {
            number = { Self.number($0) }
        }

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
            // «Cuenta» may hold the part that counts (`600.00`) instead of «Sí» or «No». Only as
            // the exporter writes it, with its decimal point: a bare «1» or an account number
            // from another spreadsheet is not a part.
            let countsText = field(counts)
            let part = countsText.flatMap { $0.contains(".") || (commaDecimals && $0.contains(",")) ? number($0) : nil }
            let counted = !isNo(countsText)
            result.records.append(ExpenseRecord(
                date: parsedDate, merchant: field(merchant) ?? "Sin comercio", amount: value,
                currency: currencyText, card: field(card), category: field(category),
                counts: counted, countedAmount: part,
                uncountedReason: !counted || part != nil ? UncountedReason(text: field(reason)) : nil
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

    /// Undoes the exporter's formula guard: `'=SUM` was `=SUM`, `'\tcmd` was `\tcmd` and
    /// `''Hola` was `'Hola`. Exactly one apostrophe, and only before what the exporter defuses.
    private static func undefused(_ text: String) -> String {
        guard text.hasPrefix("'"), let next = text.dropFirst().unicodeScalars.first,
              CSVExporter.defusedStarts.unicodeScalars.contains(next) else { return text }
        return String(text.dropFirst())
    }

    /// The text of a chosen file, in whatever encoding the spreadsheet saved it (2026-11-18):
    /// Excel's «CSV» is Windows-1252 and its «Unicode» is UTF-16, and both were «No se pudo leer
    /// el archivo». UTF-16 only with its mark: tried blindly, a Windows file of even length reads
    /// as noise. The same order as «Mi dinero»'s import.
    public static func text(from data: Data) -> String? {
        let marked = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        let encodings: [String.Encoding] = marked ? [.utf16] : [.utf8, .windowsCP1252, .isoLatin1]
        return encodings.lazy.compactMap { String(data: data, encoding: $0) }.first
    }

    /// Whether the amounts are written with a decimal comma. With «;», always (a spreadsheet
    /// only saves it so where the comma is the decimal). With a tab, by what the amounts say:
    /// Excel's «Texto Unicode» in a decimal-comma region writes `89,50`, and in Mexico `89.50`.
    /// A comma file is written with quotes around a comma, so it never reads one this way.
    static func readsWithDecimalComma<Rows: Sequence>(_ rows: Rows, delimiter: Unicode.Scalar,
                                                      columns: [Int?]) -> Bool where Rows.Element == [String] {
        if delimiter == ";" { return true }
        guard delimiter == "\t" else { return false }
        let indexes = columns.compactMap { $0 }
        for row in rows {
            for index in indexes where index < row.count {
                let field = row[index].trimmingCharacters(in: .whitespaces)
                if field.range(of: #"\d,\d{1,2}$"#, options: .regularExpression) != nil { return true }
            }
        }
        return false
    }

    /// An amount in a tab file with a decimal point. A lone group of three after a point (`1.234`)
    /// is not guessed: from a tab file it may be a thousand written with a decimal comma's
    /// grouping, and what we write has two decimals. The row is counted as unreadable.
    static func pointDecimal(_ text: String) -> Decimal? {
        if text.range(of: #"^[-−]?\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil { return nil }
        return number(text)
    }

    /// What separates the fields, by the first line with something in it: «;» or a tab when
    /// there are more of them than commas outside quotes, a comma otherwise (what we write).
    static func separator(of text: String) -> Unicode.Scalar {
        var counts: [Unicode.Scalar: Int] = [:]
        var quoted = false
        var hasContent = false
        for c in text.unicodeScalars {
            if c == "\"" { quoted.toggle(); hasContent = true; continue }
            if quoted { continue }
            if c == "\n" || c == "\r" {
                if hasContent { break }
                continue
            }
            if c == "," || c == ";" || c == "\t" {
                counts[c, default: 0] += 1
            } else if !CharacterSet.whitespaces.contains(c) {
                hasContent = true
            }
        }
        let commas = counts[",", default: 0], semicolons = counts[";", default: 0], tabs = counts["\t", default: 0]
        if semicolons > commas && semicolons >= tabs { return ";" }
        if tabs > commas && tabs > semicolons { return "\t" }
        return ","
    }

    /// An amount from a file separated by «;», where the comma is the decimal: `89,50`,
    /// `1.234,56`, `1.234.567`. Also `89.50`, which can only be a decimal point. A lone group
    /// of three after a point (`1.234`) could be either, so it is not guessed: the row is
    /// counted as unreadable.
    static func commaDecimal(_ text: String) -> Decimal? {
        var digits = Substring(text)
        let negative = digits.first == "-" || digits.first == "−"
        if negative { digits = digits.dropFirst() }
        let patterns = [
            #"^\d+(,\d+)?$"#,                          // 89 · 89,50
            #"^[1-9]\d{0,2}(\.\d{3})+,\d+$"#,           // 1.234,56
            #"^[1-9]\d{0,2}(\.\d{3}){2,}$"#,             // 1.234.567
            #"^\d+\.\d{1,2}$"#,                         // 89.50
        ]
        let plain = String(digits)
        guard patterns.contains(where: { plain.range(of: $0, options: .regularExpression) != nil }) else { return nil }
        let normalized: String
        if plain.contains(",") {
            normalized = plain.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if plain.filter({ $0 == "." }).count > 1 {
            normalized = plain.replacingOccurrences(of: ".", with: "")
        } else {
            normalized = plain
        }
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    /// RFC 4180: quoted fields may hold the separator, quotes (doubled) and line breaks.
    private static func parse(_ text: String, delimiter: Unicode.Scalar) -> [[String]] {
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
            if c == delimiter { row.append(field); field = ""; continue }
            switch c {
            case "\"": quoted = true
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
