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
        switch try ExpenseRecorder.record(amountText: amount, merchant: merchant, card: card,
                                          in: Store.container.mainContext) {
        case .unreadable:
            throw $amount.needsValueError("No entendí el monto «\(amount)».")
        case .empty:
            // Wallet sometimes hands over an empty payment. Failing loudly makes Atajos
            // show it, instead of a silent $0 in the list.
            throw CaptureError.empty
        case .duplicate(let merchant):
            return .result(dialog: "Ya estaba anotado: \(amount) en \(merchant).")
        case .saved(let merchant):
            return .result(dialog: "Anotado: \(amount) en \(merchant).")
        }
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
