import AppIntents
import Foundation

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
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        switch try ExpenseRecorder.record(amountText: amount, merchant: merchant, card: card,
                                          in: container.mainContext) {
        case .unreadable:
            throw $amount.needsValueError("No entendí el monto «\(amount)».")
        case .empty:
            // Wallet sometimes hands over an empty payment. Failing loudly makes Atajos
            // show it, instead of a silent $0 in the list.
            throw CaptureError.empty
        case .duplicate(let merchant):
            return .result(dialog: "Ya estaba anotado: \(amount) en \(merchant).")
        case .saved(let merchant):
            // Right after paying is when "how am I doing" matters most. If that part fails,
            // the payment is still saved; the notice just says less.
            let budgetLine = (try? MonthStatus.budgetSentence(in: container.mainContext,
                                                              budget: MonthStatus.savedBudget)) ?? nil
            let notice = ["Anotado: \(amount) en \(merchant).", budgetLine].compactMap { $0 }
            return .result(dialog: "\(notice.joined(separator: " "))")
        }
    }
}

enum CaptureError: Error, CustomLocalizedStringResourceConvertible {
    case empty
    case storeUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .empty: "Wallet mandó el pago sin monto. Agrégalo a mano con «+» en Centavo."
        case .storeUnavailable: "Centavo no pudo abrir su base de datos. Abre la app para ver qué pasó."
        }
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
