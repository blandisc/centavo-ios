import Foundation

/// An expense said in one sentence: «230 de unos tacos ayer, en efectivo».
public struct QuickEntry: Equatable, Sendable {
    /// The amount exactly as said, currency word included («230», «20 dólares»), for
    /// `AmountParser` to read: a number is never made up, only found.
    public var amountText: String
    public var merchant: String?
    public var date: Date
    /// One of the person's payment sources, spelled as they set it up, or «Efectivo».
    public var source: String?

    public init(amountText: String, merchant: String?, date: Date, source: String?) {
        self.amountText = amountText
        self.merchant = merchant
        self.date = date
        self.source = source
    }
}

/// Reads a sentence into an expense, with plain rules: the amount is the number in it, the
/// date comes from «hoy», «ayer», «el viernes», «el 3» or «hace 2 días», the card from «en
/// efectivo» or «con la Nu». What is left is the merchant. It works on every iPhone; the
/// on-device model only improves the merchant and the reading of odd sentences (`refine`).
public enum QuickEntryParser {
    public static func parse(_ sentence: String, sources: [String], now: Date,
                             calendar: Calendar = .current) -> QuickEntry? {
        var words = Words(sentence)
        let date = takeDate(&words, now: now, calendar: calendar) ?? now
        guard let amount = takeAmount(&words) else { return nil }
        let source = takeSource(&words, among: sources)
        return QuickEntry(amountText: amount, merchant: merchant(in: words), date: date, source: source)
    }

    /// What the model read, checked against the sentence: each part is used only when it is
    /// really in what was said, as whole words («45» is not in «450»). The plain reading of
    /// the day and the card wins when it found one: «antes de ayer» must not become «ayer».
    public static func refine(_ base: QuickEntry, sentence: String, amount: String?, merchant: String?,
                              when: String?, payment: String?, sources: [String], now: Date,
                              calendar: Calendar = .current) -> QuickEntry {
        var entry = base
        let said = Words(sentence)
        var plain = said
        let plainDate = takeDate(&plain, now: now, calendar: calendar)
        // The plain amount stands when it was sure (one number, a currency, «de 20»).
        let plainAmountSure = amountChoice(in: plain)?.certain ?? false
        let plainSource = takeSource(&plain, among: sources)
        if !plainAmountSure, let amount, said.contains(amount) {
            var words = Words(amount)
            if let found = takeAmount(&words) { entry.amountText = found }
        }
        if plainDate == nil, let when, said.contains(when) {
            var words = Words(when)
            if let date = takeDate(&words, now: now, calendar: calendar) { entry.date = date }
        }
        if plainSource == nil, let payment, said.contains(payment) {
            var words = Words(payment)
            if let source = takeSource(&words, among: sources) { entry.source = source }
        }
        if let merchant {
            let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let saidWords = Set(MerchantCatalog.tokens(sentence))
            let nameWords = MerchantCatalog.tokens(name)
            // The day or the card is not the place: «Tacos ayer en efectivo» is «Tacos».
            let notAName = notMerchantWords.union(sources.flatMap(MerchantCatalog.tokens))
            if !nameWords.isEmpty, name.count <= 60, nameWords.allSatisfy(saidWords.contains),
               !nameWords.contains(where: { $0.contains(where: \.isNumber) || notAName.contains($0) }) {
                entry.merchant = capitalized(name)
            }
        }
        return entry
    }

    /// Words that say when or how, never where.
    private static let notMerchantWords: Set<String> = Set(weekdays).union([
        "hoy", "ayer", "antier", "anteayer", "hace", "semana", "pasada", "pasado", "dia", "dias",
        "efectivo", "cash", "tarjeta",
    ])

    /// «ayer», «el viernes», «el 3», «hace 2 días»: the day it means, never in the future.
    public static func date(from phrase: String, now: Date, calendar: Calendar = .current) -> Date? {
        var words = Words(phrase)
        return takeDate(&words, now: now, calendar: calendar)
    }

    // MARK: - Pieces

    /// The sentence as words, each with a folded copy to compare and a flag once used.
    struct Words {
        var original: [String]
        var folded: [String]
        var used: [Bool]

        init(_ text: String) {
            original = text.split(whereSeparator: \.isWhitespace)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!¡?¿«»\"()")) }
                .filter { !$0.isEmpty }
            folded = original.map(QuickEntryParser.fold)
            used = original.map { _ in false }
        }

        /// Whether `phrase` is in these words, whole and in order.
        func contains(_ phrase: String) -> Bool {
            let wanted = Words(phrase).folded
            guard !wanted.isEmpty, wanted.count <= folded.count else { return false }
            return (0...(folded.count - wanted.count)).contains { start in
                Array(folded[start..<(start + wanted.count)]) == wanted
            }
        }

        func free(_ index: Int) -> Bool { index >= 0 && index < folded.count && !used[index] }
        func word(_ index: Int) -> String? { free(index) ? folded[index] : nil }
        mutating func use(_ range: ClosedRange<Int>) { for index in range { used[index] = true } }
    }

    private static let weekdays = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"]
    private static let smallNumbers = ["un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4,
                                       "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10]

    private static func takeDate(_ words: inout Words, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        func daysAgo(_ count: Int) -> Date? {
            calendar.date(byAdding: .day, value: -count, to: now)
        }
        for index in words.folded.indices where words.free(index) {
            let word = words.folded[index]
            switch word {
            case "hoy":
                words.use(index...index)
                return now
            case "antier", "anteayer":
                words.use(index...index)
                return daysAgo(2)
            case "ayer":
                // «antes de ayer» is two days.
                if words.word(index - 2) == "antes", words.word(index - 1) == "de" {
                    words.use((index - 2)...index)
                    return daysAgo(2)
                }
                words.use(index...index)
                return daysAgo(1)
            case "hace":
                guard let next = words.word(index + 1),
                      let count = Int(next) ?? smallNumbers[next],
                      let unit = words.word(index + 2), unit.hasPrefix("dia") || unit.hasPrefix("semana"),
                      count <= 60 else { continue }
                words.use(index...(index + 2))
                return daysAgo(unit.hasPrefix("semana") ? count * 7 : count)
            case "semana":
                guard words.word(index + 1) == "pasada" else { continue }
                let start = words.word(index - 1) == "la" ? index - 1 : index
                words.use(start...(index + 1))
                return daysAgo(7)
            default:
                break
            }
            if let weekday = weekdays.firstIndex(of: word) {
                // The last one that already came: «el viernes» said on a Monday is three days ago.
                let todayWeekday = calendar.component(.weekday, from: today) - 1
                let back = (todayWeekday - weekday + 7) % 7
                var start = index
                if let before = words.word(index - 1), ["el", "este"].contains(before) { start = index - 1 }
                var end = index
                if words.word(index + 1) == "pasado" { end = index + 1 }
                words.use(start...end)
                return daysAgo(back)
            }
            // «el 3», «el día 3», «día 3»: this month if it already came, else last month's.
            if word == "el" || word == "dia" {
                var dayIndex = index + 1
                if word == "el", words.word(dayIndex) == "dia" { dayIndex += 1 }
                guard let text = words.word(dayIndex), let day = Int(text), (1...31).contains(day) else { continue }
                words.use(index...dayIndex)
                return dayOfMonth(day, now: now, calendar: calendar)
            }
        }
        return nil
    }

    private static func dayOfMonth(_ day: Int, now: Date, calendar: Calendar) -> Date? {
        let todayDay = calendar.component(.day, from: now)
        let month = day <= todayDay ? now : calendar.date(byAdding: .month, value: -1, to: now) ?? now
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let start = calendar.dateInterval(of: .month, for: month)?.start else { return nil }
        let clamped = min(day, range.count)
        guard let midnight = calendar.date(byAdding: .day, value: clamped - 1, to: start) else { return nil }
        // Same time of day as now, so a past day doesn't land on midnight.
        let time = now.timeIntervalSince(calendar.startOfDay(for: now))
        return midnight.addingTimeInterval(time)
    }

    private static let currencyWords: Set<String> = [
        "peso", "pesos", "dolar", "dolares", "dls", "dlls", "euro", "euros", "usd", "mxn", "eur",
    ]

    /// Words that put the amount right after them: «5 tacos de 20» is 20, «gasté 300 en 2 cosas»
    /// is 300.
    private static let amountLeads: Set<String> = [
        "de", "por", "fue", "fueron", "son", "pague", "gaste", "costo", "costaron", "anota", "apunta",
    ]

    /// The amount: a number with a currency first, then one right after «de», «por», «gasté»…;
    /// with neither, the biggest number, since a count is smaller than a price («3 tacos 60»,
    /// «Farmacia 24 horas 180»). `certain` is false in that last case: the model may know better.
    private static func amountChoice(in words: Words) -> (index: Int, certain: Bool)? {
        var candidates: [(index: Int, value: Decimal)] = []
        for index in words.folded.indices where words.free(index) {
            let word = words.original[index]
            guard word.contains(where: \.isNumber),
                  word.allSatisfy({ $0.isNumber || ".,$".contains($0) }),
                  let parsed = AmountParser.parse(word), parsed.value > 0 else { continue }
            candidates.append((index, parsed.value))
        }
        if let marked = candidates.first(where: { candidate in
            words.original[candidate.index].contains("$")
                || words.word(candidate.index + 1).map(currencyWords.contains) == true
        }) { return (marked.index, true) }
        if let led = candidates.first(where: { words.word($0.index - 1).map(amountLeads.contains) == true }) {
            return (led.index, true)
        }
        guard let biggest = candidates.max(by: { $0.value < $1.value }) else { return nil }
        return (biggest.index, candidates.count == 1)
    }

    private static func takeAmount(_ words: inout Words) -> String? {
        guard let index = amountChoice(in: words)?.index else { return nil }
        if let next = words.word(index + 1), currencyWords.contains(next) {
            words.use(index...(index + 1))
            return words.original[index] + " " + words.original[index + 1]
        }
        words.use(index...index)
        return words.original[index]
    }

    private static func takeSource(_ words: inout Words, among sources: [String]) -> String? {
        let cash = sources.first { fold($0) == "efectivo" } ?? "Efectivo"
        for index in words.folded.indices where words.free(index) {
            if words.folded[index] == "efectivo" || words.folded[index] == "cash" {
                var start = index
                if let before = words.word(index - 1), ["en", "con"].contains(before) { start = index - 1 }
                words.use(start...index)
                return cash
            }
        }
        // «con la Nu», «con mi tarjeta BBVA»: a source they set up, by its own words.
        for index in words.folded.indices where words.word(index) == "con" || words.word(index) == "en" {
            var start = index + 1
            while let filler = words.word(start), ["la", "el", "mi", "tarjeta", "mis"].contains(filler) { start += 1 }
            for source in sources.sorted(by: { $0.count > $1.count }) {
                let wanted = MerchantCatalog.tokens(source)
                guard !wanted.isEmpty, start + wanted.count <= words.folded.count else { continue }
                let found = (0..<wanted.count).allSatisfy { offset in
                    words.free(start + offset)
                        && MerchantCatalog.tokens(words.original[start + offset]) == [wanted[offset]]
                }
                if found {
                    words.use(index...(start + wanted.count - 1))
                    return source
                }
            }
        }
        return nil
    }

    private static let leading: Set<String> = [
        "anota", "anotar", "anotame", "apunta", "apuntar", "apuntame", "gaste", "pague", "compre",
        "fue", "fueron", "son", "de", "en", "por", "unos", "unas", "un", "una", "el", "la", "los", "las",
        "mi", "mis", "que", "y", "con",
    ]
    private static let trailing: Set<String> = ["de", "en", "con", "y", "por", "el", "la", "un", "una"]

    /// What is left once the amount, the date and the card are out.
    private static func merchant(in words: Words) -> String? {
        var left = words.original.indices.filter { words.free($0) }
        while let first = left.first, leading.contains(words.folded[first]) { left.removeFirst() }
        while let last = left.last, trailing.contains(words.folded[last]) { left.removeLast() }
        // «gasolina en Pemex»: a name written with a capital after «en» is the place.
        if let place = left.lastIndex(where: { words.folded[$0] == "en" }), place < left.count - 1,
           words.original[left[place + 1]].first?.isUppercase == true {
            left = Array(left[(place + 1)...])
        }
        guard !left.isEmpty else { return nil }
        return capitalized(left.map { words.original[$0] }.joined(separator: " "))
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
