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
        // The currency is a menu next to the amount (2026-10-29).
        app.buttons["moneda"].tap()
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
        app.buttons["guia-siguiente"].tap(); sleep(1); snap("09d-guia-paso-4")
        app.buttons["guia-siguiente"].tap(); sleep(1); snap("09e-guia-paso-5")
        app.buttons["guia-siguiente"].tap()
        // Step 6 plays its taps one every 2.6 s: photograph each.
        for frame in ["a", "b", "c"] { snap("09f-guia-paso-6-\(frame)"); usleep(2_600_000) }
        app.buttons["guia-siguiente"].tap()
        sleep(4)  // let the taps play out
        snap("14-guia-conectar-importe")
    }

    func testPrincipalMosaico() {
        let app = launch(["-whereItGoesStyle", "mosaic"])
        snap("03-principal-mosaico")
        app.buttons["categoria-Ropa"].tap()
        sleep(1)
        snap("04-principal-mosaico-ropa")
    }

    func testPrincipalMosaicoDetalle() {
        let app = launch(["-whereItGoesStyle", "mosaic"])
        app.buttons["categoria-Despensa"].press(forDuration: 1.2)
        sleep(1)
        snap("03b-principal-mosaico-detalle")
    }

    func testPrincipalSinEnQueSeVa() {
        let app = launch(["-whereItGoesStyle", "hidden"])
        XCTAssertFalse(app.otherElements["en-que-se-va"].exists, "Se ve «En qué se va» aunque está apagado")
        snap("05-principal-sin-en-que-se-va")
    }

    func testLetraGrandeMosaico() {
        _ = launch(["-whereItGoesStyle", "mosaic", "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityXXXL"])
        snap("12-letra-grande-mosaico")
    }

    func testLetraGrande() {
        let app = launch(["-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        snap("10-letra-grande-presupuesto")
        app.buttons["Calendario"].tap()
        sleep(1)
        snap("11-letra-grande-calendario")
    }

    // MARK: «No cuenta» (el Uber de hoy de la demo, «Me lo reembolsan»)

    /// The demo's Uber of today, the expense that doesn't count.
    private func uncountedRow(_ app: XCUIApplication) -> XCUIElement {
        let uber = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Uber'")).firstMatch
        for _ in 0..<4 where !uber.isHittable { app.swipeUp() }
        return uber
    }

    func testNoCuentaHoja() {
        let app = launch()
        uncountedRow(app).tap()
        // «Tipo: No cuenta» opens «Más detalles» by itself.
        XCTAssertTrue(app.buttons["tipo"].waitForExistence(timeout: 5), "No está «Tipo»")
        for _ in 0..<4 where !app.buttons["motivo"].isHittable { app.swipeUp() }
        snap("nc-01-hoja-no-cuenta")
        let reason = app.buttons["motivo"].exists ? app.buttons["motivo"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Motivo'")).firstMatch
        reason.tap()
        sleep(1)
        snap("nc-02-motivo-abierto")
    }

    func testNoCuentaLista() {
        let app = launch()
        _ = uncountedRow(app)
        sleep(1)
        snap("nc-03-lista-no-cuenta")
    }

    func testNoCuentaDesglose() {
        let app = launch()
        let bar = app.buttons["barra-del-mes"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "No está la barra del presupuesto")
        bar.tap()
        sleep(1)
        snap("nc-04-desglose-fuera-del-presupuesto")
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
