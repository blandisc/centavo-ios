import AppIntents
import Foundation

/// The action a Shortcuts "Transaction" automation calls after every Apple Wallet payment.
/// It runs in the background, never opens the app, and saves on-device only.
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar gasto"
    static let description = IntentDescription("Guarda un pago de Apple Wallet en Al día.")
    static let openAppWhenRun = false

    // Titled «Importe» because that is what Atajos (in Spanish) calls the amount of a Wallet
    // transaction: the person matches the word in the action to the same word in the list.
    // Connects itself to what comes before it (the Wallet payment) where Atajos allows it.
    // Connecting the whole payment instead of its «Importe» works too: see `CaptureText`.
    @Parameter(title: "Importe", description: "El importe tal como lo envía Wallet, p. ej. $123.45",
               inputConnectionBehavior: .connectToPreviousIntentResult)
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
        // So "what is left" counts this month's rent even if the app was not opened.
        try? RecurringExpenses.logDue(in: container.mainContext)
        let place = await PaymentPlace.current()
        switch try ExpenseRecorder.record(amountText: amount, merchant: merchant, card: card,
                                          place: place, in: container.mainContext) {
        case .unreadable:
            // Seen for real: the whole Wallet payment connected here arrives as just the
            // merchant's name. Say how to fix the automation, not only that it failed.
            throw $amount.needsValueError(
                "No llegó un monto, llegó «\(amount)». En Atajos, toca la burbuja de «Importe» y elige «Importe» del pago de Wallet (no el pago completo)."
            )
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
        case .empty: "Wallet mandó el pago sin monto. Agrégalo a mano con «+» en Al día."
        case .storeUnavailable: "Al día no pudo abrir su base de datos. Abre la app para ver qué pasó."
        }
    }
}

/// What Siri, Spotlight and the Action button offer with no setup.
///
/// «Registrar gasto» is not here on purpose: it only makes sense inside the Wallet
/// automation, wired to the payment. Offered as a ready-made shortcut it showed up in the
/// list Atajos gives when creating that automation, and picking it there saved an
/// automation with no amount that never logged anything. It stays an action in Atajos.
struct CentavoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Anotar gasto en \(.applicationName)",
                "Anota un gasto en \(.applicationName)",
                "Gasté en \(.applicationName)",
            ],
            shortTitle: "Anotar gasto",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: MonthTotalIntent(),
            phrases: [
                "Cuánto llevo en \(.applicationName)",
                "Cuánto he gastado en \(.applicationName)",
                "Cuánto me queda en \(.applicationName)",
            ],
            shortTitle: "Cuánto llevo",
            systemImageName: "sum"
        )
        AppShortcut(
            intent: QuickExpenseIntent(),
            phrases: [
                "Anota esto en \(.applicationName)",
                "Apunta un gasto en \(.applicationName)",
                "Anotar en una frase en \(.applicationName)",
            ],
            shortTitle: "Anotar en una frase",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: CategoryTotalIntent(),
            phrases: [
                "Cuánto llevo en \(\.$category) en \(.applicationName)",
                "Cuánto he gastado en \(\.$category) en \(.applicationName)",
                "Cuánto llevo por categoría en \(.applicationName)",
            ],
            shortTitle: "Cuánto llevo en…",
            systemImageName: "chart.pie"
        )
    }
}
