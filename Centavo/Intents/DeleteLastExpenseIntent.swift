import AppIntents
import CentavoCore
import Foundation

/// «Borra el último gasto en Al día»: for the coffee told to Siri twice, or a payment logged by
/// mistake. Siri says which one it is and asks before deleting it; a fixed expense is never
/// the one (see `ExpenseRecorder.lastLogged`).
struct DeleteLastExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Borrar el último gasto"
    static let description = IntentDescription("Borra el gasto más reciente, después de confirmarlo.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // One more try at a store that failed earlier in this launch (`Store.forIntent`).
        guard let container = Store.forIntent else { throw CaptureError.storeUnavailable }
        // The widgets drop it before returning: Siri may suspend the app right after.
        defer { WidgetBridge.refreshAfterIntent() }
        let context = container.mainContext
        guard let expense = try ExpenseRecorder.lastLogged(in: context) else {
            return .result(dialog: "No hay gastos que borrar.")
        }
        let described = describe(expense)
        // Always asked (no `conditions`): a delete by voice is never taken for granted.
        try await requestConfirmation(
            actionName: .custom(acceptLabel: "Borrar", acceptAlternatives: ["Sí", "Bórralo"],
                                denyLabel: "Cancelar", denyAlternatives: ["No"], destructive: true),
            dialog: "¿Borro \(described)?"
        )
        context.delete(expense)
        // The context is the screens' too: a delete left pending would go out with the next save.
        do { try context.save() } catch { context.rollback(); throw error }
        return .result(dialog: "Listo, borré \(described).")
    }

    /// «$89.00 en Oxxo, de ayer»: enough to know it is the right one.
    @MainActor
    private func describe(_ expense: Expense) -> String {
        let code = ExpenseRecorder.spokenCurrency(expense.currencyMarker, primary: MonthStatus.primaryCurrency)
        let money = formatMoney(expense.amount, isoCode: code, label: code, main: CurrencyPreference.current)
        let name = expense.shownName
        if let day = QuickExpense.spokenDay(expense.date) {
            return String(localized: "\(money) en \(name), de \(day)",
                          comment: "Siri: the expense to delete, e.g. «$89.00 en Oxxo, de ayer»")
        }
        return String(localized: "\(money) en \(name)", comment: "Siri: the expense to delete, e.g. «$89.00 en Oxxo»")
    }
}
