import AppIntents

/// «Anotar gasto» from the small widget's «+» and from the control (Centro de control, pantalla
/// bloqueada, botón de acción): opens Al día on the expense sheet.
///
/// It is compiled into the app and into the widgets (project.yml): the widget's button and the
/// control name it, and the system runs it in the app, which it opens first (`openAppWhenRun`).
/// `OpenURLIntent` would be simpler, but it only takes universal links, not `centavo://`.
struct OpenAddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir para anotar un gasto"
    static let description = IntentDescription("Abre Al día en la hoja para anotar un gasto.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await AddExpenseRoute.open()
        return .result()
    }
}

/// Who opens the sheet once the app is up. The app sets it at launch (`AddExpenseLink`); in the
/// widgets it stays empty, since the system never runs the intent there.
@MainActor
enum AddExpenseRoute {
    static var handler: (@MainActor () async -> Void)?

    static func open() async { await handler?() }
}
