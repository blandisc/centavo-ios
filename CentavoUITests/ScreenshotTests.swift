import XCTest

/// Photographs every screen so the design can be reviewed without a Mac at hand.
/// The CI exports the attachments; nothing here asserts pixels.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = [], demo: Bool = true,
                        budget: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX"]
        arguments += [demo ? "-centavo-demo" : "-centavo-empty"]
        if budget { arguments += ["-monthlyBudget", "8000"] }
        XCUIDevice.shared.appearance = .dark
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.buttons["Anotar gasto"].waitForExistence(timeout: 20),
                      "La pantalla principal no abrió")
        return app
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPrincipalPresupuesto() {
        _ = launch()
        snap("01-principal-presupuesto")
    }

    func testPrincipalCalendario() {
        let app = launch()
        app.buttons["Calendario"].tap()
        sleep(1)
        snap("02-principal-calendario")
    }

    func testPrincipalSinPresupuesto() {
        _ = launch(budget: false)
        snap("03-principal-sin-presupuesto")
    }

    func testPrimeraVez() {
        _ = launch(demo: false, budget: false)
        snap("04-primera-vez")
    }

    func testNuevoGasto() {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        sleep(1)
        snap("05-nuevo-gasto")
    }

    func testEditarGasto() {
        let app = launch()
        let liverpool = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Liverpool'")).firstMatch
        for _ in 0..<4 where !liverpool.exists { app.swipeUp() }
        liverpool.tap()
        sleep(1)
        snap("06-editar-gasto")
    }

    func testNuevoGastoEnDolares() {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        sleep(1)
        app.buttons["USD"].tap()
        snap("05b-nuevo-gasto-dolares")
    }

    func testMenuMas() {
        let app = launch()
        app.buttons["Más"].tap()
        sleep(1)
        snap("07-menu-mas")
    }

    func testFijarPresupuesto() {
        let app = launch()
        app.buttons["Más"].tap()
        app.buttons["Presupuesto del mes"].tap()
        sleep(1)
        snap("08-fijar-presupuesto")
    }

    func testGuia() {
        let app = launch()
        app.buttons["Más"].tap()
        app.buttons["Configurar atajo"].tap()
        sleep(1)
        snap("09-guia")
        app.buttons["guia-siguiente"].tap(); sleep(1); snap("09b-guia-paso-2")
        app.buttons["guia-siguiente"].tap(); sleep(1); snap("09c-guia-paso-3")
        app.buttons["guia-siguiente"].tap(); app.buttons["guia-siguiente"].tap()
        snap("09d-guia-paso-5-a"); sleep(2); snap("09e-guia-paso-5-b"); sleep(2); snap("09f-guia-paso-5-c")
        app.buttons["guia-siguiente"].tap()
        sleep(4)  // let the taps play out
        snap("14-guia-conectar-importe")
    }

    func testLetraGrande() {
        let app = launch(["-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        snap("10-letra-grande-presupuesto")
        app.buttons["Calendario"].tap()
        sleep(1)
        snap("11-letra-grande-calendario")
    }

    func testMesAnterior() {
        let app = launch()
        app.buttons["Mes anterior"].tap()
        sleep(1)
        snap("12-mes-anterior-presupuesto")
        app.buttons["Calendario"].tap()
        sleep(1)
        snap("13-mes-anterior-calendario")
    }

}
