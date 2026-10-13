import AppIntents
import CentavoCore
import Foundation
import SwiftData

/// The action a Shortcuts "Transaction" automation calls after every Apple Wallet payment.
/// It runs in the background, never opens the app, and saves on-device only.
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar gasto"
    static let description = IntentDescription("Guarda un pago de Apple Wallet en Centavo.")
    static let openAppWhenRun = false

    @Parameter(title: "Monto", description: "El monto tal como lo envía Wallet, p. ej. $123.45")
    var amount: String

    @Parameter(title: "Comercio")
    var merchant: String?

    @Parameter(title: "Tarjeta")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$amount) en \(\.$merchant)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let parsed = AmountParser.parse(amount) else {
            throw $amount.needsValueError("No entendí el monto «\(amount)».")
        }
        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantName = (name?.isEmpty ?? true) ? "Sin comercio" : name!
        let context = Store.container.mainContext
        let now = Date.now

        switch CaptureGuard.check(amount: parsed.value, merchant: merchantName, card: card,
                                  at: now, recent: recentCaptures(before: now, in: context)) {
        case .save:
            break
        case .empty:
            // Wallet sometimes hands over an empty payment. Failing loudly makes Atajos
            // show it, instead of a silent $0 in the list.
            throw CaptureError.empty
        case .duplicate:
            return .result(dialog: "Ya estaba anotado: \(amount) en \(merchantName).")
        }

        let expense = Expense(
            amount: parsed.value,
            currencyMarker: parsed.currencyMarker,
            merchant: merchantName,
            card: card,
            date: now,
            category: rememberedCategory(for: merchantName, in: context),
            rawAmount: amount
        )
        context.insert(expense)
        try context.save()
        return .result(dialog: "Anotado: \(amount) en \(expense.merchant).")
    }

    /// Payments saved in the last few minutes, the only ones a repeat could match.
    private func recentCaptures(before now: Date, in context: ModelContext) -> [RecentCapture] {
        let since = now.addingTimeInterval(-CaptureGuard.duplicateWindow)
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= since })
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map {
            RecentCapture(amount: $0.amount, merchant: $0.merchant, card: $0.card, date: $0.date)
        }
    }

    /// Whatever this merchant was filed under last time, so a captured payment lands
    /// in the right place without anyone touching the app.
    private func rememberedCategory(for merchant: String, in context: ModelContext) -> String? {
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

enum CaptureError: Error, CustomLocalizedStringResourceConvertible {
    case empty

    var localizedStringResource: LocalizedStringResource {
        "Wallet mandó el pago sin monto. Agrégalo a mano con «+» en Centavo."
    }
}

struct CentavoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: ["Registrar gasto en \(.applicationName)"],
            shortTitle: "Registrar gasto",
            systemImageName: "creditcard"
        )
    }
}
