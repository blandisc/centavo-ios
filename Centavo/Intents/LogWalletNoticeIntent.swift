import AppIntents
import CentavoCore
import Foundation

/// «Registrar aviso de Wallet»: the action an iOS 27 «Notificación» automation runs for every
/// notification Wallet shows. Wallet notifies every purchase, online or contactless, so this
/// one automation catches what the «Wallet» trigger (contactless only) misses.
struct LogWalletNoticeIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar aviso de Wallet"
    static let description = IntentDescription(
        "Anota la compra de una notificación de Wallet: tarjeta, comercio y monto, en línea o sin contacto."
    )
    static let openAppWhenRun = false

    // Connects itself to the notification the trigger hands over where Atajos allows it.
    @Parameter(title: "Notificación",
               description: "La notificación de Wallet completa, p. ej. «American Express México · Google · MXN 319.00»",
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var notice: String

    /// Wallet puts the merchant in the notification's subtitle, and Atajos leaves the subtitle
    /// out when it hands the notification over as text (seen on the owner's iPhone: only
    /// «American Express México · MXN 205.00» arrived for a Didi ride). Connected to
    /// Notificación › Subtítulo, it brings the merchant.
    @Parameter(title: "Comercio",
               description: "El subtítulo de la notificación: en Atajos, toca la burbuja «Notificación» y elige «Subtítulo»")
    var subtitle: String?

    static var parameterSummary: some ParameterSummary {
        // Both on one line, so «Notificación» and «Subtítulo» read as two different things
        // (the owner kept setting the first one to «Subtítulo» too).
        Summary("Registrar \(\.$notice) con comercio \(\.$subtitle)")
    }

    @MainActor
    // Nothing to show: any dialog, even an empty one, made Atajos pop up a sheet with «Listo» after
    // every purchase (owner, 2026-10-22). The expense just appears in the list.
    func perform() async throws -> some IntentResult {
        // A store that failed to open earlier in this launch gets one more try before the
        // payment is left pending (`Store.retry` never opens it twice).
        let container = (try? Store.opened.get()) ?? (try? Store.retry().get())
        // On the widgets before returning: Atajos may suspend the app right after the payment.
        defer { if container != nil { WidgetBridge.refreshAfterIntent() } }
        if let container { try? RecurringExpenses.logDue(in: container.mainContext) }
        // The subtitle goes after the amount, where the reader expects the concept.
        let shop = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = shop.isEmpty || notice.localizedCaseInsensitiveContains(shop) ? notice : notice + "\n" + shop
        // Read before the store is asked for (it needs none), so a notice is kept for «Hoy»
        // even when the expenses can't be opened.
        let read = WalletNotice.parse(text, knownCards: UserCatalog.sourceNames)
        // Not every Wallet notification is a charge (passes, Apple Cash...): skip those quietly,
        // but keep one that looks like a wrong wiring (see `UnreadNotice`) so the app can say so.
        guard let parsed = read else {
            // A notice with a currency next to a figure that couldn't be read is a charge that
            // would vanish in silence (2026-11-02, second audit): always kept to say so.
            UnreadNotice.note(notice, always: WalletNotice.mentionsMoney(text),
                              justSaved: container.map { UnreadNotice.justSavedShops(in: $0.mainContext) } ?? [])
            return .result()
        }
        // A payment that read stays written down outside the store when the store can't take
        // it (2026-11-11): the error goes to Atajos, where nobody sees it in the background.
        func keepUnsaved() {
            UnreadNotice.noteUnsaved(amount: parsed.amountText, merchant: parsed.merchant, card: parsed.card)
        }
        guard let container else {
            keepUnsaved()
            throw CaptureError.storeUnavailable
        }
        let context = container.mainContext
        // The amount the notice already read, not its text read again (`ExpenseRecorder.record`).
        var expense: Expense?
        let outcome: CaptureOutcome
        do {
            outcome = try ExpenseRecorder.record(amountText: parsed.amountText, merchant: parsed.merchant,
                                                     card: parsed.card, amount: parsed.amount, rawNotice: text,
                                                     in: context) { expense = $0 }
        } catch {
            keepUnsaved()
            throw error
        }
        // Where the iPhone is right now, if «Guardar dónde pagas» is on: Wallet keeps its own.
        // After saving, so a slow location never costs a payment.
        if let expense { ExpenseRecorder.addPlace(await PaymentPlace.current(), to: expense, in: context) }
        // Only what was saved: the owner doesn't want the budget in the notice (2026-10-21).
        switch outcome {
        case .unreadable:
            UnreadNotice.note(notice, always: true)
        case .saved(let merchant), .maybeRepeated(let merchant):
            // The notice that brought only this shop's name a moment ago was this payment.
            UnreadNotice.settle(savedIn: [merchant, parsed.merchant ?? ""])
            // The proof the setup guide waits for: it arrived on this iPhone (`CaptureArrival`).
            CaptureArrival.note(amount: parsed.amountText, merchant: merchant)
        case .empty:
            break
        }
        return .result()
    }
}
