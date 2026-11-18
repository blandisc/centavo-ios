import XCTest

/// The app with the iPhone in English (2026-11-18, docs/DECISIONS.md): the same screens as
/// `ScreenshotTests`, to review the English copy. It finds its way only by launch arguments and
/// accessibility identifiers, never by a label, and asserts no text: it is to look at.
/// Runs by hand in the CI («Capturas en inglés», artifact `capturas-ingles`).
@MainActor
final class EnglishScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// Opens the app in English with `extra` and waits for `identifier` (or 3 s without one).
    @discardableResult
    private func launch(_ extra: [String], waitingFor identifier: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        XCUIDevice.shared.appearance = .dark
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-centavo-dibujos-quietos"] + extra
        app.launch()
        if let identifier {
            let element = app.descendants(matching: .any)[identifier]
            if !element.waitForExistence(timeout: 20) { sleep(3) }
        } else {
            sleep(3)
        }
        sleep(1)
        return app
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The welcome, page by page (the app opens on the page asked for).
    func testBienvenida() {
        for page in 0...4 {
            let app = launch(["-centavo-empty", "-centavo-onboarding", "-centavo-bienvenida-pagina", "\(page)"],
                             waitingFor: page == 4 ? "bienvenida-configurar" : "bienvenida-siguiente")
            snap("en-70-bienvenida-\(page + 1)")
            app.terminate()
        }
    }

    func testHoyConPresupuesto() {
        launch(["-centavo-demo", "-monthlyBudget", "8000"], waitingFor: "hoy-puedes-gastar")
        snap("en-01-hoy-con-presupuesto")
    }

    func testHoySinPresupuesto() {
        launch(["-centavo-demo"], waitingFor: "total-mes")
        snap("en-02-hoy-sin-presupuesto")
    }

    func testHoyVacio() {
        launch(["-centavo-empty"], waitingFor: "vacio-anotar")
        snap("en-03-hoy-vacio")
    }

    /// Each sheet `-centavo-abrir` opens over «Hoy», with the identifier it waits for.
    func testHojas() {
        let sheets: [(name: String, identifier: String)] = [
            ("anotar", "monto"),
            ("presupuesto", "presupuesto-monto"),
            ("fijos", "agregar-fijo"),
            ("catalogos", "agregar-categoria"),
            ("ajustes", "ajustes-listo"),
            ("tutorial", "tutorial-titulo"),
        ]
        for sheet in sheets {
            let app = launch(["-centavo-demo", "-monthlyBudget", "8000", "-centavo-abrir", sheet.name],
                             waitingFor: sheet.identifier)
            snap("en-10-hoja-\(sheet.name)")
            app.terminate()
        }
    }

    /// The setup guide from its first step (`-centavo-guia-paso 0`), one picture per step.
    func testGuia() {
        let app = launch(["-centavo-empty", "-centavo-guia-paso", "0"], waitingFor: "guia-siguiente")
        snap("en-20-guia-paso-1")
        let next = app.buttons["guia-siguiente"]
        for step in 2...12 {
            guard next.exists, next.isHittable else { break }
            next.tap()
            sleep(2)
            snap("en-20-guia-paso-\(step)")
        }
    }

    /// The ready-made automation's page (iOS 27), when this iOS has it.
    func testAtajoListo() {
        launch(["-centavo-empty", "-centavo-atajo"])
        snap("en-21-atajo-listo")
    }
}
