import AppIntents
import CentavoCore
import Foundation

/// «Anotar gasto»: cash, an online purchase, anything Wallet did not catch. Siri asks how
/// much and where, and it is saved without opening the app. Also for the Action button.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Anotar gasto"
    static let description = IntentDescription(
        "Anota un gasto a mano: efectivo, compras en línea o lo que Wallet no alcance a capturar."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Monto", requestValueDialog: "¿Cuánto fue? Si no fue en tu moneda, di «dólares» o «euros».")
    var amount: String

    @Parameter(title: "Comercio", requestValueDialog: "¿Dónde?")
    var merchant: String

    /// Optional: Siri never asks for it. Set in Atajos (or said there), it beats the memory.
    @Parameter(title: "Categoría")
    var category: CategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Anotar \(\.$amount) en \(\.$merchant)") {
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Told to Siri and not written down stays in «Hoy» like a Wallet payment (2026-11-18,
        // the rule of 2026-11-11): with the Action button and the phone locked, nobody may hear
        // the error. Only an amount that reads is kept, as Siri says it back («$89.00», which
        // «Anotar» reads again); one that doesn't or a zero is asked for again. `true`: kept.
        func keepUnsaved() -> Bool {
            guard let parsed = AmountParser.parse(amount), parsed.value != 0 else { return false }
            UnreadNotice.noteUnsaved(amount: spoken(amount), merchant: merchant, card: nil)
            return true
        }
        // One more try at a store that failed earlier in this launch (`Store.forIntent`).
        guard let container = Store.forIntent else {
            throw keepUnsaved() ? CaptureError.storeUnavailableKept : CaptureError.storeUnavailable
        }
        // On the widgets before returning: Siri may suspend the app right after.
        defer { WidgetBridge.refreshAfterIntent() }
        // So "what is left" counts this month's rent even if the app was not opened.
        _ = try? RecurringExpenses.logDue(in: container.mainContext)
        let context = container.mainContext
        let outcome: CaptureOutcome
        do {
            outcome = try ExpenseRecorder.recordByHand(amountText: amount, merchant: merchant,
                                                       category: category?.id, in: context)
        } catch {
            // It read (`recordByHand` only throws on saving), so it is always kept.
            _ = keepUnsaved()
            throw CaptureError.saveFailed
        }
        switch outcome {
        case .unreadable:
            // No decimals in the example (2026-11-18): «89.50» misleads whoever says «89 coma 50».
            throw $amount.needsValueError("No entendí «\(amount)». Dime solo la cantidad, por ejemplo 89.")
        case .empty:
            throw $amount.needsValueError("Un gasto de cero no se anota. ¿Cuánto fue?")
        case .maybeRepeated(let name), .saved(let name):
            let budgetLine = (try? MonthStatus.budgetSentence(in: context, budget: MonthStatus.savedBudget)) ?? nil
            let notice = ["Anotado: \(spoken(amount)) en \(name).", budgetLine].compactMap { $0 }
            return .result(dialog: "\(notice.joined(separator: " "))")
        }
    }

    /// "89" said to Siri reads back as money: "$89.00".
    private func spoken(_ text: String) -> String {
        guard let parsed = AmountParser.parse(text) else { return text }
        let code = ExpenseRecorder.spokenCurrency(parsed.currencyMarker, primary: MonthStatus.primaryCurrency)
        return formatMoney(parsed.value, isoCode: code, label: code, main: CurrencyPreference.current)
    }
}
