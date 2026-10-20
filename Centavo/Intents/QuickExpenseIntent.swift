import AppIntents
import CentavoCore
import Foundation

/// «Anota esto en Al día»: Siri asks what was spent and one sentence does the rest, «230 de
/// unos tacos ayer, en efectivo». Apple doesn't let the phrase that starts Siri carry free
/// text, so it is two steps: the phrase, then the sentence.
///
/// The amount, the day and the card are read by plain rules on every iPhone; with Apple
/// Intelligence, the on-device model reads odder sentences, and is believed only where it
/// matches what was said.
struct QuickExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Anotar en una frase"
    static let description = IntentDescription(
        "Anota un gasto dicho en una frase, con el día y cómo pagaste: «230 de tacos ayer, en efectivo»."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Frase", requestValueDialog: "¿Qué gastaste? Por ejemplo: 230 de tacos ayer, en efectivo.")
    var sentence: String

    static var parameterSummary: some ParameterSummary {
        Summary("Anotar \(\.$sentence)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let container) = Store.opened else { throw CaptureError.storeUnavailable }
        let context = container.mainContext
        try? RecurringExpenses.logDue(in: context)
        let sources = UserCatalog.decode(UserDefaults.standard.string(forKey: UserCatalog.sourcesKey) ?? "")
            .map(\.name)
        guard let entry = await QuickExpense.read(sentence, sources: sources) else {
            throw $sentence.needsValueError("No encontré cuánto fue en «\(sentence)». Dilo con la cantidad, por ejemplo: 230 de tacos.")
        }
        switch try ExpenseRecorder.recordByHand(amountText: entry.amountText, merchant: entry.merchant ?? "",
                                                card: entry.source, in: context, now: entry.date) {
        case .unreadable, .empty:
            throw $sentence.needsValueError("Un gasto de cero no se anota. ¿Cuánto fue?")
        case .duplicate(let name), .saved(let name):
            let budgetLine = (try? MonthStatus.budgetSentence(in: context, budget: MonthStatus.savedBudget)) ?? nil
            let day = QuickExpense.spokenDay(entry.date).map { ", \($0)" } ?? ""
            let paid = entry.source.map { ", con \($0.lowercased() == "efectivo" ? "efectivo" : $0)" } ?? ""
            let notice = ["Anotado: \(spoken(entry.amountText)) en \(name)\(day)\(paid).", budgetLine]
                .compactMap { $0 }
            return .result(dialog: "\(notice.joined(separator: " "))")
        }
    }

    private func spoken(_ text: String) -> String {
        guard let parsed = AmountParser.parse(text) else { return text }
        let code = ExpenseRecorder.spokenCurrency(parsed.currencyMarker, primary: MonthStatus.primaryCurrency)
        return formatMoney(parsed.value, isoCode: code, label: code)
    }
}
