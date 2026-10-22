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
        Summary("Registrar \(\.$notice)") {
            \.$subtitle
        }
    }

    @MainActor
    // Nothing to show: any dialog, even an empty one, made Atajos pop up a sheet with «Listo» after
    // every purchase (owner, 2026-10-22). The expense just appears in the list.
    func perform() async throws -> some IntentResult {
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        let context = container.mainContext
        try? RecurringExpenses.logDue(in: context)
        // The subtitle goes after the amount, where the reader expects the concept.
        let shop = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = shop.isEmpty || notice.localizedCaseInsensitiveContains(shop) ? notice : notice + "\n" + shop
        let read = WalletNotice.parse(text, knownCards: UserCatalog.sourceNames)
        // Not every Wallet notification is a charge (passes, Apple Cash...): skip those quietly,
        // but keep one that looks like a wrong wiring (see `UnreadNotice`) so the app can say so.
        guard let parsed = read else {
            UnreadNotice.note(notice)
            return .result()
        }
        UnreadNotice.clear()
        // Where the iPhone is right now, if «Guardar dónde pagas» is on: Wallet keeps its own.
        let place = await PaymentPlace.current()
        switch try ExpenseRecorder.record(amountText: parsed.amountText, merchant: parsed.merchant,
                                          card: parsed.card, rawNotice: text, place: place, in: context) {
        case .unreadable, .empty:
            return .result()
        case .duplicate(let merchant):
            return .result()
        case .saved(let merchant):
            // Only what was saved: the owner doesn't want the budget in the notice (2026-10-21).
            return .result()
        }
    }
}
