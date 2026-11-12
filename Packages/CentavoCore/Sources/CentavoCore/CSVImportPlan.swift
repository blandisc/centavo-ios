import Foundation

/// What importing a CSV would do with each row, before anything is saved (2026-11-11).
///
/// An old export loaded after a card was renamed or a merchant's name corrected used to come
/// in again: the row no longer read the same as the expense it came from. Now each row is one
/// of three things, and the doubtful ones are asked about, never added in silence.
public enum CSVImportPlan {
    /// An expense already in the app, as far as telling repeats apart needs.
    public struct Existing: Sendable {
        public var date: Date
        public var amount: Decimal
        public var currency: String?
        public var merchant: String
        /// The corrected name it shows, if it has one.
        public var displayName: String?
        public var card: String?

        public init(date: Date, amount: Decimal, currency: String?, merchant: String,
                    displayName: String? = nil, card: String? = nil) {
            self.date = date
            self.amount = amount
            self.currency = currency
            self.merchant = merchant
            self.displayName = displayName
            self.card = card
        }
    }

    public enum Verdict: Equatable, Sendable {
        /// Nothing like it in the app.
        case new
        /// The same expense: same second, amount, currency, merchant and card, a renamed card
        /// and a corrected merchant name taken for the same.
        case alreadyThere
        /// Same second, amount and currency as an expense in the app, with another name or
        /// card: it looks like the same one, and only the person can tell.
        case looksRepeated
    }

    /// One verdict per row, in the file's order.
    ///
    /// Counted, never just seen: each expense in the app answers for one row. Two «Uber $100»
    /// of the same moment in a file are two expenses; with one already here, one is
    /// `alreadyThere` and the other `new`. A row is matched with its exact expense first, so a
    /// look-alike never takes the place of the real one.
    ///
    /// - Parameters:
    ///   - merchantRenames: the names the person gave merchants by hand; a row with the old
    ///     name is the expense saved with the new one.
    ///   - cardRenames: the same for the cards renamed in «Pagos y categorías».
    public static func classify(_ rows: [ExpenseRecord], against existing: [Existing], primary: String,
                                merchantRenames: MerchantRenames = MerchantRenames(),
                                cardRenames: MerchantRenames = MerchantRenames()) -> [Verdict] {
        func name(_ text: String?, _ renames: MerchantRenames) -> String {
            guard let text else { return "" }
            return MerchantKey.normalized(renames.name(for: text) ?? text)
        }
        /// Same second (floored, as the export writes it) and the same money: a bare «$» and the
        /// main currency are one.
        func moment(_ date: Date, _ currency: String?) -> String {
            let code = CurrencyResolver.isoCode(for: currency, primary: primary) ?? MerchantKey.normalized(currency ?? "")
            return "\(Int(date.timeIntervalSince1970.rounded(.down)))|\(code)"
        }

        struct Candidate {
            var amount: Decimal
            var names: Set<String>
            var card: String
            var taken = false
        }
        var there: [String: [Candidate]] = [:]
        for expense in existing {
            var names: Set<String> = [name(expense.merchant, merchantRenames)]
            if let shown = expense.displayName { names.insert(name(shown, merchantRenames)) }
            there[moment(expense.date, expense.currency), default: []]
                .append(Candidate(amount: expense.amount, names: names, card: name(expense.card, cardRenames)))
        }

        var verdicts = [Verdict](repeating: .new, count: rows.count)
        var undecided: [Int] = []
        // First the exact ones, for every row: a look-alike must not use up the real expense.
        for (index, row) in rows.enumerated() {
            let key = moment(row.date, row.currency)
            let merchant = name(row.merchant, merchantRenames), card = name(row.card, cardRenames)
            if let match = there[key]?.firstIndex(where: {
                !$0.taken && $0.amount == row.amount && $0.card == card && $0.names.contains(merchant)
            }) {
                there[key]?[match].taken = true
                verdicts[index] = .alreadyThere
            } else {
                undecided.append(index)
            }
        }
        // Then what is left: an expense of that moment and amount nobody answered for.
        for index in undecided {
            let row = rows[index], key = moment(row.date, row.currency)
            if let match = there[key]?.firstIndex(where: { !$0.taken && $0.amount == row.amount }) {
                there[key]?[match].taken = true
                verdicts[index] = .looksRepeated
            }
        }
        return verdicts
    }
}
