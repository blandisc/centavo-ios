import Foundation

/// What a search typed or dictated asks for: «uber de octubre arriba de 200».
public struct SearchQuery: Equatable, Sendable {
    /// Words that must all appear in the merchant, its readable name, category or card.
    public var words: [String]
    /// A category asked for by name.
    public var category: String?
    public var minAmount: Decimal?
    public var maxAmount: Decimal?
    /// Whether the bounds count themselves: «desde 200» and «hasta 100» do, «más de 200» doesn't.
    public var inclusive = false
    /// The month asked for, the last one of that name that already came; with a year, that
    /// month of that year; a year alone, the whole year.
    public var interval: DateInterval?
    /// The month as it was said: «Don Julio» is a taquería as much as a month.
    public var monthWord: String?
    /// The year asked for («uber octubre 2024», 2026-11-18): before, «2024» was looked for in
    /// the names and the amount, and the months of other years could not be found.
    public var year: Int?

    public init(words: [String] = [], category: String? = nil, minAmount: Decimal? = nil,
                maxAmount: Decimal? = nil, interval: DateInterval? = nil) {
        self.words = words
        self.category = category
        self.minAmount = minAmount
        self.maxAmount = maxAmount
        self.interval = interval
    }

    public var isEmpty: Bool {
        words.isEmpty && category == nil && minAmount == nil && maxAmount == nil && interval == nil
    }
}

/// One expense, as far as a search cares.
public struct SearchableExpense: Equatable, Sendable {
    public var merchant: String
    public var readableName: String?
    public var category: String?
    public var card: String?
    public var amount: Decimal
    public var date: Date

    public init(merchant: String, readableName: String? = nil, category: String? = nil,
                card: String? = nil, amount: Decimal, date: Date) {
        self.merchant = merchant
        self.readableName = readableName
        self.category = category
        self.card = card
        self.amount = amount
        self.date = date
    }
}

/// Search the way people say it, with plain rules: month names, «arriba de», «menos de» (and
/// their English, «october», «over»), and the rest as words to find. Works on every iPhone.
public enum ExpenseSearch {
    public static func query(from text: String, now: Date, calendar: Calendar = .current) -> SearchQuery {
        let words = text.split(whereSeparator: \.isWhitespace)
            .map { fold(String($0)).trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "$"))) }
            .filter { !$0.isEmpty }
        var query = SearchQuery()
        var month: Int?
        var index = 0
        while index < words.count {
            let word = words[index]
            if let named = Self.month(named: word) {
                month = named
                query.monthWord = word
                index += 1
                continue
            }
            if let phrase = bound(at: index, in: words) {
                let length = phrase.words.count
                let amount = AmountParser.parse(words[index + length])?.value
                if phrase.bound == .min { query.minAmount = amount } else { query.maxAmount = amount }
                if phrase.inclusive { query.inclusive = true }
                index += length + 1
                continue
            }
            // A bare year, written as one («2024», not «2,024»). An expense of $2,024 still
            // shows, as a «Don Julio» does for «julio» (`matches`).
            if let said = yearWord(word) {
                query.year = said
                index += 1
                continue
            }
            // «1,250» is how the amount is written, not how it is kept.
            let plain = word.allSatisfy({ $0.isNumber || ",.".contains($0) })
                ? AmountParser.parse(word).map { "\($0.value)" } ?? word : word
            if !stopWords.contains(word) { query.words.append(plain) }
            index += 1
        }
        query.interval = interval(month: month, year: query.year, now: now, calendar: calendar)
        return query
    }

    public static func matches(_ expense: SearchableExpense, _ query: SearchQuery) -> Bool {
        let amount = expense.amount.magnitude
        if let min = query.minAmount, query.inclusive ? amount < min : amount <= min { return false }
        if let max = query.maxAmount, query.inclusive ? amount > max : amount >= max { return false }
        // The amount too, so «230» finds the 230.00 one.
        // The app's own category and «Efectivo» as they are shown too («groceries» finds
        // «Despensa»); in Spanish that is the same name (2026-11-18).
        let filed = [expense.category, expense.card].compactMap { $0 }
        let shown = filed.map { BuiltInName.shown($0) }.filter { !filed.contains($0) }
        let fields: [String?] = [expense.merchant, expense.readableName, expense.category, expense.card]
        var words: [String] = fields.compactMap { $0 }
        words += shown
        words.append("\(amount)")
        let haystack = fold(words.joined(separator: " "))
        // A month name is the month, unless the expense itself is called that («Don Julio»); a
        // year is the year, unless it is the amount («2024» finds the $2,024.00 one).
        let dateWords = [query.monthWord, query.year.map { String($0) }].compactMap { $0 }
        if let interval = query.interval, !interval.contains(expense.date),
           dateWords.isEmpty || !dateWords.allSatisfy(haystack.contains) { return false }
        if let category = query.category {
            // Asked for in the iPhone's language («Groceries»), it is the one stored in Spanish.
            let wanted = fold(BuiltInName.category(category))
            guard let own = expense.category, fold(own) == fold(category) || fold(own) == wanted else { return false }
            return true
        }
        return query.words.allSatisfy(haystack.contains)
    }

    private enum Bound { case min, max }

    /// Words that put a bound on the amount, and whether the bound counts itself: «desde 200»
    /// and «hasta 100» do, «más de 200» doesn't.
    private struct BoundPhrase {
        var words: [String]
        var bound: Bound
        var inclusive = false
    }

    /// In both languages at once, whatever the iPhone's: an iPhone in English searches «over
    /// 500» and «uber october» (2026-11-18); before, those were words to find and found nothing.
    private static let phrases: [BoundPhrase] = [
        BoundPhrase(words: ["arriba", "de"], bound: .min), BoundPhrase(words: ["mas", "de"], bound: .min),
        BoundPhrase(words: ["mayor", "a"], bound: .min), BoundPhrase(words: ["mayores", "a"], bound: .min),
        BoundPhrase(words: ["sobre"], bound: .min), BoundPhrase(words: ["desde"], bound: .min, inclusive: true),
        BoundPhrase(words: ["menos", "de"], bound: .max), BoundPhrase(words: ["abajo", "de"], bound: .max),
        BoundPhrase(words: ["menor", "a"], bound: .max), BoundPhrase(words: ["menores", "a"], bound: .max),
        BoundPhrase(words: ["debajo", "de"], bound: .max), BoundPhrase(words: ["hasta"], bound: .max, inclusive: true),
        BoundPhrase(words: ["over"], bound: .min), BoundPhrase(words: ["above"], bound: .min),
        BoundPhrase(words: ["more", "than"], bound: .min), BoundPhrase(words: ["greater", "than"], bound: .min),
        BoundPhrase(words: ["at", "least"], bound: .min, inclusive: true),
        BoundPhrase(words: ["from"], bound: .min, inclusive: true),
        BoundPhrase(words: ["under"], bound: .max), BoundPhrase(words: ["below"], bound: .max),
        BoundPhrase(words: ["less", "than"], bound: .max),
        BoundPhrase(words: ["up", "to"], bound: .max, inclusive: true),
        BoundPhrase(words: ["at", "most"], bound: .max, inclusive: true),
    ]

    /// «arriba de 200», «más de 200», «over 200»: the bound and the words it took before the
    /// number. Only before a number: «Under Armour» is a shop.
    private static func bound(at index: Int, in words: [String]) -> BoundPhrase? {
        for phrase in phrases where index + phrase.words.count < words.count {
            let end = index + phrase.words.count
            guard Array(words[index..<end]) == phrase.words, words[end].contains(where: \.isNumber) else { continue }
            return phrase
        }
        return nil
    }

    /// Each month's names, Spanish and English (2026-11-18), with the short forms that are not
    /// words of their own: «mar» is the sea, so March is «march» only.
    private static let monthNames: [[String]] = [
        ["enero", "january", "jan"], ["febrero", "february", "feb"], ["marzo", "march"],
        ["abril", "april", "apr"], ["mayo", "may"], ["junio", "june", "jun"], ["julio", "july", "jul"],
        ["agosto", "august", "aug"], ["septiembre", "september", "sep", "sept"],
        ["octubre", "october", "oct"], ["noviembre", "november", "nov"], ["diciembre", "december", "dec"],
    ]

    /// The month a word names, 1 to 12.
    private static func month(named word: String) -> Int? {
        monthNames.firstIndex { $0.contains(word) }.map { $0 + 1 }
    }

    /// Words that ask for nothing, in Spanish and in English («uber in october», 2026-11-18).
    private static let stopWords: Set<String> = [
        "de", "del", "en", "el", "la", "los", "las", "mis", "mi", "que", "con", "y", "a", "al",
        "gastos", "gasto", "pagos", "pago", "compras", "lo", "por", "este", "mes", "pesos",
        "in", "of", "the", "this", "month", "my", "for", "at", "on", "and", "expenses", "expense",
        "payments", "payment", "purchases", "dollars", "from",
    ]

    /// The years a search reads as a year, not as an amount.
    private static let years = 1990...2100

    private static func yearWord(_ word: String) -> Int? {
        guard word.count == 4, word.allSatisfy(\.isASCII), word.allSatisfy(\.isNumber),
              let year = Int(word), years.contains(year) else { return nil }
        return year
    }

    /// That month of that year; the last one of that name that already came without a year; the
    /// whole year without a month.
    private static func interval(month: Int?, year: Int?, now: Date, calendar: Calendar) -> DateInterval? {
        switch (month, year) {
        case let (month?, year?):
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            return calendar.dateInterval(of: .month, for: date)
        case let (month?, nil):
            return lastMonth(named: month, now: now, calendar: calendar)
        case let (nil, year?):
            guard let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
            return calendar.dateInterval(of: .year, for: date)
        case (nil, nil):
            return nil
        }
    }

    private static func lastMonth(named month: Int, now: Date, calendar: Calendar) -> DateInterval? {
        let current = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now) - (month > current ? 1 : 0)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        return calendar.dateInterval(of: .month, for: date)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
