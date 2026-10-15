import CentavoCore
import Foundation
import SwiftData

/// What happened to a payment the Wallet automation handed over.
enum CaptureOutcome: Equatable {
    case saved(merchant: String)
    /// The same payment was saved a moment ago.
    case duplicate(merchant: String)
    /// Wallet sent a zero amount, almost certainly a glitch.
    case empty
    /// The amount text could not be read as money.
    case unreadable
}

/// Saves one payment from the Shortcuts "Transaction" automation. It lives apart from the
/// App Intent so it can be tested with an in-memory store.
enum ExpenseRecorder {
    /// A merchant name longer than this is not a name, it is noise.
    static let maxMerchantLength = 120

    static func record(
        amountText: String,
        merchant: String?,
        card: String?,
        in context: ModelContext,
        now: Date = .now
    ) throws -> CaptureOutcome {
        // Usually just the amount; `CaptureText` also finds it when the whole payment came.
        guard let parsed = CaptureText.amount(in: amountText) else { return .unreadable }

        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let merchantName = name.isEmpty ? "Sin comercio" : String(name.prefix(maxMerchantLength))
        // A card that is only spaces is no card: it would print as an empty gap in the ledger.
        let cardName = card?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCard = (cardName?.isEmpty ?? true) ? nil : cardName

        switch CaptureGuard.check(amount: parsed.value, merchant: merchantName, card: cleanCard,
                                  at: now, recent: recentCaptures(before: now, in: context)) {
        case .empty: return .empty
        case .duplicate: return .duplicate(merchant: merchantName)
        case .save: break
        }

        context.insert(Expense(
            amount: parsed.value,
            currencyMarker: parsed.currencyMarker,
            merchant: merchantName,
            card: cleanCard,
            date: now,
            category: rememberedCategory(for: merchantName, in: context),
            rawAmount: amountText
        ))
        try context.save()
        return .saved(merchant: merchantName)
    }

    /// A payment told to Siri or the Action button: how much and where, nothing else.
    ///
    /// Not a Wallet capture, so the raw text is not kept and nothing is treated as a repeat
    /// (two coffees in a row are two coffees). A word for a currency ("89 pesos") is ignored,
    /// as in the expense sheet, so the expense stays in the month's total.
    static func recordByHand(
        amountText: String,
        merchant: String,
        in context: ModelContext,
        now: Date = .now
    ) throws -> CaptureOutcome {
        guard let parsed = AmountParser.parse(amountText) else { return .unreadable }
        guard parsed.value != 0 else { return .empty }
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantName = name.isEmpty ? "Sin comercio" : String(name.prefix(maxMerchantLength))
        let marker = parsed.currencyMarker.flatMap { CurrencyResolver.recognizes($0) ? $0 : nil }
        context.insert(Expense(
            amount: parsed.value,
            currencyMarker: marker ?? "$",
            merchant: merchantName,
            date: now,
            category: rememberedCategory(for: merchantName, in: context)
        ))
        try context.save()
        return .saved(merchant: merchantName)
    }

    /// Payments saved in the last few minutes, the only ones a repeat could match.
    private static func recentCaptures(before now: Date, in context: ModelContext) -> [RecentCapture] {
        let since = now.addingTimeInterval(-CaptureGuard.duplicateWindow)
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= since })
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map {
            RecentCapture(amount: $0.amount, merchant: $0.merchant, card: $0.card, date: $0.date)
        }
    }

    /// Whatever this merchant was filed under last time, so a captured payment lands
    /// in the right place without anyone touching the app.
    private static func rememberedCategory(for merchant: String, in context: ModelContext) -> String? {
        let descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let history = try? context.fetch(descriptor) else { return nil }
        return CategoryMemory.category(
            for: merchant,
            in: history.map {
                CategorizedExpense(merchant: $0.merchant, category: $0.category, date: $0.date)
            }
        )
    }
}
