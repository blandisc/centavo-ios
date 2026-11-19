import XCTest

// TEMPORAL (cuarta ronda de QA, 2026-11-19): no se sube. Recorre pantallas, guarda captura,
// auditoría de accesibilidad y el árbol que lee VoiceOver en $QA_DIR.
@MainActor
final class QATemporalRondaCuatroTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var lang: String { env["QA_LANG"] ?? "es" }
    private var ax5: Bool { env["QA_AX5"] == "1" }
    private var dir: String { env["QA_DIR"] ?? "/tmp/qa4" }
    private var tag: String { "\(lang)\(ax5 ? "-ax5" : "")" }

    override func setUp() { continueAfterFailure = true }

    private func launch(_ extra: [String], waitingFor identifier: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        XCUIDevice.shared.appearance = .dark
        var args = lang == "en" ? ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
                                : ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX"]
        if ax5 { args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchArguments = args + ["-centavo-dibujos-quietos"] + extra
        app.launch()
        if let identifier { _ = app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20) }
        sleep(2)
        return app
    }

    private func record(_ app: XCUIApplication, _ name: String, audit: Bool = true) {
        let base = "\(dir)/\(tag)"
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(base)/\(name).png"))
        try? app.debugDescription.write(toFile: "\(base)/\(name).tree.txt", atomically: true, encoding: .utf8)
        guard audit else { return }
        var findings: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                findings.append("[\(issue.auditType.rawValue)] \(issue.compactDescription) — "
                                + "\(issue.element?.debugDescription.prefix(200) ?? "sin elemento")")
                return true
            }
        } catch { findings.append("auditoría: \(error)") }
        try? findings.joined(separator: "\n").write(toFile: "\(base)/\(name).audit.txt", atomically: true, encoding: .utf8)
    }

    func test01Bienvenida() {
        for page in 0...4 {
            let app = launch(["-centavo-empty", "-centavo-onboarding", "-centavo-bienvenida-pagina", "\(page)"],
                             waitingFor: page == 4 ? "bienvenida-configurar" : "bienvenida-siguiente")
            record(app, "bienvenida-\(page + 1)")
            if page == 4 {
                let a = app.buttons["bienvenida-configurar"]
                if a.exists { a.tap(); sleep(2); record(app, "bienvenida-listo") }
            }
            app.terminate()
        }
    }

    func test02Hoy() {
        record(launch(["-centavo-demo", "-monthlyBudget", "8000"], waitingFor: "hoy-puedes-gastar"), "hoy-presupuesto")
        let app = launch(["-centavo-demo"], waitingFor: "total-mes")
        record(app, "hoy-sin-presupuesto")
        app.swipeUp(); sleep(1); record(app, "hoy-sin-presupuesto-abajo", audit: false)
        app.swipeUp(); sleep(1); record(app, "hoy-sin-presupuesto-abajo2", audit: false)
        record(launch(["-centavo-empty"], waitingFor: "vacio-anotar"), "hoy-vacio")
    }

    func test03Hojas() {
        let sheets: [(String, String)] = [("anotar", "monto"), ("presupuesto", "presupuesto-monto"),
                                          ("fijos", "agregar-fijo"), ("catalogos", "agregar-categoria"),
                                          ("ajustes", "ajustes-listo"), ("tutorial", "tutorial-titulo")]
        for (name, id) in sheets {
            let app = launch(["-centavo-demo", "-monthlyBudget", "8000", "-centavo-abrir", name], waitingFor: id)
            record(app, "hoja-\(name)")
            if name == "anotar" {
                let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Más detalles' OR label BEGINSWITH[c] 'More details'")).firstMatch
                if more.exists { more.tap(); sleep(1); record(app, "hoja-anotar-detalles") }
            }
            if name == "ajustes" {
                app.swipeUp(); sleep(1); record(app, "hoja-ajustes-abajo")
                let backup = app.buttons["ajustes-respaldo"]
                for _ in 0..<4 where !backup.exists { app.swipeUp() }
                if backup.exists { backup.tap(); sleep(2); record(app, "respaldo")
                    app.swipeUp(); sleep(1); record(app, "respaldo-abajo", audit: false) }
            }
            if name == "tutorial" {
                for i in 2...6 { app.swipeLeft(); sleep(2); record(app, "tutorial-\(i)", audit: i == 2) }
            }
            app.terminate()
        }
    }

    func test04Gasto() {
        let app = launch(["-centavo-demo", "-monthlyBudget", "8000"], waitingFor: "hoy-puedes-gastar")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Liverpool'")).firstMatch
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        if row.exists { row.tap(); sleep(2); record(app, "gasto-editar")
            app.swipeUp(); sleep(1); record(app, "gasto-editar-abajo", audit: false) }
    }

    func test05Busqueda() {
        let app = launch(["-centavo-demo", "-monthlyBudget", "8000"], waitingFor: "hoy-puedes-gastar")
        let search = app.buttons.matching(NSPredicate(format: "label == 'Búsqueda' OR label == 'Search' OR label == 'Buscar'")).firstMatch
        if search.exists { search.tap() } else { app.searchFields.firstMatch.tap() }
        sleep(2)
        record(app, "busqueda-vacia")
        let field = app.searchFields.firstMatch
        if field.exists { field.typeText(lang == "en" ? "groceries" : "oxxo"); sleep(2); record(app, "busqueda-resultado")
            field.typeText("zzzz"); sleep(2); record(app, "busqueda-nada", audit: false) }
    }

    func test06Guia() {
        let app = launch(["-centavo-empty", "-centavo-guia-paso", "0"], waitingFor: "guia-siguiente")
        record(app, "guia-1")
        let next = app.buttons["guia-siguiente"]
        for step in 2...14 {
            guard next.exists, next.isHittable else { break }
            next.tap(); sleep(2)
            record(app, "guia-\(step)", audit: step % 4 == 0)
        }
    }

    func test07Mas() {
        let app = launch(["-centavo-demo", "-monthlyBudget", "8000"], waitingFor: "hoy-puedes-gastar")
        app.buttons[lang == "en" ? "More" : "Más"].tap(); sleep(1)
        record(app, "menu-mas", audit: false)
    }
}
