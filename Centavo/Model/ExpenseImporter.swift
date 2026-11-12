import CentavoCore
import Foundation
import SwiftData

/// Loads an exported CSV back in. What is already in the app stays and is not repeated.
enum ExpenseImporter {
    struct Summary: Equatable {
        var added = 0
        var alreadyThere = 0
        var unreadable = 0
        /// Rows left out because they look like an expense already here (same moment and
        /// amount, another name or card) and the person didn't ask for them.
        var leftOut = 0

        /// What happened, said plainly: how many came in, how many were already here, how many
        /// were left out for looking repeated, and how many rows couldn't be read.
        var text: String {
            var parts = [added == 1 ? "Se agregó 1 gasto." : "Se agregaron \(added) gastos."]
            if alreadyThere > 0 {
                parts.append(alreadyThere == 1 ? "1 ya estaba." : "\(alreadyThere) ya estaban.")
            }
            if leftOut > 0 {
                parts.append(leftOut == 1 ? "1 se dejó fuera por parecer repetido."
                             : "\(leftOut) se dejaron fuera por parecer repetidos.")
            }
            if unreadable > 0 {
                parts.append(unreadable == 1 ? "1 renglón no se pudo leer."
                             : "\(unreadable) renglones no se pudieron leer.")
            }
            return parts.joined(separator: " ")
        }
    }

    /// What to do with the rows that look repeated (`CSVImportPlan.Verdict.looksRepeated`).
    enum Repeated {
        /// Only what is plainly new comes in. The safe one, and the default.
        case leaveOut
        /// The person looked and wants them too.
        case add
    }

    /// The one question asked before saving, when the file has rows that look repeated:
    /// «Solo los nuevos» (the default) or «Agregar todos».
    struct Question: Equatable {
        var looksRepeated: Int

        var message: String {
            looksRepeated == 1
                ? "1 parece repetido: mismo día, hora y monto que un gasto que ya tienes, con otro nombre o tarjeta. ¿Agregarlo también?"
                : "\(looksRepeated) parecen repetidos: mismo día, hora y monto que gastos que ya tienes, con otro nombre o tarjeta. ¿Agregarlos también?"
        }

        static let onlyNew = "Solo los nuevos"
        static let all = "Agregar todos"
    }

    /// What the file would do, without saving anything: how many rows are new, already here,
    /// look repeated or can't be read. `leftOut` is the rows that look repeated.
    static func preview(_ text: String, in context: ModelContext,
                        merchantRenames: MerchantRenames = UserCatalog.merchantRenames,
                        cardRenames: MerchantRenames = UserCatalog.cardRenames) throws -> Summary {
        let parsed = try CSVImporter.records(from: text)
        let verdicts = try classify(parsed.records, in: context, merchantRenames: merchantRenames, cardRenames: cardRenames)
        return Summary(added: verdicts.filter { $0 == .new }.count,
                       alreadyThere: verdicts.filter { $0 == .alreadyThere }.count,
                       unreadable: parsed.skipped,
                       leftOut: verdicts.filter { $0 == .looksRepeated }.count)
    }

    /// A row without a category gets the one the owner chose for that merchant (in the app or
    /// elsewhere in the file), like a new Wallet payment; a row with one keeps it. Not the
    /// catalog's guess: an empty category in an export can be on purpose.
    ///
    /// The rows are sorted again here, against what the app holds at this moment (a payment may
    /// have come in while the question was on screen). All of it is saved at once, or none.
    static func importCSV(_ text: String, into context: ModelContext,
                          repeated: Repeated = .leaveOut,
                          rules: CategoryRules = UserCatalog.categoryRules,
                          hidden: [String] = UserCatalog.notAutoAssigned,
                          merchantRenames: MerchantRenames = UserCatalog.merchantRenames,
                          cardRenames: MerchantRenames = UserCatalog.cardRenames) throws -> Summary {
        let parsed = try CSVImporter.records(from: text)
        let existing = try context.fetch(FetchDescriptor<Expense>())
        let latest = CategoryMemory.latest(in: existing.map(\.categorized) + parsed.records.map {
            CategorizedExpense(merchant: $0.merchant, category: $0.category, date: $0.date)
        })
        // Same second, amount, merchant, card and currency: the same expense (an export
        // re-imported), a renamed card or a corrected name included. Counted, not just seen:
        // two «Uber $100» logged the same moment are two expenses, and a file with both brings
        // both, minus the ones already here (`CSVImportPlan`).
        let verdicts = classify(parsed.records, against: existing, merchantRenames: merchantRenames, cardRenames: cardRenames)
        var summary = Summary(unreadable: parsed.skipped)
        for (record, verdict) in zip(parsed.records, verdicts) {
            switch verdict {
            case .alreadyThere:
                summary.alreadyThere += 1
                continue
            case .looksRepeated where repeated == .leaveOut:
                summary.leftOut += 1
                continue
            case .new, .looksRepeated:
                break
            }
            let category = record.category
                ?? CategoryMemory.remembered(for: record.merchant, rules: rules, latest: latest, hidden: hidden)
            let expense = Expense(amount: record.amount, currencyMarker: record.currency,
                                  merchant: record.merchant, card: record.card,
                                  date: record.date, category: category)
            // A part only when it's a part: between zero and the amount, with its sign. Any other
            // number under «Cuenta» (an account number, a 1 for yes) means it counts, as before.
            if let part = record.countedAmount, record.counts, part != 0, part.magnitude < record.amount.magnitude,
               (part < 0) == (record.amount < 0) {
                expense.countedAmount = part
                expense.uncountedReason = record.uncountedReason?.rawValue
            } else if !record.counts {
                // Without a reason in the file it just doesn't count; none is made up.
                expense.countedAmount = 0
                expense.uncountedReason = record.uncountedReason?.rawValue
            }
            context.insert(expense)
            summary.added += 1
        }
        if summary.added > 0 {
            // Half a file is never left in memory looking saved.
            do { try context.save() } catch { context.rollback(); throw error }
        }
        return summary
    }

    private static func classify(_ records: [ExpenseRecord], in context: ModelContext,
                                 merchantRenames: MerchantRenames, cardRenames: MerchantRenames) throws -> [CSVImportPlan.Verdict] {
        classify(records, against: try context.fetch(FetchDescriptor<Expense>()),
                 merchantRenames: merchantRenames, cardRenames: cardRenames)
    }

    private static func classify(_ records: [ExpenseRecord], against existing: [Expense],
                                 merchantRenames: MerchantRenames, cardRenames: MerchantRenames) -> [CSVImportPlan.Verdict] {
        CSVImportPlan.classify(records, against: existing.map {
            CSVImportPlan.Existing(date: $0.date, amount: $0.amount, currency: $0.currencyMarker,
                                   merchant: $0.merchant, displayName: $0.displayName, card: $0.card)
        }, primary: CurrencyPreference.current, merchantRenames: merchantRenames, cardRenames: cardRenames)
    }
}
