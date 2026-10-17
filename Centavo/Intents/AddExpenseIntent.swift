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

    @Parameter(title: "Monto", requestValueDialog: "¿Cuánto fue?")
    var amount: String

    @Parameter(title: "Comercio", requestValueDialog: "¿Dónde?")
    var merchant: String

    static var parameterSummary: some ParameterSummary {
        Summary("Anotar \(\.$amount) en \(\.$merchant)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        let context = container.mainContext
        switch try ExpenseRecorder.recordByHand(amountText: amount, merchant: merchant, in: context) {
        case .unreadable:
            throw $amount.needsValueError("No entendí «\(amount)». Dime solo la cantidad, por ejemplo 89.50.")
        case .empty:
            throw $amount.needsValueError("Un gasto de cero no se anota. ¿Cuánto fue?")
        case .duplicate(let name), .saved(let name):
            let budgetLine = (try? MonthStatus.budgetSentence(in: context, budget: MonthStatus.savedBudget)) ?? nil
            let notice = ["Anotado: \(spoken(amount)) en \(name).", budgetLine].compactMap { $0 }
            return .result(dialog: "\(notice.joined(separator: " "))")
        }
    }

    /// "89" said to Siri reads back as money: "$89.00".
    private func spoken(_ text: String) -> String {
        guard let parsed = AmountParser.parse(text) else { return text }
        let marker = parsed.currencyMarker.flatMap { CurrencyResolver.recognizes($0) ? $0 : nil }
        let primary = MonthStatus.primaryCurrency
        return formatMoney(parsed.value, isoCode: CurrencyResolver.isoCode(for: marker, primary: primary),
                           label: marker ?? "$")
    }
}
