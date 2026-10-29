import AppIntents
import Foundation

/// «¿Cuánto puedo gastar hoy en Al día?»: the main screen's big figure, out loud, and nothing
/// else. «Cuánto llevo» says the whole month; this is the short answer before paying.
struct TodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Cuánto puedo gastar hoy"
    static let description = IntentDescription("Dice cuánto puedes gastar hoy, como la cifra grande de la app.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        // A fixed expense now due may have been saved: on the widgets before returning.
        defer { WidgetBridge.refreshAfterIntent() }
        try? RecurringExpenses.logDue(in: container.mainContext)
        let sentence = try MonthStatus.todaySentence(in: container.mainContext, budget: MonthStatus.savedBudget)
        return .result(value: sentence, dialog: "\(sentence)")
    }
}
