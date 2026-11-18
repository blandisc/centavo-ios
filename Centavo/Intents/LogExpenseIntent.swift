import AppIntents
import CentavoCore
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
    // The example has no decimals (2026-11-18): «123.45» misleads whoever writes «123,45 €».
    @Parameter(title: "Importe", description: "El importe tal como lo envía Wallet, p. ej. $123",
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
        // A payment the store can't take stays written down outside it for «Hoy» (2026-11-11):
        // the error goes to Atajos, where nobody sees it in the background. With an amount
        // that reads, as a payment to write down; without one, as a notice that didn't read.
        func keepUnsaved() {
            if CaptureText.amount(in: amount) != nil {
                UnreadNotice.noteUnsaved(amount: amount, merchant: merchant, card: card)
            } else {
                UnreadNotice.note(amount, always: true)
            }
        }
        // A store that failed to open earlier in this launch gets one more try before the
        // payment is left pending (`Store.forIntent`).
        guard let container = Store.forIntent else {
            keepUnsaved()
            throw CaptureError.storeUnavailable
        }
        // On the widgets before returning: Atajos may suspend the app right after the payment,
        // before the 300 ms of `WidgetBridge.start()` go by.
        defer { WidgetBridge.refreshAfterIntent() }
        // So "what is left" counts this month's rent even if the app was not opened.
        _ = try? RecurringExpenses.logDue(in: container.mainContext)
        let context = container.mainContext
        // Whether a payment had ever arrived here, asked before `record` marks this one as
        // arrived: otherwise «Llegó tu primer pago solo» never showed (2026-11-18).
        let arrivedBefore = CaptureArrival.walletKnown()
        // Saved first; where the iPhone is comes after, so a slow location never costs a payment.
        var expense: Expense?
        let outcome: CaptureOutcome
        do {
            outcome = try ExpenseRecorder.record(amountText: amount, merchant: merchant, card: card,
                                                     in: context) { expense = $0 }
        } catch {
            keepUnsaved()
            throw error
        }
        if let expense { ExpenseRecorder.addPlace(await PaymentPlace.current(), to: expense, in: context) }
        // What the dialog and the guide say: only the figure that was read («MXN 300.00»), not
        // the whole payment when that is what was connected («ALL 2 GO MXN 300.00», 2026-11-18).
        let shown = CaptureText.shown(amount)
        switch outcome {
        case .unreadable:
            // Figures with a currency that still didn't read («1.2.3 MXN»): an amount did come,
            // so it is kept as a payment, with its shop and card, and the advice about «Importe»
            // would be wrong (2026-11-18).
            if WalletNotice.mentionsMoney(amount) {
                UnreadNotice.noteUnsaved(amount: amount, merchant: merchant, card: card)
                throw CaptureError.unreadableAmount(amount)
            }
            // Seen for real: the whole Wallet payment connected here arrives as just the
            // merchant's name. Say how to fix the automation, not only that it failed.
            // Kept for «Hoy» too, like the notice automation does: Atajos may fail out of sight.
            UnreadNotice.note(amount, always: true, justSaved: UnreadNotice.justSavedShops(in: context))
            throw $amount.needsValueError(
                "No llegó un monto, llegó «\(amount)». En Atajos, toca la burbuja de «Importe» y elige «Importe» del pago de Wallet (no el pago completo)."
            )
        case .empty:
            // Wallet sometimes hands over an empty payment. Failing loudly makes Atajos
            // show it, instead of a silent $0 in the list.
            throw CaptureError.empty
        case .maybeRepeated(let merchant):
            UnreadNotice.settle(savedIn: [merchant, self.merchant ?? ""])
            // The proof the setup guide waits for: it arrived on this iPhone (`CaptureArrival`).
            CaptureArrival.note(amount: shown, merchant: merchant, arrivedBefore: arrivedBefore)
            return .result(dialog: "Anotado: \(shown) en \(merchant). Es igual a uno de hace unos minutos: revísalo en Al día.")
        case .saved(let merchant):
            // The notice that brought only this shop's name a moment ago was this payment.
            UnreadNotice.settle(savedIn: [merchant, self.merchant ?? ""])
            CaptureArrival.note(amount: shown, merchant: merchant, arrivedBefore: arrivedBefore)
            // Only what was saved: the owner doesn't want the budget in the notice (2026-10-21).
            return .result(dialog: "Anotado: \(shown) en \(merchant).")
        }
    }
}

enum CaptureError: Error, CustomLocalizedStringResourceConvertible {
    case empty
    case storeUnavailable
    /// The same, with what was said kept pending in «Hoy» (2026-11-18).
    case storeUnavailableKept
    /// The save failed; what was said or paid is pending in «Hoy» (2026-11-18): Siri used to
    /// say SwiftData's own error, in English, and nothing was kept.
    case saveFailed
    /// An amount with figures and a currency that still didn't read («1.2.3 MXN»): kept with
    /// its shop and card in «Hoy». Telling them to rewire «Importe» would be wrong advice.
    case unreadableAmount(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .empty: "Wallet mandó el pago sin monto. Agrégalo a mano con «+» en Al día."
        case .storeUnavailable: "Al día no pudo abrir tus gastos. Abre la app para ver qué hacer."
        case .storeUnavailableKept:
            "Al día no pudo abrir tus gastos y no lo anoté. Quedó pendiente en Hoy: abre la app para ver qué hacer."
        case .saveFailed: "No pude guardar este gasto. Quedó pendiente en Hoy para que lo anotes a mano."
        case .unreadableAmount(let text):
            "No pude leer el importe «\(text)». Quedó pendiente en Hoy para que lo anotes a mano."
        }
    }
}

/// What Siri, Spotlight and the Action button offer with no setup. Apple allows 10 at most;
/// there are 6.
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
        AppShortcut(
            intent: TodayIntent(),
            phrases: [
                "Cuánto puedo gastar hoy en \(.applicationName)",
                "Cuánto puedo gastar hoy con \(.applicationName)",
                "Qué puedo gastar hoy en \(.applicationName)",
            ],
            shortTitle: "Cuánto puedo gastar hoy",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: DeleteLastExpenseIntent(),
            phrases: [
                "Borra el último gasto en \(.applicationName)",
                "Borrar el último gasto en \(.applicationName)",
                "Quita el último gasto de \(.applicationName)",
            ],
            shortTitle: "Borrar el último gasto",
            systemImageName: "trash"
        )
    }
}
