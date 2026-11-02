import Foundation

/// «¿Lo tienes en Excel?» (2026-11-01): reads what the person's own AI returned from their
/// spreadsheet — a CSV, a pasted table with tabs or a Markdown table — into lines for
/// «Mi dinero». Nothing is guessed: what doesn't read comes back as a problem with its reason,
/// for the review screen to show and the person to fix.
public enum MoneyImport {
    /// What a line is. The raw values match the app's `MoneySubtype`, plus income.
    public enum Kind: String, CaseIterable, Sendable {
        case account = "cuenta", investment = "inversion"
        case card = "tarjeta", loan = "prestamo", otherDebt = "otros"
        case lent = "me_deben", coming = "por_caer"
        case income = "ingreso"

        public var isDebt: Bool { self == .card || self == .loan || self == .otherDebt }
        public var isAsset: Bool { self == .account || self == .investment }
        public var takesRate: Bool { self == .account || self == .investment || self == .card || self == .loan }
    }

    /// One line, as read. `problems` block it until fixed; `warnings` only inform.
    public struct Line: Equatable, Sendable {
        public var row: Int
        public var kind: Kind?
        public var name: String
        public var institution: String
        public var currency: String
        public var amount: Decimal?
        public var yearlyRate: Decimal?
        public var exchange: Decimal?
        public var repeats: Bool?
        public var problems: [String] = []
        public var warnings: [String] = []

        public var isReady: Bool { problems.isEmpty && kind != nil && amount != nil && !name.isEmpty }
    }

    public struct Result: Equatable, Sendable {
        public var lines: [Line] = []
        /// The AI's own notes, the lines that start with `#`.
        public var notes: [String] = []
        /// Exchange rates found, per currency, in the order they came (several when they disagree).
        public var rates: [String: [Decimal]] = [:]
        /// Not a «Mi dinero» file at all; why, in words.
        public var refusal: String?

        public var ready: [Line] { lines.filter(\.isReady) }
        public var toReview: [Line] { lines.filter { !$0.isReady } }
    }

    // MARK: Reading

    public static func parse(_ text: String, main: String) -> Result {
        var result = Result()
        var rows: [(number: Int, text: String)] = []
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (index, raw) in cleaned.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("```") { continue }
            if line.hasPrefix("#") {
                let note = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !note.isEmpty { result.notes.append(note) }
                continue
            }
            rows.append((index + 1, line))
        }

        // The header: the first row that names at least a type and an amount.
        guard let headerAt = rows.firstIndex(where: { row in
            let fields = split(row.text, by: separator(of: row.text)).map(columnName)
            return fields.contains("tipo") && fields.contains("monto")
        }) else {
            let looksLikeExpenses = rows.contains { row in
                let fields = Set(split(row.text, by: separator(of: row.text)).map(fold))
                return fields.contains("fecha") && fields.contains("comercio")
            }
            result.refusal = looksLikeExpenses
                ? "Este archivo es de tus gastos: impórtalo en Ajustes → Importar CSV."
                : "No encontré una tabla con las columnas «tipo» y «monto». Revisa que tu IA haya seguido las instrucciones."
            return result
        }
        let delimiter = separator(of: rows[headerAt].text)
        let columns = split(rows[headerAt].text, by: delimiter).map(columnName)
        func value(_ fields: [String], _ column: String) -> String {
            guard let at = columns.firstIndex(of: column), at < fields.count else { return "" }
            return fields[at].trimmingCharacters(in: .whitespaces)
        }

        var seen = Set<String>()
        for row in rows[(headerAt + 1)...] {
            if delimiter == "|" {
                if !row.text.contains("|") { break }
                if row.text.allSatisfy({ "|:- ".contains($0) }) { continue }
            }
            let fields = split(row.text, by: delimiter)
            // Prose the AI wrote after the table: one field, no separator.
            guard fields.filter({ !$0.isEmpty }).count > 1 else { continue }
            var line = Line(row: row.number, kind: kind(value(fields, "tipo")), name: value(fields, "nombre"),
                            institution: value(fields, "institucion"), currency: "", amount: nil)
            if fields.count > columns.count && delimiter == "," {
                line.problems.append("Trae más columnas que los títulos: ¿un monto con comas? Revísalo.")
            }
            if line.kind == nil {
                let said = value(fields, "tipo")
                line.problems.append(said.isEmpty ? "Le falta el tipo: elige qué es."
                                                  : "No sé qué es «\(said)»: elige qué es.")
            }
            if line.name.isEmpty { line.problems.append("Le falta el nombre.") }

            let code = value(fields, "moneda").uppercased()
            if code.isEmpty {
                line.currency = main
            } else if code.count == 3, code.allSatisfy(\.isLetter) {
                line.currency = code
            } else {
                line.currency = main
                line.problems.append("La moneda «\(code)» no es un código de tres letras (MXN, USD, EUR).")
            }

            read(amount: value(fields, "monto"), into: &line, column: code)
            read(rate: value(fields, "tasa_anual"), into: &line)
            if let rate = decimal(value(fields, "tipo_cambio")), rate > 0, line.currency != main {
                line.exchange = rate
                if !(result.rates[line.currency] ?? []).contains(rate) { result.rates[line.currency, default: []].append(rate) }
            }

            let repeats = value(fields, "repite")
            line.repeats = repeats.isEmpty ? nil : ["si", "yes", "true", "1", "x", "mensual"].contains(fold(repeats))
            if line.kind == .income && line.repeats == false {
                line.kind = .coming
                line.warnings.append("Era un ingreso de una sola vez: lo puse en «por caer».")
            }

            let key = [line.kind?.rawValue ?? "", fold(line.name), fold(line.institution), line.currency].joined(separator: "|")
            if !line.name.isEmpty && !seen.insert(key).inserted {
                line.problems.append("Viene repetida en el archivo.")
            }
            result.lines.append(line)
        }
        if result.lines.isEmpty {
            result.refusal = "La tabla no trae renglones debajo de los títulos."
        }
        return result
    }

    /// The marks an amount may carry: a symbol or a three-letter code. «k», «mil», «M» are not money.
    private static let markers: Set<String> = ["$", "MX$", "US$", "USD$", "€", "£", "¥", "CA$", "C$"]

    private static func read(amount raw: String, into line: inout Line, column: String) {
        guard !raw.isEmpty else { line.problems.append("Le falta el monto."); return }
        // The format asks for a decimal point: «18.125» is eighteen and a bit, never 18,125.
        guard let parsed = AmountParser.parsePointDecimal(raw) else {
            line.problems.append("El monto «\(raw)» no es un número: escríbelo completo, como 25000.")
            return
        }
        if let marker = parsed.currencyMarker {
            let clean = marker.trimmingCharacters(in: .whitespaces)
            let isCode = clean.count == 3 && clean.allSatisfy(\.isUppercase)
            guard markers.contains(clean) || isCode else {
                line.problems.append("El monto «\(raw)» no es un número: escríbelo completo, como 25000.")
                return
            }
            // A code or an unmistakable symbol beside the number says the currency.
            let said: String? = isCode ? clean : ["US$": "USD", "USD$": "USD", "MX$": "MXN", "€": "EUR", "£": "GBP", "CA$": "CAD"][clean]
            if let said {
                if column.isEmpty {
                    line.currency = said
                } else if said != column {
                    line.problems.append("El monto dice \(said) pero la moneda dice \(column).")
                }
            }
        }
        var value = parsed.value
        if value < 0 {
            // Debts come positive; a negative account is an overdraft and stays as it is.
            if line.kind?.isDebt == true || line.kind == .income || line.kind == .lent || line.kind == .coming { value = -value }
        }
        line.amount = value
        // «8333.333»: a division the AI pasted whole. Kept as read, so the review shows it.
        if parsed.hasMoreThanCents {
            line.problems.append("El monto «\(raw)» trae más de dos decimales: déjalo en centavos, como \(BackupNumber.text(MoneyMath.cents(value))).")
        }
    }

    private static func read(rate raw: String, into line: inout Line) {
        let text = raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard var rate = decimal(text), rate >= 0 else {
            line.warnings.append("La tasa «\(raw)» no se leyó; la dejé vacía.")
            return
        }
        guard rate > 0 else { return }
        // Excel keeps 10.5% as 0.105; but 0.5% is real too: asked, not assumed.
        if rate < 1 {
            let read = rate
            rate *= 100
            line.problems.append("¿La tasa es \(BackupNumber.text(rate))%? Venía \(BackupNumber.text(read)); corrígela si era \(BackupNumber.text(read))%.")
        } else if rate > 100 {
            line.problems.append("Una tasa de \(BackupNumber.text(rate))% al año: revísala.")
        }
        line.yearlyRate = rate
    }

    /// A rate or exchange rate: a decimal with point or comma, never thousands.
    static func decimal(_ raw: String) -> Decimal? { MoneyMath.decimal(raw) }

    // MARK: Words

    /// What a «tipo» says, in Spanish or English, with or without accents.
    public static func kind(_ raw: String) -> Kind? {
        let word = fold(raw.filter { $0 != "*" && $0 != "`" }).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        if let exact = Kind(rawValue: word) { return exact }
        let synonyms: [Kind: [String]] = [
            .account: ["cuenta", "cuentas", "ahorro", "banco", "efectivo", "debito", "nomina", "account", "savings", "checking", "cash", "bank"],
            .investment: ["inversion", "inversiones", "fondo", "acciones", "cripto", "etf", "investment", "investments", "stocks", "fund", "crypto", "brokerage"],
            .card: ["tarjeta", "tarjeta_de_credito", "tdc", "credito", "credit_card", "card"],
            .loan: ["prestamo", "credito_auto", "hipoteca", "credito_hipotecario", "loan", "mortgage", "car_loan"],
            .otherDebt: ["otra_deuda", "deuda", "otros", "otro", "debt", "other_debt", "payable"],
            .lent: ["me_deben", "prestamo_otorgado", "prestado", "lent", "receivable", "owed_to_me"],
            .coming: ["por_caer", "por_cobrar", "bono", "aguinaldo", "reembolso", "pending", "upcoming", "bonus"],
            .income: ["ingreso", "ingresos", "sueldo", "salario", "honorarios", "income", "salary", "wage"],
        ]
        return synonyms.first { $0.value.contains(word) }?.key
    }

    /// A column title, folded and mapped to its canonical name.
    static func columnName(_ raw: String) -> String {
        let word = fold(raw).replacingOccurrences(of: " ", with: "_")
        let names: [String: [String]] = [
            "tipo": ["tipo", "type", "categoria", "kind"],
            "nombre": ["nombre", "name", "cuenta", "concepto", "descripcion"],
            "institucion": ["institucion", "banco", "institution", "bank", "emisor"],
            "moneda": ["moneda", "currency", "divisa"],
            "monto": ["monto", "saldo", "amount", "balance", "importe", "valor"],
            "tasa_anual": ["tasa_anual", "tasa", "rendimiento", "interes", "rate", "apy", "apr", "yield"],
            "tipo_cambio": ["tipo_cambio", "tipo_de_cambio", "exchange_rate", "fx", "tc"],
            "repite": ["repite", "recurrente", "repeats", "recurring", "mensual"],
        ]
        return names.first { $0.value.contains(word) }?.key ?? word
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Splitting

    /// The separator a row uses: a Markdown table, a tab, a semicolon or a comma.
    static func separator(of line: String) -> Character {
        if line.hasPrefix("|") || line.filter({ $0 == "|" }).count >= 2 { return "|" }
        if line.contains("\t") { return "\t" }
        return line.filter({ $0 == ";" }).count > line.filter({ $0 == "," }).count ? ";" : ","
    }

    /// Fields of one row; quotes keep a separator inside a field.
    static func split(_ line: String, by separator: Character) -> [String] {
        var text = line
        if separator == "|" {
            text = text.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("|") { text.removeFirst() }
            if text.hasSuffix("|") { text.removeLast() }
        }
        var fields: [String] = [], current = "", quoted = false
        var chars = Array(text)[...]
        while let char = chars.popFirst() {
            if char == "\"" {
                if quoted, chars.first == "\"" { current.append("\""); chars.removeFirst() } else { quoted.toggle() }
            } else if char == separator && !quoted {
                fields.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        // Markdown bold or code around a cell: **cuenta**, `Nu`.
        return fields.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*` ")) }
    }

    // MARK: The instructions for the AI

    public static let header = "tipo,nombre,institucion,moneda,monto,tasa_anual,tipo_cambio,repite"

    public static func instructions(main: String) -> String {
        """
        Convierte mis finanzas al formato de la app Al día. Te paso mi Excel (si no te pasé ningún archivo, pídemelo antes de seguir).

        Escríbeme el resultado como TEXTO en un solo bloque de código, no como archivo para descargar. La primera línea del bloque es exactamente este encabezado:

        \(header)

        Reglas:
        1. Una fila por cada cuenta, inversión, tarjeta, deuda, dinero que me deben e ingreso que se repite cada mes. Usa solo lo más reciente (si hay varios meses, el último).
        2. tipo es uno de estos, escrito exactamente así:
           - cuenta: banco, ahorro, efectivo; dinero mío que puedo usar hoy.
           - inversion: fondos, acciones, cripto; algo que sube y baja de valor.
           - tarjeta: lo que debo hoy en una tarjeta de crédito (no el límite ni el pago mínimo).
           - prestamo: lo que me falta pagar de un crédito (auto, casa, personal).
           - otros: otra cosa que debo (a un familiar, un pago pendiente).
           - me_deben: dinero que presté y me van a regresar.
           - por_caer: dinero que ya gané pero aún no me pagan (bono, aguinaldo, reembolso, un extra).
           - ingreso: lo que me entra cada mes (sueldo, renta que cobro). Solo los que se repiten.
        3. nombre: corto, como aparece en mi Excel («Cajita», «Nómina», «Sueldo»).
        4. institucion: el banco, la tarjeta o el lugar («Nu», «BBVA», «Amex», «GBM»). Vacío si no aplica, como el efectivo.
        5. moneda: código de tres letras (MXN, USD, EUR…). Mi moneda principal es \(main).
        6. monto: número positivo, con punto decimal y sin comas, sin signos y sin abreviar (nada de «k» ni «mil»): 12500.50. Para cuentas, inversiones y lo que me deben, el saldo de hoy; para tarjetas y deudas, lo que debo hoy, también en positivo; para ingresos, cuánto entra al mes.
        7. tasa_anual: en %, solo el número: 10.5 quiere decir 10.5 %, no escribas 0.105. En cuentas e inversiones es el rendimiento al año; en tarjetas y préstamos, el interés al año. Déjala vacía si no viene en mi Excel.
        8. tipo_cambio: solo si la moneda no es \(main) y viene en mi Excel: cuántos \(main) vale 1 unidad (18.25). Si no viene, déjalo vacío; no lo busques ni lo inventes.
        9. repite: «si» en los ingresos. Vacío en lo demás.
        10. No incluyas números de cuenta ni de tarjeta.
        11. No inventes nada. Si una fila no está clara, déjala fuera y, al final del MISMO bloque, escribe una línea que empiece con # diciendo cuál y por qué.
        """
    }
}
