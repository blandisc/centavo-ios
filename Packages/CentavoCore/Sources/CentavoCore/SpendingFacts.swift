import Foundation

/// An expense, as far as the month's notes care. Keeps this package free of SwiftData.
public struct SpendingRecord: Equatable, Sendable {
    public var amount: Decimal
    public var currencyMarker: String?
    /// The name to say it by (the readable one when there is).
    public var merchant: String
    public var category: String?
    public var date: Date
    /// A fixed expense or one of its copies.
    public var isFixed: Bool

    public init(amount: Decimal, currencyMarker: String? = nil, merchant: String,
                category: String? = nil, date: Date, isFixed: Bool = false) {
        self.amount = amount
        self.currencyMarker = currencyMarker
        self.merchant = merchant
        self.category = category
        self.date = date
        self.isFixed = isFixed
    }
}

/// One thing worth saying about the money, already worked out and already written.
public struct SpendingFact: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// The same charge twice, minutes apart.
        case doubleCharge
        /// A charge that comes every month and isn't marked as fixed.
        case subscription
        /// At this pace the month ends over the budget.
        case projection
        /// A category well above its usual by this day of the month.
        case categoryUp
    }

    public let kind: Kind
    /// Stable while the fact holds, so a note written for it can be kept.
    public let key: String
    /// The sentence, ready to show. The model may reword it, never change its figures.
    public let line: String
    /// The figures the sentence may contain, as written in it.
    public let figures: [String]

    public init(kind: Kind, key: String, line: String, figures: [String]) {
        self.kind = kind
        self.key = key
        self.line = line
        self.figures = figures
    }
}

/// Plain arithmetic over the expenses: what is worth a note. The on-device model can only
/// reword what comes out of here (see `FactCheck`); it never finds facts or does sums.
public enum SpendingFacts {
    /// The notes for `now`, most useful first. Only the primary currency: adding currencies
    /// up would be a lie.
    public static func detect(_ records: [SpendingRecord], now: Date, primary: String,
                              budget: Decimal?, money: (Decimal) -> String,
                              calendar: Calendar = .current) -> [SpendingFact] {
        let mine = records.filter { record in
            let code = CurrencyResolver.isoCode(for: record.currencyMarker, primary: primary)
                ?? record.currencyMarker
            return code == primary && record.date <= now
        }
        return doubleCharges(mine, now: now, money: money)
            + subscriptions(mine, now: now, money: money, calendar: calendar)
            + projection(mine, now: now, budget: budget, money: money, calendar: calendar)
            + categoriesUp(mine, now: now, calendar: calendar)
    }

    /// How far apart two identical charges can be and still look like one charged twice.
    static let doubleChargeWindow: TimeInterval = 2 * 60 * 60

    static func doubleCharges(_ records: [SpendingRecord], now: Date,
                              money: (Decimal) -> String) -> [SpendingFact] {
        let recent = records
            .filter { $0.amount > 0 && !$0.isFixed && now.timeIntervalSince($0.date) <= 3 * 86_400 }
            .sorted { $0.date < $1.date }
        var facts: [SpendingFact] = []
        for (index, record) in recent.enumerated() {
            guard let twin = recent[(index + 1)...].first(where: {
                key($0.merchant) == key(record.merchant) && $0.amount == record.amount
            }), twin.date.timeIntervalSince(record.date) <= doubleChargeWindow else { continue }
            let figure = money(record.amount)
            let id = "doble|\(key(record.merchant))|\(record.amount)"
            guard !facts.contains(where: { $0.key == id }) else { continue }
            facts.append(SpendingFact(
                kind: .doubleCharge, key: id,
                line: "Hay dos cargos de \(figure) en \(record.merchant) con poco tiempo de diferencia. "
                    + "Revisa que no sea un cobro doble.",
                figures: [figure]
            ))
        }
        return facts
    }

    /// One charge a month, about the same amount, for the last two months or more.
    static func subscriptions(_ records: [SpendingRecord], now: Date, money: (Decimal) -> String,
                              calendar: Calendar) -> [SpendingFact] {
        let fixed = Set(records.filter(\.isFixed).map { key($0.merchant) })
        let window = records.filter {
            $0.amount > 0 && now.timeIntervalSince($0.date) <= 100 * 86_400 && !fixed.contains(key($0.merchant))
        }
        let byMerchant = Dictionary(grouping: window) { key($0.merchant) }
        var facts: [SpendingFact] = []
        for (merchantKey, charges) in byMerchant.sorted(by: { $0.key < $1.key }) {
            let sorted = charges.sorted { $0.date < $1.date }
            guard sorted.count >= 2, let latest = sorted.last,
                  now.timeIntervalSince(latest.date) <= 40 * 86_400 else { continue }
            let months = sorted.map { calendar.dateComponents([.year, .month], from: $0.date) }
            guard Set(months).count == sorted.count else { continue }  // one a month, never two
            let monthly = zip(sorted, sorted.dropFirst()).allSatisfy { earlier, later in
                let days = later.date.timeIntervalSince(earlier.date) / 86_400
                return (25...35).contains(days)
            }
            let steady = sorted.allSatisfy { ($0.amount - latest.amount).magnitude <= latest.amount * Decimal(0.05) }
            guard monthly, steady else { continue }
            let figure = money(latest.amount)
            facts.append(SpendingFact(
                kind: .subscription, key: "fijo|\(merchantKey)",
                line: "\(latest.merchant) se cobra cada mes (\(figure)). Márcalo como fijo y se anotará solo.",
                figures: [figure]
            ))
        }
        return facts
    }

    /// From day 7: what's spent so far, spread over the whole month, against the budget.
    static func projection(_ records: [SpendingRecord], now: Date, budget: Decimal?,
                           money: (Decimal) -> String, calendar: Calendar) -> [SpendingFact] {
        guard let budget, budget > 0,
              let days = calendar.range(of: .day, in: .month, for: now)?.count else { return [] }
        let day = calendar.component(.day, from: now)
        guard day >= 7, day < days else { return [] }
        let month = records.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
        let fixed = month.filter(\.isFixed).reduce(Decimal(0)) { $0 + $1.amount }
        let variable = month.filter { !$0.isFixed }.reduce(Decimal(0)) { $0 + $1.amount }
        let projected = whole(fixed + variable / Decimal(day) * Decimal(days))
        let over = projected - budget
        guard over > budget * Decimal(0.05) else { return [] }
        let total = money(projected), extra = money(whole(over))
        return [SpendingFact(
            kind: .projection, key: "ritmo|\(calendar.component(.month, from: now))",
            line: "A este ritmo cierras el mes en \(total), \(extra) arriba del presupuesto.",
            figures: [total, extra]
        )]
    }

    /// A category 30 % or more above the usual for this day of the month (the median of the
    /// three months before, each counted to the same day), and by enough to matter.
    static func categoriesUp(_ records: [SpendingRecord], now: Date, calendar: Calendar) -> [SpendingFact] {
        let day = calendar.component(.day, from: now)
        guard day >= 5 else { return [] }
        func spent(monthsBack: Int) -> [String: (name: String, amount: Decimal)]? {
            guard let month = calendar.date(byAdding: .month, value: -monthsBack, to: now),
                  let interval = calendar.dateInterval(of: .month, for: month),
                  let length = calendar.range(of: .day, in: .month, for: month)?.count else { return nil }
            let cutoff = monthsBack == 0 ? now
                : calendar.date(byAdding: .day, value: min(day, length), to: interval.start) ?? interval.end
            let rows = records.filter { $0.date >= interval.start && $0.date < cutoff }
            if monthsBack > 0, !records.contains(where: { interval.contains($0.date) }) { return nil }
            var totals: [String: (name: String, amount: Decimal)] = [:]
            for row in rows {
                guard let name = row.category?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
                totals[key(name), default: (name, 0)].amount += row.amount
            }
            return totals
        }
        guard let current = spent(monthsBack: 0) else { return [] }
        let before = (1...3).compactMap { spent(monthsBack: $0) }
        guard before.count == 3 else { return [] }  // no history, no "usual"
        let monthTotal = current.values.reduce(Decimal(0)) { $0 + $1.amount }
        var found: [(fact: SpendingFact, delta: Decimal)] = []
        for (categoryKey, sofar) in current where sofar.amount > 0 {
            let usual = before.map { $0[categoryKey]?.amount ?? 0 }.sorted()[1]
            guard usual > 0, sofar.amount >= usual * Decimal(1.3),
                  sofar.amount - usual >= monthTotal * Decimal(0.05) else { continue }
            let percent = Int(NSDecimalNumber(decimal: (sofar.amount / usual - 1) * 100).doubleValue.rounded())
            let figure = "\(percent) %"
            found.append((SpendingFact(
                kind: .categoryUp, key: "sube|\(categoryKey)",
                line: "\(sofar.name) va \(figure) arriba de lo normal a estas alturas del mes.",
                figures: [figure]
            ), sofar.amount - usual))
        }
        return found.sorted { $0.delta > $1.delta }.map(\.fact)
    }

    private static func whole(_ value: Decimal) -> Decimal {
        var input = value, output = Decimal()
        NSDecimalRound(&output, &input, 0, .plain)
        return output
    }

    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// The guard on the model's wording: a note may be rephrased, but every number in it has to
/// be one the app worked out. A sentence with a figure that isn't there is thrown away.
public enum FactCheck {
    public static let maxLength = 180

    public static func accepts(_ text: String, for fact: SpendingFact) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= maxLength else { return false }
        let allowed = Set(numbers(in: fact.line) + fact.figures.flatMap(numbers))
        return numbers(in: clean).allSatisfy(allowed.contains)
    }

    /// Each figure as plain digits: «$1,234.00» → «1234», «40 %» → «40».
    static func numbers(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)*"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            var figure = String(text[range])
            // «.00» and «,00» are no figure of their own.
            if figure.hasSuffix(".00") || figure.hasSuffix(",00") { figure.removeLast(3) }
            return figure.filter(\.isNumber)
        }
    }
}
