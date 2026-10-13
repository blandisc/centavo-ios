import XCTest

/// Photographs every screen so the design can be reviewed without a Mac at hand.
/// The CI exports the attachments; nothing here asserts pixels.
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

    func testPrincipalCalendario() {
        _ = launch()
        snap("01-principal-calendario")
    }

    func testPrincipalPresupuesto() {
        let app = launch()
        app.buttons["Presupuesto"].tap()
        sleep(1)
        snap("02-principal-presupuesto")
    }

    func testPrincipalSinPresupuesto() {
        let app = launch(budget: false)
        app.buttons["Presupuesto"].tap()
        sleep(1)
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
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Liverpool'")).firstMatch.tap()
        sleep(1)
        snap("06-editar-gasto")
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
    }

    func testLetraGrande() {
        let app = launch(["-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        snap("10-letra-grande-calendario")
        app.buttons["Presupuesto"].tap()
        sleep(1)
        snap("11-letra-grande-presupuesto")
    }

    func testMesAnterior() {
        let app = launch()
        app.buttons["Mes anterior"].tap()
        sleep(1)
        snap("12-mes-anterior-calendario")
        app.buttons["Presupuesto"].tap()
        sleep(1)
        snap("13-mes-anterior-presupuesto")
    }
}
