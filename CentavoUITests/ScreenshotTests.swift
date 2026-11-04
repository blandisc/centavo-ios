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

    /// Types once the field has the keyboard. On CI's smaller iPhone the field can sit at the
    /// bottom edge, or under the bar with «Listo» over the keyboard, where a tap lands on something
    /// else: it is brought up, the keyboard is put away if it still covers it, and the tap aims
    /// above the field's middle.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<3 where field.frame.maxY > screen.minY + screen.height * 0.6 { app.swipeUp() }
        let keyboard = app.keyboards.firstMatch
        // The keyboard plus its bar: the bar is not part of the keyboard's frame.
        if keyboard.exists, field.frame.maxY > keyboard.frame.minY - 80 { app.swipeDown() }
        for _ in 0..<3 where (field.value(forKey: "hasKeyboardFocus") as? Bool) != true {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
            usleep(400_000)
        }
        field.typeText(text)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMiDinero() {
        let app = launch(["-centavo-dinero-demo"])
        snap("40-hoy-con-pestanas")
        app.tabBars.buttons["Mi dinero"].tap()
        XCTAssertTrue(app.staticTexts["dinero-patrimonio"].waitForExistence(timeout: 5), "No abrió «Mi dinero»")
        sleep(1)
        snap("41-mi-dinero")
        app.swipeUp()
        sleep(1)
        snap("42-mi-dinero-cuentas")
        app.buttons["dinero-hacer-corte"].tap()
        let month = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Corte de'")).firstMatch
        if month.waitForExistence(timeout: 3) { month.tap() }
        sleep(1)
        snap("43-corte")
        let keep = app.buttons["corte-sin-cambio-CETES"]
        if keep.waitForExistence(timeout: 3) { keep.tap(); sleep(1) }
        snap("44-corte-un-revisado")
    }

    func testMiDineroVacio() {
        let app = launch(["-centavo-dinero-vacio", "-centavo-dibujos-quietos"])
        app.tabBars.buttons["Mi dinero"].tap()
        XCTAssertTrue(app.buttons["dinero-primera-cuenta"].waitForExistence(timeout: 5))
        sleep(3)
        snap("45-mi-dinero-presentacion")
        app.buttons["dinero-primera-cuenta"].tap()
        XCTAssertTrue(app.textFields["fila-nombre"].waitForExistence(timeout: 5), "No abrió el paso 1")
        sleep(2)
        snap("46-paso-1")
        type("Nu cajita", into: app.textFields["fila-nombre"], in: app)
        type("185000", into: app.textFields["fila-monto"], in: app)
        type("10.5", into: app.textFields["fila-tasa"], in: app)
        snap("47-paso-1-llenando")
        app.buttons["fila-listo"].tap()
        sleep(1)
        app.buttons["tipo-inversion"].tap()
        sleep(2)
        snap("48-paso-1-inversion")
        app.swipeUp()
        let dollars = app.buttons["moneda-USD"]
        if dollars.waitForExistence(timeout: 3) && dollars.isHittable { dollars.tap() }
        sleep(1)
        snap("49-moneda-dolares")
        app.buttons["recorrido-siguiente"].tap()
        sleep(2)
        snap("50-paso-2")
        app.buttons["recorrido-saltar"].tap()
        sleep(2)
        snap("51-paso-3")
        XCTAssertTrue(app.buttons["recorrido-saltar"].waitForExistence(timeout: 5))
        app.buttons["recorrido-saltar"].tap()
        sleep(3)
        snap("52-paso-4")
        app.buttons["recorrido-siguiente"].tap()
        XCTAssertTrue(app.staticTexts["dinero-patrimonio"].waitForExistence(timeout: 5), "No llegó a «Mi dinero»")
        snap("53-mi-dinero-listo")
    }

    func testMiDineroDesdeExcel() {
        let app = launch(["-centavo-dinero-vacio", "-centavo-importar-ejemplo", "-centavo-dibujos-quietos"])
        app.tabBars.buttons["Mi dinero"].tap()
        XCTAssertTrue(app.buttons["dinero-primera-cuenta"].waitForExistence(timeout: 5))
        app.buttons["dinero-primera-cuenta"].tap()
        XCTAssertTrue(app.buttons["recorrido-excel"].waitForExistence(timeout: 5), "No está «¿Lo tienes en Excel?»")
        snap("60-paso-1-con-excel")
        app.buttons["recorrido-excel"].tap()
        XCTAssertTrue(app.buttons["importar-copiar"].waitForExistence(timeout: 5))
        snap("61-excel-instrucciones")
        app.buttons["importar-ejemplo"].tap()
        XCTAssertTrue(app.staticTexts["importar-resumen"].waitForExistence(timeout: 5), "No mostró la revisión")
        sleep(1)
        snap("62-excel-revision")
        app.swipeUp()
        sleep(1)
        snap("63-excel-revision-abajo")
        let save = app.buttons["importar-guardar"]
        XCTAssertFalse(save.isEnabled, "Sin el tipo de cambio del euro no debe guardar")
        let euro = app.textFields["importar-cambio-EUR"]
        if euro.waitForExistence(timeout: 3) {
            euro.tap()
            euro.typeText("20")
            app.buttons["Ocultar teclado"].tap()
        }
        XCTAssertTrue(save.waitForExistence(timeout: 3) && save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["recorrido-siguiente"].waitForExistence(timeout: 5))
        sleep(1)
        snap("64-paso-1-importado")
        app.buttons["recorrido-siguiente"].tap()
        sleep(1)
        snap("65-paso-2-importado")
        app.buttons["recorrido-siguiente"].tap()
        sleep(1)
        app.buttons["recorrido-siguiente"].tap()
        sleep(3)
        snap("66-paso-4-ingresos")
    }

    func testRespaldo() {
        let app = launch()
        app.buttons["Más"].tap()
        XCTAssertTrue(app.buttons["Ajustes"].waitForExistence(timeout: 5))
        app.buttons["Ajustes"].tap()
        let backup = app.buttons["ajustes-respaldo"]
        XCTAssertTrue(backup.waitForExistence(timeout: 5))
        snap("30-ajustes-respaldo")
        backup.tap()
        sleep(1)
        snap("31-respaldo-sin-configurar")
        let password = app.secureTextFields["respaldo-contrasena"]
        if password.waitForExistence(timeout: 3) {
            password.tap()
            password.typeText("clave-de-prueba")
            let again = app.secureTextFields["respaldo-repite"]
            again.tap()
            again.typeText("clave-de-prueba")
            app.buttons["respaldo-guardar-contrasena"].tap()
            sleep(1)
        }
        snap("32-respaldo-con-contrasena")
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

    /// The four pages of the welcome, one launch each (the app opens on the page asked for).
    func testBienvenida() {
        for page in 0...4 {
            let app = XCUIApplication()
            XCUIDevice.shared.appearance = .dark
            app.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX", "-centavo-empty",
                                   "-centavo-onboarding", "-centavo-bienvenida-pagina", "\(page)",
                                   "-centavo-dibujos-quietos"]
            app.launch()
            XCTAssertTrue(app.buttons["bienvenida-siguiente"].waitForExistence(timeout: 20)
                          || app.buttons["bienvenida-configurar"].waitForExistence(timeout: 5), "No abrió la bienvenida")
            sleep(page == 0 ? 3 : 1)
            snap("70-bienvenida-\(page + 1)")
            if page == 0 {
                sleep(3)
                snap("70-bienvenida-1b")
            }
            app.terminate()
        }
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

    func testGuia() throws {
        let app = launch()
        app.buttons["Más"].tap()
        app.buttons["Configurar atajo"].tap()
        // On iOS 27 «Configurar atajo» adds the ready-made shortcut instead (2026-10-29): the
        // step-by-step guide is the iOS 26 path.
        try XCTSkipUnless(app.buttons["guia-siguiente"].waitForExistence(timeout: 5),
                          "Sin guía paso a paso en esta versión de iOS")
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
        app.buttons["parte-Ropa"].tap()
        sleep(1)
        snap("04-principal-mosaico-ropa")
    }

    func testPrincipalMosaicoDetalle() {
        let app = launch(["-whereItGoesStyle", "mosaic"])
        app.buttons["parte-Despensa"].press(forDuration: 1.2)
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
        XCTAssertTrue(app.textFields["monto"].waitForExistence(timeout: 5), "No abrió el gasto")
        // «Tipo: No cuenta» opens «Más detalles» by itself; on CI's smaller iPhone even its row is
        // below the fold, and the form only makes rows once scrolled to.
        for _ in 0..<4 where !app.buttons["mas-detalles"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["mas-detalles"].waitForExistence(timeout: 5), "No está «Más detalles»")
        for _ in 0..<4 where !app.buttons["tipo"].exists { app.swipeUp() }
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
        let bar = app.buttons["ver-cuenta"]
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
