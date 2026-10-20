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

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$notice)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        let context = container.mainContext
        try? RecurringExpenses.logDue(in: context)
        var read = WalletNotice.parse(notice)
        // A notice with money in it that the plain reader couldn't follow (a bank or format it
        // doesn't know): the on-device model may, and is believed only where the notice agrees.
        if read == nil, CaptureText.amount(in: notice) != nil,
           let reading = await LocalModel.readNotice(notice), let amount = reading.amount {
            read = WalletNotice.rescue(notice, merchant: reading.merchant, card: reading.card,
                                       amountFragment: amount)
        }
        // Not every Wallet notification is a charge (passes, Apple Cash...): skip those quietly.
        guard let parsed = read else {
            return .result(dialog: "")
        }
        switch try ExpenseRecorder.record(amountText: parsed.amountText, merchant: parsed.merchant,
                                          card: parsed.card, rawNotice: notice, in: context) {
        case .unreadable, .empty:
            return .result(dialog: "")
        case .duplicate(let merchant):
            return .result(dialog: "Ya estaba anotado: \(parsed.amountText) en \(merchant).")
        case .saved(let merchant):
            let budgetLine = (try? MonthStatus.budgetSentence(in: context, budget: MonthStatus.savedBudget)) ?? nil
            let notice = ["Anotado: \(parsed.amountText) en \(merchant).", budgetLine].compactMap { $0 }
            return .result(dialog: "\(notice.joined(separator: " "))")
        }
    }
}
