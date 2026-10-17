import XCTest

/// Uses the app the way a person does and checks what comes out. Each test starts from a
/// fresh in-memory store, so none depends on another.
@MainActor
final class FlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .dark
    }

    // MARK: Helpers

    private func launch(demo: Bool = false, budget: Bool = false,
                        extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX",
                         ]
        arguments += [demo ? "-centavo-demo" : "-centavo-empty"]
        if budget { arguments += ["-monthlyBudget", "8000"] }
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.buttons["Anotar gasto"].waitForExistence(timeout: 20),
                      "La pantalla principal no abrió")
        return app
    }

    /// Waits for an element; if it never shows up, attaches the screen and its hierarchy so the
    /// failure can be diagnosed without guessing, then fails.
    @discardableResult
    private func require(_ element: XCUIElement, _ message: String,
                         timeout: TimeInterval = 10) -> XCUIElement {
        if !element.waitForExistence(timeout: timeout) {
            snap("fallo-\(message.prefix(40))")
            let tree = XCTAttachment(string: XCUIApplication().debugDescription)
            tree.name = "jerarquia"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail(message)
        }
        return element
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Opens the new-expense sheet and fills it in. Leaves the sheet open.
    private func fillExpense(_ app: XCUIApplication, amount: String, merchant: String,
                             refund: Bool = false) {
        app.buttons["Anotar gasto"].tap()
        let amountField = require(app.textFields["monto"], "No abrió la hoja de gasto")
        amountField.tap()
        amountField.typeText(amount)
        let merchantField = app.textFields["comercio"]
        merchantField.tap()
        merchantField.typeText(merchant)
        if refund {
            app.switches["devolucion"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
    }

    /// The row for a payment. The list is lazy, so a row off screen is not in the hierarchy
    /// at all: scroll down, then back up, until it turns up.
    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        let element = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if element.exists { return element }
        for _ in 0..<4 where !element.exists { app.swipeUp() }
        for _ in 0..<8 where !element.exists { app.swipeDown() }
        return element
    }

    // MARK: Anotar

    func testAnotarUnGastoLoSumaAlTotalYApareceEnLaLista() {
        let app = launch()
        fillExpense(app, amount: "123.45", merchant: "Taquería Prueba")
        app.buttons["hoja-guardar"].tap()

        require(row(app, containing: "Taquería Prueba"), "El gasto no apareció en la lista")
        expectTotal(app, "$123.45")
        snap("flujo-anotar")
    }

    func testUnaDevolucionRestaDelTotal() {
        let app = launch()
        fillExpense(app, amount: "100", merchant: "Tienda")
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$100.00")

        fillExpense(app, amount: "30", merchant: "Tienda", refund: true)
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$70.00", "La devolución no restó")
        XCTAssertTrue(row(app, containing: "+30.00").exists, "La devolución no sale como +30.00")
        snap("flujo-devolucion")
    }

    func testUnGastoEnOtraMonedaNoSeMezclaConElTotal() {
        let app = launch()
        fillExpense(app, amount: "50", merchant: "Super")
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$50.00")

        fillExpense(app, amount: "20", merchant: "Steam")
        app.buttons["USD"].tap()
        app.buttons["hoja-guardar"].tap()
        let others = require(app.staticTexts["otras-monedas"], "El gasto en USD no salió aparte")
        XCTAssertTrue(others.label.contains("USD 20.00"), "Otras monedas dice: \(others.label)")
        expectTotal(app, "$50.00", "El total mezcló monedas")
        snap("flujo-otra-moneda")
    }

    func testEscribirPesosNoSacaElGastoDelTotal() {
        let app = launch()
        fillExpense(app, amount: "89 pesos", merchant: "Oxxo")
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$89.00", "«89 pesos» no contó en el total")
    }

    func testNoSePuedeGuardarCeroNiUnMontoAbsurdo() {
        let app = launch()
        fillExpense(app, amount: "0", merchant: "Nada")
        XCTAssertFalse(app.buttons["hoja-guardar"].isEnabled, "Dejó guardar un gasto de $0")

        let amount = app.textFields["monto"]
        amount.tap()
        amount.clearAndType("1234567890123")
        XCTAssertFalse(app.buttons["hoja-guardar"].isEnabled, "Dejó guardar un monto de 13 dígitos")
        snap("flujo-monto-invalido")
    }

    func testSinMontoOSinComercioNoSePuedeGuardar() {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        require(app.textFields["monto"], "No abrió la hoja de gasto")
        XCTAssertFalse(app.buttons["hoja-guardar"].isEnabled)
        app.textFields["monto"].tap()
        app.textFields["monto"].typeText("10")
        XCTAssertFalse(app.buttons["hoja-guardar"].isEnabled, "Dejó guardar sin comercio")
    }

    // MARK: Editar y borrar

    func testEditarUnGastoCambiaLaListaYElTotal() {
        let app = launch(demo: true)
        require(row(app, containing: "Cinépolis"), "No hay fila de Cinépolis").tap()
        let amount = require(app.textFields["monto"], "No abrió la hoja de edición")
        amount.tap()
        amount.clearAndType("999")
        app.buttons["hoja-guardar"].tap()
        XCTAssertTrue(row(app, containing: "999.00").waitForExistence(timeout: 10),
                      "El monto editado no aparece")
        snap("flujo-editar")
    }

    func testBorrarPideConfirmacionYLuegoQuitaElGasto() {
        let app = launch(demo: true)
        require(row(app, containing: "Cinépolis"), "No hay fila de Cinépolis").tap()
        require(app.buttons["borrar-gasto"], "No hay botón de borrar").tap()

        let confirm = require(app.buttons["Borrar"], "No pidió confirmación")
        snap("flujo-confirmar-borrado")
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(row(app, containing: "Cinépolis")),
                      "El gasto sigue en la lista")
    }

    func testCancelarLaConfirmacionNoBorra() {
        let app = launch(demo: true)
        require(row(app, containing: "Cinépolis"), "No hay fila de Cinépolis").tap()
        require(app.buttons["borrar-gasto"], "No hay botón de borrar").tap()
        require(app.buttons["Borrar"], "No pidió confirmación")
        // On iOS 26 the dialog is a popover with no Cancel of its own: tapping outside dismisses it.
        let dialogCancel = app.buttons.matching(NSPredicate(
            format: "label == 'Cancelar' AND identifier != 'hoja-cancelar'")).firstMatch
        if dialogCancel.waitForExistence(timeout: 2) {
            dialogCancel.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        require(app.buttons["hoja-cancelar"], "La hoja de edición se cerró").tap()
        XCTAssertTrue(row(app, containing: "Cinépolis").waitForExistence(timeout: 5),
                      "Se borró aunque se canceló")
    }

    // MARK: Presupuesto

    func testFijarYQuitarElPresupuesto() {
        let app = launch(demo: true)
        app.buttons["Presupuesto"].tap()
        require(app.buttons["fijar-presupuesto"], "No ofrece fijar el presupuesto").tap()
        let field = require(app.textFields["presupuesto-monto"], "No abrió la hoja del presupuesto")
        field.tap()
        field.typeText("5000")
        app.buttons["hoja-guardar"].tap()

        let ticket = require(app.otherElements["presupuesto-ticket"],
                             "No apareció el ticket del presupuesto")
        XCTAssertTrue(ticket.label.contains("$5,000.00"), "El ticket dice: \(ticket.label)")
        snap("flujo-presupuesto-fijado")

        app.buttons["Más"].tap()
        app.buttons["Presupuesto del mes"].tap()
        require(app.buttons["quitar-presupuesto"], "No ofrece quitar el presupuesto").tap()
        require(app.buttons["fijar-presupuesto"], "No quitó el presupuesto")
    }

    func testPasarseDelPresupuestoLoDice() {
        let app = launch()
        app.buttons["Más"].tap()
        app.buttons["Presupuesto del mes"].tap()
        let field = require(app.textFields["presupuesto-monto"], "No abrió la hoja del presupuesto")
        field.tap()
        field.typeText("100")
        app.buttons["hoja-guardar"].tap()

        fillExpense(app, amount: "250", merchant: "Antojo")
        app.buttons["hoja-guardar"].tap()
        app.buttons["Presupuesto"].tap()
        let ticket = require(app.otherElements["presupuesto-ticket"], "No apareció el ticket")
        XCTAssertTrue(ticket.label.contains("Te pasaste"), "El ticket dice: \(ticket.label)")
        snap("flujo-pasado-de-presupuesto")
        expectFitsOnScreen(app, ticket)
    }

    /// Opening the app already over budget once locked the page wider than the screen:
    /// "Gastado" and the budget line were cut off and the brass spilled onto the calendar.
    func testAbrirYaPasadoDelPresupuestoCabeEnPantalla() {
        let app = launch(demo: true, extra: ["-monthlyBudget", "1000"])
        app.buttons["Presupuesto"].tap()
        let ticket = require(app.otherElements["presupuesto-ticket"], "No apareció el ticket")
        XCTAssertTrue(ticket.label.contains("Te pasaste"), "El ticket dice: \(ticket.label)")
        // $2,366 spent of a $1,000 budget, the demo month.
        XCTAssertTrue(ticket.label.contains("el 237"), "No dice el porcentaje: \(ticket.label)")
        snap("flujo-abre-pasado-de-presupuesto")
        expectFitsOnScreen(app, ticket)
    }

    /// Accessibility frames are clipped to what is visible, so "inside the screen" proves
    /// nothing. The ticket has to keep the same margins as the total above it.
    private func expectFitsOnScreen(_ app: XCUIApplication, _ element: XCUIElement) {
        let total = app.staticTexts["total-mes"].frame
        let screen = app.windows.firstMatch.frame
        let margin = total.minX - screen.minX
        XCTAssertEqual(element.frame.minX, total.minX, accuracy: 1,
                       "No respeta el margen izquierdo: \(element.frame), total en \(total)")
        XCTAssertEqual(element.frame.maxX, screen.maxX - margin, accuracy: 1,
                       "No respeta el margen derecho: \(element.frame) en \(screen)")
    }

    // MARK: En qué se va

    func testElPresupuestoDiceEnQueSeVa() {
        let app = launch(demo: true, budget: true)
        let shares = require(app.descendants(matching: .any)["en-que-se-va"], "No dice en qué se va")
        XCTAssertTrue(app.staticTexts["Ropa: 42 % de lo gastado"].exists
                      || shares.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Ropa'")).count > 0,
                      "No aparece la categoría más grande")
    }

    // MARK: Salud de la captura

    func testDiceCuandoLlegoElUltimoPagoDeWallet() {
        let app = launch(demo: true)
        let health = require(app.buttons["salud-captura"], "No dice cómo va la captura")
        XCTAssertTrue(health.label.localizedCaseInsensitiveContains("último pago"), "Dice: \(health.label)")
    }

    func testSinPagosDeWalletInvitaAConfigurarYAbreLaGuia() {
        let app = launch(budget: true, extra: ["-centavo-demo-large"])
        let health = require(app.buttons["salud-captura"], "No dice cómo va la captura")
        XCTAssertTrue(health.label.localizedCaseInsensitiveContains("sin conectar"), "Dice: \(health.label)")
        health.tap()
        require(app.buttons["guia-siguiente"], "No abrió la guía")
    }

    // MARK: Guía del atajo

    /// Opens the guide from the menu, or from the empty screen on a first launch.
    private func walkGuideToTheEnd(_ app: XCUIApplication, fromMenu: Bool = true) -> XCUIElement {
        if fromMenu { app.buttons["Más"].tap() }
        app.buttons["Configurar atajo"].firstMatch.tap()
        let next = require(app.buttons["guia-siguiente"], "No abrió la guía paso a paso")
        // 8 steps on iOS 26, 7 on iOS 27: walk until the last one.
        for _ in 0..<10 where next.isEnabled { next.tap() }
        XCTAssertFalse(next.isEnabled, "La guía no tiene fin")
        return require(app.descendants(matching: .any)["guia-comprobacion"], "El último paso no comprueba la captura")
    }

    func testLaGuiaEsperaElPrimerPago() {
        let check = walkGuideToTheEnd(launch(), fromMenu: false)
        XCTAssertTrue(check.label.contains("Esperando"), "Dice: \(check.label)")
        snap("flujo-guia-esperando")
    }

    func testLaGuiaConfirmaQueLaCapturaFunciona() {
        let check = walkGuideToTheEnd(launch(demo: true))
        XCTAssertTrue(check.label.contains("Ya funciona"), "Dice: \(check.label)")
        XCTAssertTrue(check.label.contains("Oxxo"), "Dice: \(check.label)")
        snap("flujo-guia-funciona")
    }

    // MARK: Meses

    func testNavegarAMesesAnterioresMuestraSusDatos() {
        let app = launch(demo: true, budget: true)
        XCTAssertFalse(app.buttons["Mes siguiente"].isEnabled, "No debería poder ir al futuro")
        require(row(app, containing: "Cinépolis"), "El mes actual no muestra sus pagos")

        app.buttons["Mes anterior"].tap()
        // Last month in the demo data: 880 + 2,400 + 150 + 399.
        expectTotal(app, "$3,829.00", "El total del mes anterior no es el esperado")
        require(row(app, containing: "Renta"), "El mes anterior no muestra sus pagos")
        XCTAssertFalse(row(app, containing: "Cinépolis").exists,
                       "Los pagos de este mes aparecen en el mes anterior")
        XCTAssertFalse(app.buttons["Mes anterior"].isEnabled,
                       "Dejó ir más atrás del primer gasto")
        // The budget is what the screen opens on.
        let ticket = require(app.otherElements["presupuesto-ticket"], "No hay ticket del mes anterior")
        XCTAssertTrue(ticket.label.contains("Te quedaron"), "Dice: \(ticket.label)")
        XCTAssertFalse(ticket.label.contains("A hoy"), "Un mes cerrado no tiene «hoy»")
        snap("flujo-mes-anterior-presupuesto")

        app.buttons["Calendario"].tap()
        snap("flujo-mes-anterior-calendario")

        app.buttons["Mes siguiente"].tap()
        require(row(app, containing: "Cinépolis"), "No regresó al mes actual")
    }

    func testAnotarMientrasSeVeUnMesAnteriorLoPoneEnESeMes() {
        let app = launch(demo: true)
        app.buttons["Mes anterior"].tap()
        expectTotal(app, "$3,829.00")

        fillExpense(app, amount: "100", merchant: "Retroactivo")
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$3,929.00", "El gasto no cayó en el mes que se estaba viendo")
        require(row(app, containing: "Retroactivo"), "No aparece en el mes anterior")

        app.buttons["Mes siguiente"].tap()
        require(row(app, containing: "Cinépolis"), "No regresó al mes actual")
        XCTAssertFalse(row(app, containing: "Retroactivo").exists,
                       "El gasto del mes pasado aparece en este mes")
    }

    // MARK: Volumen

    func testConCincoMilGastosLaPantallaAbreYRespondeDeprisa() {
        let started = Date()
        let app = launch(budget: true, extra: ["-centavo-demo-large"])
        let opened = Date().timeIntervalSince(started)

        // Scroll the ledger a long way, then come back and use the app.
        let scrolled = Date()
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        let scrolling = Date().timeIntervalSince(scrolled)

        let editorStarted = Date()
        app.buttons["Anotar gasto"].tap()
        require(app.textFields["monto"], "No abrió la hoja de gasto con 5,000 gastos")
        let editorOpened = Date().timeIntervalSince(editorStarted)

        let report = XCTAttachment(string: String(format:
            "Abrir con 5,000 gastos: %.1f s\nDesplazar 6 veces: %.1f s\nAbrir la hoja de gasto: %.1f s",
            opened, scrolling, editorOpened))
        report.name = "tiempos-5000-gastos"
        report.lifetime = .keepAlways
        add(report)
        snap("flujo-5000-gastos")

        XCTAssertLessThan(opened, 25, "Abrir con 5,000 gastos tardó \(opened) s")
        XCTAssertLessThan(editorOpened, 10, "Abrir la hoja con 5,000 gastos tardó \(editorOpened) s")
    }

    // MARK: Base de datos

    func testSiLaBaseNoAbreSeExplicaEnVezDeCerrarse() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX",
                               "-centavo-broken-store"]
        app.launch()
        require(app.staticTexts["No se pudo abrir tu base de datos"],
                "No mostró la pantalla de error de la base")
        XCTAssertFalse(app.buttons["Anotar gasto"].exists)
        snap("flujo-error-base")
    }

    // MARK: Utilidades

    private func expectTotal(_ app: XCUIApplication, _ expected: String,
                             _ message: String = "El total del mes no es el esperado") {
        let total = require(app.staticTexts["total-mes"], "No hay total del mes")
        let predicate = NSPredicate(format: "label == %@", expected)
        let matched = XCTNSPredicateExpectation(predicate: predicate, object: total)
        if XCTWaiter().wait(for: [matched], timeout: 10) != .completed {
            XCTFail("\(message): esperaba \(expected) y dice \(total.label)")
        }
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}

private extension XCUIElement {
    /// Replaces whatever is in the field.
    func clearAndType(_ text: String) {
        guard let current = value as? String, !current.isEmpty else {
            typeText(text)
            return
        }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}

// MARK: - Auditoría de accesibilidad

/// Runs Apple's own accessibility audit on each screen and writes every finding to an
/// attachment. It reports rather than fails, so the findings can be read and fixed.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(demo: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX",
                               demo ? "-centavo-demo" : "-centavo-empty",
                               "-monthlyBudget", "8000"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Anotar gasto"].waitForExistence(timeout: 20))
        return app
    }

    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        var findings: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                findings.append("[\(issue.auditType.rawValue)] \(issue.compactDescription) — "
                                + "\(issue.element?.debugDescription.prefix(160) ?? "sin elemento")")
                return true
            }
        } catch let error as NSError where error.code == -56 {
            // "Audit failed to complete in time": the CI runner is slow on busy screens. This
            // audit only reports, so a timeout is noted instead of failing the PR.
            findings.append("La auditoría no terminó a tiempo: \(error.localizedDescription)")
        }
        let report = XCTAttachment(string: findings.isEmpty
                                   ? "Sin hallazgos en \(screen)"
                                   : "\(findings.count) hallazgos en \(screen):\n" + findings.joined(separator: "\n"))
        report.name = "auditoria-\(screen)"
        report.lifetime = .keepAlways
        add(report)
    }

    /// The one audit that fails the build: a tap target under 44 points is a bug, not a taste.
    func testZonasTactilesSonSuficientes() throws {
        var issues: [String] = []
        func check(_ app: XCUIApplication, _ screen: String) throws {
            try app.performAccessibilityAudit(for: .hitRegion) { issue in
                issues.append("\(screen): \(issue.compactDescription) — "
                              + "\(issue.element?.debugDescription.prefix(220) ?? "sin elemento")")
                return true
            }
        }
        let app = launch()
        try check(app, "principal")
        app.buttons["Calendario"].tap()
        try check(app, "calendario")
        app.buttons["Anotar gasto"].tap()
        XCTAssertTrue(app.textFields["monto"].waitForExistence(timeout: 10))
        try check(app, "hoja de gasto")
        XCTAssertTrue(issues.isEmpty, "Zonas táctiles menores de 44 pt:\n" + issues.joined(separator: "\n"))
    }

    func testAuditarPrincipal() throws { try audit(launch(), "principal-presupuesto") }

    func testAuditarCalendario() throws {
        let app = launch()
        app.buttons["Calendario"].tap()
        try audit(app, "principal-calendario")
    }

    func testAuditarPrimeraVez() throws { try audit(launch(demo: false), "primera-vez") }

    func testAuditarHojaDeGasto() throws {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        XCTAssertTrue(app.textFields["monto"].waitForExistence(timeout: 10))
        try audit(app, "hoja-de-gasto")
    }

    func testAuditarGuia() throws {
        let app = launch()
        app.buttons["Más"].tap()
        app.buttons["Configurar atajo"].tap()
        XCTAssertTrue(app.buttons["hoja-listo"].waitForExistence(timeout: 10))
        try audit(app, "guia")
    }

    func testAuditarLetraGrande() throws {
        try audit(launch(extra: ["-UIPreferredContentSizeCategoryName",
                                 "UICTContentSizeCategoryAccessibilityXXXL"]), "letra-grande")
    }
}
