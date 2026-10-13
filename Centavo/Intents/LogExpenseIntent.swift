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
        let expense = Expense(
            amount: parsed.value,
            currencyMarker: parsed.currencyMarker,
            merchant: merchantName,
            card: card,
            category: rememberedCategory(for: merchantName, in: context),
            rawAmount: amount
        )
        context.insert(expense)
        try context.save()
        return .result(dialog: "Anotado: \(amount) en \(expense.merchant).")
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
