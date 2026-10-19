import Foundation

/// What a search typed or dictated asks for: «uber de octubre arriba de 200».
public struct SearchQuery: Equatable, Sendable {
    /// Words that must all appear in the merchant, its readable name, category or card.
    public var words: [String]
    /// A category the words were taken to mean (the model maps «cafecitos» to «Café»).
    public var category: String?
    public var minAmount: Decimal?
    public var maxAmount: Decimal?
    /// The month asked for, the last one of that name that already came.
    public var interval: DateInterval?

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

/// Search the way people say it, with plain rules: month names, «arriba de», «menos de»,
/// and the rest as words to find. Works on every iPhone.
public enum ExpenseSearch {
    public static func query(from text: String, now: Date, calendar: Calendar = .current) -> SearchQuery {
        let words = text.split(whereSeparator: \.isWhitespace)
            .map { fold(String($0)).trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "$"))) }
            .filter { !$0.isEmpty }
        var query = SearchQuery()
        var index = 0
        while index < words.count {
            let word = words[index]
            if let month = months.firstIndex(of: word) {
                query.interval = lastMonth(named: month + 1, now: now, calendar: calendar)
                index += 1
                continue
            }
            if let (bound, length) = bound(at: index, in: words) {
                let amount = AmountParser.parse(words[index + length])?.value
                if bound == .min { query.minAmount = amount } else { query.maxAmount = amount }
                index += length + 1
                continue
            }
            if !stopWords.contains(word) { query.words.append(word) }
            index += 1
        }
        return query
    }

    public static func matches(_ expense: SearchableExpense, _ query: SearchQuery) -> Bool {
        let amount = expense.amount.magnitude
        if let min = query.minAmount, amount <= min { return false }
        if let max = query.maxAmount, amount >= max { return false }
        if let interval = query.interval, !interval.contains(expense.date) { return false }
        if let category = query.category {
            guard let own = expense.category, fold(own) == fold(category) else { return false }
            return true
        }
        let haystack = fold([expense.merchant, expense.readableName, expense.category, expense.card]
            .compactMap { $0 }.joined(separator: " "))
        return query.words.allSatisfy(haystack.contains)
    }

    private enum Bound { case min, max }

    /// «arriba de 200», «más de 200», «menos de 100»: which bound, and how many words
    /// it took before the number.
    private static func bound(at index: Int, in words: [String]) -> (Bound, Int)? {
        let phrases: [([String], Bound)] = [
            (["arriba", "de"], .min), (["mas", "de"], .min), (["mayor", "a"], .min),
            (["mayores", "a"], .min), (["sobre"], .min), (["desde"], .min),
            (["menos", "de"], .max), (["abajo", "de"], .max), (["menor", "a"], .max),
            (["menores", "a"], .max), (["debajo", "de"], .max), (["hasta"], .max),
        ]
        for (phrase, bound) in phrases where index + phrase.count < words.count {
            guard Array(words[index..<(index + phrase.count)]) == phrase,
                  words[index + phrase.count].contains(where: \.isNumber) else { continue }
            return (bound, phrase.count)
        }
        return nil
    }

    private static let months = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                                 "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    private static let stopWords: Set<String> = [
        "de", "del", "en", "el", "la", "los", "las", "mis", "mi", "que", "con", "y", "a", "al",
        "gastos", "gasto", "pagos", "pago", "compras", "lo", "por", "este", "mes", "pesos",
    ]

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
