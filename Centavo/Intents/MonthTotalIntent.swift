import AppIntents
import Foundation

/// "¿Cuánto llevo en Centavo?": the month's total and what is left of the budget, out loud.
/// Works from Siri, Shortcuts, Spotlight and the Action button without opening the app.
struct MonthTotalIntent: AppIntent {
    static let title: LocalizedStringResource = "Cuánto llevo este mes"
    static let description = IntentDescription(
        "Dice cuánto llevas gastado este mes y cuánto te queda del presupuesto."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        let sentence = try MonthStatus.totalSentence(in: container.mainContext,
                                                     budget: MonthStatus.savedBudget)
        return .result(value: sentence, dialog: "\(sentence)")
    }
}
