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
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        // The widgets drop it before returning: Siri may suspend the app right after.
        defer { WidgetBridge.refreshAfterIntent() }
        let context = container.mainContext
        guard let expense = try ExpenseRecorder.lastLogged(in: context) else {
            return .result(dialog: "No hay gastos que borrar.")
        }
        let described = describe(expense)
        try await requestConfirmation(
            result: .result(dialog: "¿Borro \(described)?"),
            confirmationActionName: .custom(acceptLabel: "Borrar", acceptAlternatives: ["Sí", "Bórralo"],
                                            denyLabel: "Cancelar", denyAlternatives: ["No"], destructive: true)
        )
        context.delete(expense)
        try context.save()
        return .result(dialog: "Listo, borré \(described).")
    }

    /// «$89.00 en Oxxo, de ayer»: enough to know it is the right one.
    @MainActor
    private func describe(_ expense: Expense) -> String {
        let code = ExpenseRecorder.spokenCurrency(expense.currencyMarker, primary: MonthStatus.primaryCurrency)
        let day = QuickExpense.spokenDay(expense.date).map { ", de \($0)" } ?? ""
        return "\(formatMoney(expense.amount, isoCode: code, label: code)) en \(expense.shownName)\(day)"
    }
}
