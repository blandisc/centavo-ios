import Foundation

/// An expense said in one sentence: «230 de unos tacos ayer, en efectivo».
public struct QuickEntry: Equatable, Sendable {
    /// The amount exactly as said, currency word included («230», «20 dólares»), for
    /// `AmountParser` to read: a number is never made up, only found.
    public var amountText: String
    public var merchant: String?
    /// The day said, or now when none was.
    public var date: Date
    /// Whether the sentence named a day («ayer», «el 3»). Without one, `date` is only now: the
    /// expense sheet keeps the date it already had (the month being browsed, one picked by
    /// hand) instead of moving it to today (2026-11-18).
    public var daySaid: Bool
    /// One of the person's payment sources, spelled as they set it up, or «Efectivo».
    public var source: String?

    public init(amountText: String, merchant: String?, date: Date, source: String?, daySaid: Bool = false) {
        self.amountText = amountText
        self.merchant = merchant
        self.date = date
        self.daySaid = daySaid
        self.source = source
    }
}

/// Reads a sentence into an expense, with plain rules: the amount is the number in it, the
/// date comes from «hoy», «ayer», «el viernes», «el 3», «el 15 de septiembre» or «hace 2 días»,
/// the card from «en efectivo» or «con la Nu». What is left is the merchant. It works on every
/// iPhone; the on-device model only improves the merchant and the reading of odd sentences
/// (`refine`). It also reads the English the app shows as its example («230 for tacos
/// yesterday, cash»), in both languages at once (2026-11-18): an iPhone in English promised the
/// day and saved «For tacos yesterday» today.
public enum QuickEntryParser {
    public static func parse(_ sentence: String, sources: [String], now: Date,
                             calendar: Calendar = .current) -> QuickEntry? {
        var words = Words(sentence)
        let said = takeDate(&words, now: now, calendar: calendar)
        guard let amount = takeAmount(&words) else { return nil }
        let source = takeSource(&words, among: sources)
        return QuickEntry(amountText: amount, merchant: merchant(in: words), date: said ?? now, source: source,
                          daySaid: said != nil)
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
            if let date = takeDate(&words, now: now, calendar: calendar) {
                entry.date = date
                entry.daySaid = true
            }
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
    private static let notMerchantWords: Set<String> = Set(weekdays).union(englishWeekdays).union([
        "hoy", "ayer", "antier", "anteayer", "hace", "semana", "pasada", "pasado", "dia", "dias",
        "efectivo", "cash", "tarjeta", "today", "yesterday", "ago", "week",
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
            original = Words.symbolAfterFigure(text.split(whereSeparator: \.isWhitespace))
                .flatMap(Words.spellingEuro)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!¡?¿«»\"()")) }
                .filter { !$0.isEmpty }
            folded = original.map(QuickEntryParser.fold)
            used = original.map { _ in false }
        }

        /// «12,50€», «€12,50» and a lone «€» as «12,50 euros»: the symbol read as the word, so
        /// the amount is found and its currency kept (2026-11-18: «12,50€» had no amount, and
        /// «12,50 €» was saved in the main currency).
        static func spellingEuro(_ word: Substring) -> [Substring] {
            guard word.contains("€") else { return [word] }
            let rest = String(word.filter { $0 != "€" })
            return rest.isEmpty ? ["euros"] : [Substring(rest), "euros"]
        }

        /// «€ 12,50» as «12,50 €»: the amount only looks for its currency in the word after it.
        static func symbolAfterFigure(_ words: [Substring]) -> [Substring] {
            var words = words
            var index = 0
            while index + 1 < words.count {
                if words[index].allSatisfy({ $0 == "€" }), words[index + 1].contains(where: \.isNumber) {
                    words.swapAt(index, index + 1)
                    index += 2
                } else {
                    index += 1
                }
            }
            return words
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
    private static let englishWeekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let englishNumbers = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                                         "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]

    /// Each month's names after a day («el 15 de sept.», «the 3rd of May»), Spanish and English.
    private static let monthNames: [[String]] = [
        ["enero", "ene", "january", "jan"], ["febrero", "feb", "february"], ["marzo", "mar", "march"],
        ["abril", "abr", "april", "apr"], ["mayo", "may"], ["junio", "jun", "june"], ["julio", "jul", "july"],
        ["agosto", "ago", "august", "aug"], ["septiembre", "setiembre", "sep", "sept", "set", "september"],
        ["octubre", "oct", "october"], ["noviembre", "nov", "november"], ["diciembre", "dic", "december", "dec"],
    ]
    /// The months that can come before their day («September 15»): the whole name, in English.
    private static let englishMonths = ["january", "february", "march", "april", "may", "june", "july",
                                        "august", "september", "october", "november", "december"]

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
            case "today":
                words.use(index...index)
                return now
            case "yesterday":
                // «the day before yesterday» is two days.
                if words.word(index - 2) == "day", words.word(index - 1) == "before" {
                    let start = words.word(index - 3) == "the" ? index - 3 : index - 2
                    words.use(start...index)
                    return daysAgo(2)
                }
                words.use(index...index)
                return daysAgo(1)
            case "ago":
                // «3 days ago», «two weeks ago», «a week ago».
                guard let unit = words.word(index - 1), unit.hasPrefix("day") || unit.hasPrefix("week"),
                      let said = words.word(index - 2), let count = Int(said) ?? englishNumbers[said],
                      count <= 60 else { continue }
                words.use((index - 2)...index)
                return daysAgo(unit.hasPrefix("week") ? count * 7 : count)
            case "week":
                guard words.word(index - 1) == "last" else { continue }
                words.use((index - 1)...index)
                return daysAgo(7)
            default:
                break
            }
            if let weekday = weekdays.firstIndex(of: word) ?? englishWeekdays.firstIndex(of: word) {
                // The last one that already came: «el viernes» said on a Monday is three days ago.
                let todayWeekday = calendar.component(.weekday, from: today) - 1
                var back = (todayWeekday - weekday + 7) % 7
                let before = words.word(index - 1)
                // «last Friday» said on a Friday is a week ago.
                if before == "last", back == 0 { back = 7 }
                var start = index
                if let before, ["el", "este", "on", "this", "last"].contains(before) { start = index - 1 }
                var end = index
                if words.word(index + 1) == "pasado" { end = index + 1 }
                words.use(start...end)
                return daysAgo(back)
            }
            // «el 3», «el día 3», «día 3»: this month if it already came, else the last month that
            // has it. «el 15 de septiembre»: that month (2026-11-18: «de septiembre» was left in
            // the name and the expense went to this month).
            if word == "el" || word == "dia" {
                var dayIndex = index + 1
                if word == "el", words.word(dayIndex) == "dia" { dayIndex += 1 }
                guard let text = words.word(dayIndex), let day = Int(text), (1...31).contains(day) else { continue }
                if let named = Self.month(after: dayIndex, in: words) {
                    words.use(index...named.end)
                    return Self.day(day, of: named.month, year: named.year, now: now, calendar: calendar)
                }
                words.use(index...dayIndex)
                return dayOfMonth(day, now: now, calendar: calendar)
            }
            // «the 3rd», «on the 15th of September»: an ordinal is a day, never an amount.
            if let day = ordinalDay(word) {
                var start = index
                if words.word(start - 1) == "the" { start -= 1 }
                if words.word(start - 1) == "on" { start -= 1 }
                if let named = Self.month(after: index, in: words) {
                    words.use(start...named.end)
                    return Self.day(day, of: named.month, year: named.year, now: now, calendar: calendar)
                }
                words.use(start...index)
                return dayOfMonth(day, now: now, calendar: calendar)
            }
            // «September 15», «on May 3rd». A bare number after the month is the day only when
            // another number is the amount: «tacos May 20» is $20.
            if let month = englishMonths.firstIndex(of: word), let text = words.word(index + 1),
               let day = ordinalDay(text) ?? plainDay(text),
               ordinalDay(text) != nil || hasNumber(besides: index + 1, in: words) {
                let start = words.word(index - 1) == "on" ? index - 1 : index
                words.use(start...(index + 1))
                return Self.day(day, of: month + 1, year: nil, now: now, calendar: calendar)
            }
        }
        return nil
    }

    /// «3rd», «21st», «15th»: the day it names.
    private static func ordinalDay(_ word: String) -> Int? {
        guard word.count > 2, ["st", "nd", "rd", "th"].contains(String(word.suffix(2))),
              let day = Int(word.dropLast(2)) else { return nil }
        return (1...31).contains(day) ? day : nil
    }

    private static func plainDay(_ word: String) -> Int? {
        guard let day = Int(word), (1...31).contains(day) else { return nil }
        return day
    }

    /// Whether a free word other than `index` has a figure in it.
    private static func hasNumber(besides index: Int, in words: Words) -> Bool {
        words.folded.indices.contains { other in
            other != index && words.free(other) && words.folded[other].contains(where: \.isNumber)
        }
    }

    /// «de septiembre», «de sept. de 2025», «of May» right after the day at `index`: the month,
    /// the year if said, and the last of their words.
    private static func month(after index: Int, in words: Words) -> (month: Int, year: Int?, end: Int)? {
        guard let joiner = words.word(index + 1), joiner == "de" || joiner == "of",
              let name = words.word(index + 2),
              let month = monthNames.firstIndex(where: { $0.contains(name) }) else { return nil }
        if words.word(index + 3) == "de", let text = words.word(index + 4), text.count == 4,
           let year = Int(text), (1990...2100).contains(year) {
            return (month + 1, year, index + 4)
        }
        return (month + 1, nil, index + 2)
    }

    /// That day of that month, of the year said or else the last one in which it already came.
    /// A day the month doesn't have («31 de septiembre») or one still to come is no day at all:
    /// the expense keeps today rather than land somewhere it wasn't.
    private static func day(_ day: Int, of month: Int, year: Int?, now: Date, calendar: Calendar) -> Date? {
        let thisYear = calendar.component(.year, from: now)
        let thisMonth = calendar.component(.month, from: now)
        let later = month > thisMonth || (month == thisMonth && day > calendar.component(.day, from: now))
        let parts = DateComponents(year: year ?? (later ? thisYear - 1 : thisYear), month: month, day: 1)
        guard let first = calendar.date(from: parts),
              let length = calendar.range(of: .day, in: .month, for: first)?.count, day <= length,
              let midnight = calendar.date(byAdding: .day, value: day - 1, to: first) else { return nil }
        let date = midnight.addingTimeInterval(timeOfDay(now, calendar: calendar))
        return date <= now ? date : nil
    }

    private static func dayOfMonth(_ day: Int, now: Date, calendar: Calendar) -> Date? {
        let todayDay = calendar.component(.day, from: now)
        // «el 31» said on 5 March is 31 January, not February cut to the 28th (2026-11-18).
        let first = day <= todayDay ? 0 : 1
        for back in first...12 {
            guard let month = calendar.date(byAdding: .month, value: -back, to: now),
                  let range = calendar.range(of: .day, in: .month, for: month),
                  let start = calendar.dateInterval(of: .month, for: month)?.start else { return nil }
            guard day <= range.count else { continue }
            guard let midnight = calendar.date(byAdding: .day, value: day - 1, to: start) else { return nil }
            return midnight.addingTimeInterval(timeOfDay(now, calendar: calendar))
        }
        return nil
    }

    /// Same time of day as now, so a past day doesn't land on midnight.
    private static func timeOfDay(_ now: Date, calendar: Calendar) -> TimeInterval {
        now.timeIntervalSince(calendar.startOfDay(for: now))
    }

    private static let currencyWords: Set<String> = Set(spelledCurrencies.keys).union([
        "peso", "pesos", "dolar", "dolares", "dls", "dlls", "euro", "euros", "usd", "mxn", "eur",
    ])

    /// Currency words in English, kept as the code the rest of the app reads: «20 dollars» is
    /// USD, as «20 dólares» is (2026-11-18). «dollars» alone was a word of the merchant.
    private static let spelledCurrencies: [String: String] = [
        "dollar": "USD", "dollars": "USD", "buck": "USD", "bucks": "USD",
    ]

    /// Words that put the amount right after them: «5 tacos de 20» is 20, «gasté 300 en 2 cosas»
    /// is 300.
    private static let amountLeads: Set<String> = [
        "de", "por", "fue", "fueron", "son", "pague", "gaste", "costo", "costaron", "anota", "apunta",
        "for", "spent", "paid", "cost", "costs",
    ]

    /// «2 mil», «1.5 millones»: the word multiplies the number before it.
    private static let multipliers: [String: Decimal] = ["mil": 1_000, "millon": 1_000_000, "millones": 1_000_000]

    /// A number as said, maybe with «mil» or «millones» after it (and «2 mil 500»): where it
    /// starts and ends among the words, and what it is worth.
    private struct Figure {
        var index: Int
        var end: Int
        var value: Decimal
        /// Said with a word that multiplies it: the text to keep is the value, not the digits.
        var scaled: Bool
    }

    private static func figure(at index: Int, in words: Words) -> Figure? {
        let word = words.original[index]
        guard word.contains(where: \.isNumber),
              word.allSatisfy({ $0.isNumber || ".,$".contains($0) }),
              let parsed = AmountParser.parse(word), parsed.value > 0 else { return nil }
        var figure = Figure(index: index, end: index, value: parsed.value, scaled: false)
        guard let next = words.word(index + 1), let times = multipliers[next] else { return figure }
        figure.value *= times
        figure.end = index + 1
        figure.scaled = true
        // «2 mil 500»: what comes after the thousands, when it fits under them.
        if times == 1_000, let rest = words.word(index + 2), rest.allSatisfy(\.isNumber),
           let more = Decimal(string: rest), more < 1_000 {
            figure.value += more
            figure.end = index + 2
        }
        // Past `AmountParser`'s twelve digits it is not a price anyone said.
        guard figure.value < 1_000_000_000_000 else { return nil }
        return figure
    }

    /// Words after a number that say what it counts is not: joiners, days, currencies.
    private static let notCounted: Set<String> = leading.union(trailing).union(notMerchantWords).union(englishArticles)
        .union(currencyWords).union(multipliers.keys).union(["para", "del", "al", "a"])

    /// «4 personas», «3 tacos»: a number followed by the thing it counts.
    private static func isCount(_ figure: Figure, in words: Words) -> Bool {
        guard !figure.scaled, let next = words.word(figure.end + 1) else { return false }
        return next.count >= 3 && next.allSatisfy(\.isLetter) && !notCounted.contains(next)
    }

    /// The amount: a number with a currency first, then one right after «de», «por», «gasté»…;
    /// with neither, the biggest number, since a count is smaller than a price («3 tacos 60»,
    /// «Farmacia 24 horas 180»). `certain` is false in that last case: the model may know better.
    /// A number after «de» that counts something («Cena de 4 personas 1200») is not led when
    /// there is another number to take.
    private static func amountChoice(in words: Words) -> (figure: Figure, certain: Bool)? {
        var candidates: [Figure] = []
        var index = 0
        while index < words.folded.count {
            if words.free(index), let figure = figure(at: index, in: words) {
                candidates.append(figure)
                index = figure.end + 1
            } else {
                index += 1
            }
        }
        if let marked = candidates.first(where: { candidate in
            words.original[candidate.index].contains("$")
                || words.word(candidate.end + 1).map(currencyWords.contains) == true
        }) { return (marked, true) }
        if let led = candidates.first(where: { candidate in
            words.word(candidate.index - 1).map(amountLeads.contains) == true
                && !(candidates.count > 1 && isCount(candidate, in: words))
        }) {
            return (led, true)
        }
        guard let biggest = candidates.max(by: { $0.value < $1.value }) else { return nil }
        return (biggest, candidates.count == 1)
    }

    private static func takeAmount(_ words: inout Words) -> String? {
        guard let figure = amountChoice(in: words)?.figure else { return nil }
        // «2 mil» is kept as 2000: `AmountParser` reads digits, not words.
        let said = figure.scaled ? BackupNumber.text(figure.value) : words.original[figure.index]
        if let next = words.word(figure.end + 1), currencyWords.contains(next) {
            words.use(figure.index...(figure.end + 1))
            return said + " " + (spelledCurrencies[next] ?? words.original[figure.end + 1])
        }
        words.use(figure.index...figure.end)
        return said
    }

    private static func takeSource(_ words: inout Words, among sources: [String]) -> String? {
        let cash = sources.first { fold($0) == "efectivo" } ?? "Efectivo"
        for index in words.folded.indices where words.free(index) {
            if words.folded[index] == "efectivo" || words.folded[index] == "cash" {
                var start = index
                if let before = words.word(index - 1), ["en", "con", "in", "with"].contains(before) { start = index - 1 }
                words.use(start...index)
                return cash
            }
        }
        // «con la Nu», «con mi tarjeta BBVA»: a source they set up, by its own words.
        for index in words.folded.indices where words.word(index).map(sourceLeads.contains) == true {
            var start = index + 1
            while let filler = words.word(start), sourceFillers.contains(filler) { start += 1 }
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

    /// «con la Nu», «with my Nu»: the words before a card, and the ones between.
    private static let sourceLeads: Set<String> = ["con", "en", "with", "on"]
    private static let sourceFillers: Set<String> = ["la", "el", "mi", "tarjeta", "mis", "my", "the"]

    private static let leading: Set<String> = englishLeading.union([
        "anota", "anotar", "anotame", "apunta", "apuntar", "apuntame", "gaste", "pague", "compre",
        "fue", "fueron", "son", "de", "en", "por", "unos", "unas", "un", "una", "el", "la", "los", "las",
        "mi", "mis", "que", "y", "con",
    ])
    /// «230 for tacos», «spent 80 on a coffee» (2026-11-18).
    private static let englishLeading: Set<String> = [
        "for", "on", "at", "with", "in", "of", "spent", "paid", "bought", "i",
    ]
    /// «for the tacos», «on a coffee»: an article goes only after one of those English words, so
    /// a shop that starts with one («The Home Depot») keeps its name.
    private static let englishArticles: Set<String> = ["the", "a", "an", "my", "some"]
    private static let trailing: Set<String> = [
        "de", "en", "con", "y", "por", "el", "la", "un", "una",
        "for", "on", "at", "with", "in", "the", "an", "of", "and",
    ]

    /// What is left once the amount, the date and the card are out.
    private static func merchant(in words: Words) -> String? {
        var left = words.original.indices.filter { words.free($0) }
        var english = false
        while let first = left.first {
            let word = words.folded[first]
            // «for a burrito»: «a» goes only after English, «a» in Spanish is not an article.
            let article = english && englishArticles.contains(word)
            guard leading.contains(word) || article else { break }
            english = englishLeading.contains(word) || article
            left.removeFirst()
        }
        while let last = left.last, trailing.contains(words.folded[last]) { left.removeLast() }
        // «gasolina en Pemex», «coffee at Starbucks»: a name written with a capital after «en» is
        // the place.
        if let place = left.lastIndex(where: { ["en", "at"].contains(words.folded[$0]) }), place < left.count - 1,
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
