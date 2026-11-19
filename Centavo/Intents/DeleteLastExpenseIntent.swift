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
        // Said by Siri: in English the currency goes by its name, never a bare «$» (2026-11-18).
        let money = spokenMoney(expense.amount, isoCode: code, label: code, main: CurrencyPreference.current)
        let name = expense.shownName
        // A whole sentence for each day (2026-11-18): «de» before «el viernes…» said «de el».
        let calendar = Calendar.current
        let now = AppClock.now
        if calendar.isDate(expense.date, inSameDayAs: now) {
            return String(localized: "\(money) en \(name)", comment: "Siri: the expense to delete, e.g. «$89.00 en Oxxo»")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(expense.date, inSameDayAs: yesterday) {
            return String(localized: "\(money) en \(name), de ayer",
                          comment: "Siri: the expense to delete, from yesterday, e.g. «$89.00 en Oxxo, de ayer»")
        }
        // In the iPhone's language, as `QuickExpense.spokenDay` says it: it is only said.
        let day = expense.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.current))
        return String(localized: "\(money) en \(name), del \(day)",
                      comment: "Siri: the expense to delete, from an earlier day, e.g. «$89.00 en Oxxo, del viernes 16 de oct.»")
    }
}
