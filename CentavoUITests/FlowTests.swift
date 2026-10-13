import XCTest

/// Uses the app the way a person does and checks what comes out. Each test starts from a
/// fresh in-memory store, so none depends on another.
final class FlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(demo: Bool = false, budget: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX"]
        arguments += [demo ? "-centavo-demo" : "-centavo-empty"]
        if budget { arguments += ["-monthlyBudget", "8000"] }
        app.launchArguments = arguments
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

    /// Opens the new-expense sheet and fills it in. Leaves the sheet open.
    private func fillExpense(_ app: XCUIApplication, amount: String, merchant: String,
                             refund: Bool = false) {
        app.buttons["Anotar gasto"].tap()
        let amountField = app.textFields["Monto"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 10), "No abrió la hoja de gasto")
        amountField.tap()
        amountField.typeText(amount)
        let merchantField = app.textFields["Comercio"]
        merchantField.tap()
        merchantField.typeText(merchant)
        if refund { app.switches.firstMatch.tap() }
    }

    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    // MARK: Anotar

    func testAnotarUnGastoLoSumaAlTotalYApareceEnLaLista() {
        let app = launch()
        fillExpense(app, amount: "123.45", merchant: "Taquería Prueba")
        app.buttons["Guardar"].tap()

        XCTAssertTrue(row(app, containing: "Taquería Prueba").waitForExistence(timeout: 10),
                      "El gasto no apareció en la lista")
        XCTAssertTrue(app.staticTexts["$123.45"].waitForExistence(timeout: 5),
                      "El total del mes no se actualizó")
        snap("flujo-anotar")
    }

    func testUnaDevolucionRestaDelTotal() {
        let app = launch()
        fillExpense(app, amount: "100", merchant: "Tienda")
        app.buttons["Guardar"].tap()
        XCTAssertTrue(app.staticTexts["$100.00"].waitForExistence(timeout: 10))

        fillExpense(app, amount: "30", merchant: "Tienda", refund: true)
        app.buttons["Guardar"].tap()
        XCTAssertTrue(app.staticTexts["$70.00"].waitForExistence(timeout: 10),
                      "La devolución no restó")
        XCTAssertTrue(row(app, containing: "+30.00").exists, "La devolución no sale como +30.00")
        snap("flujo-devolucion")
    }

    func testUnGastoEnOtraMonedaNoSeMezclaConElTotal() {
        let app = launch()
        fillExpense(app, amount: "50", merchant: "Super")
        app.buttons["Guardar"].tap()
        XCTAssertTrue(app.staticTexts["$50.00"].waitForExistence(timeout: 10))

        fillExpense(app, amount: "USD 20", merchant: "Steam")
        app.buttons["Guardar"].tap()
        XCTAssertTrue(app.staticTexts["+ USD 20.00 aparte"].waitForExistence(timeout: 10),
                      "El gasto en USD no salió aparte")
        XCTAssertTrue(app.staticTexts["$50.00"].exists, "El total mezcló monedas")
        snap("flujo-otra-moneda")
    }

    func testEscribirPesosNoSacaElGastoDelTotal() {
        let app = launch()
        fillExpense(app, amount: "89 pesos", merchant: "Oxxo")
        app.buttons["Guardar"].tap()
        XCTAssertTrue(app.staticTexts["$89.00"].waitForExistence(timeout: 10),
                      "«89 pesos» no contó en el total")
    }

    func testNoSePuedeGuardarCeroNiUnMontoAbsurdo() {
        let app = launch()
        fillExpense(app, amount: "0", merchant: "Nada")
        XCTAssertFalse(app.buttons["Guardar"].isEnabled, "Dejó guardar un gasto de $0")

        let amount = app.textFields["Monto"]
        amount.tap()
        amount.clearAndType("1234567890123")
        XCTAssertFalse(app.buttons["Guardar"].isEnabled, "Dejó guardar un monto de 13 dígitos")
        snap("flujo-monto-invalido")
    }

    func testSinMontoOSinComercioNoSePuedeGuardar() {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        XCTAssertTrue(app.textFields["Monto"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Guardar"].isEnabled)
        app.textFields["Monto"].tap()
        app.textFields["Monto"].typeText("10")
        XCTAssertFalse(app.buttons["Guardar"].isEnabled, "Dejó guardar sin comercio")
    }

    // MARK: Editar y borrar

    func testEditarUnGastoCambiaLaListaYElTotal() {
        let app = launch(demo: true)
        row(app, containing: "Cinépolis").tap()
        let amount = app.textFields["Monto"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap()
        amount.clearAndType("999")
        app.buttons["Guardar"].tap()
        XCTAssertTrue(row(app, containing: "999.00").waitForExistence(timeout: 10),
                      "El monto editado no aparece")
        snap("flujo-editar")
    }

    func testBorrarPideConfirmacionYLuegoQuitaElGasto() {
        let app = launch(demo: true)
        row(app, containing: "Cinépolis").tap()
        XCTAssertTrue(app.buttons["Borrar gasto"].waitForExistence(timeout: 10))
        app.buttons["Borrar gasto"].tap()

        let confirm = app.buttons["Borrar"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No pidió confirmación")
        snap("flujo-confirmar-borrado")
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(row(app, containing: "Cinépolis")),
                      "El gasto sigue en la lista")
    }

    func testCancelarLaConfirmacionNoBorra() {
        let app = launch(demo: true)
        row(app, containing: "Cinépolis").tap()
        app.buttons["Borrar gasto"].tap()
        XCTAssertTrue(app.buttons["Borrar"].waitForExistence(timeout: 5))
        app.buttons["Cancelar"].firstMatch.tap()
        app.buttons["Cancelar"].firstMatch.tap()
        XCTAssertTrue(row(app, containing: "Cinépolis").waitForExistence(timeout: 5),
                      "Se borró aunque se canceló")
    }

    // MARK: Presupuesto

    func testFijarYQuitarElPresupuesto() {
        let app = launch(demo: true)
        app.buttons["Presupuesto"].tap()
        XCTAssertTrue(app.buttons["Fijar presupuesto"].waitForExistence(timeout: 5),
                      "No ofrece fijar el presupuesto")

        app.buttons["Fijar presupuesto"].tap()
        let field = app.textFields["Presupuesto"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("5000")
        app.buttons["Guardar"].tap()

        let summary = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS 'Presupuesto de'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "No apareció el ticket del presupuesto")
        snap("flujo-presupuesto-fijado")

        app.buttons["Más"].tap()
        app.buttons["Presupuesto del mes"].tap()
        XCTAssertTrue(app.buttons["Quitar presupuesto"].waitForExistence(timeout: 10))
        app.buttons["Quitar presupuesto"].tap()
        XCTAssertTrue(app.buttons["Fijar presupuesto"].waitForExistence(timeout: 10),
                      "No quitó el presupuesto")
    }

    func testPasarseDelPresupuestoLoDice() {
        let app = launch()
        app.buttons["Más"].tap()
        app.buttons["Presupuesto del mes"].tap()
        let field = app.textFields["Presupuesto"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("100")
        app.buttons["Guardar"].tap()

        fillExpense(app, amount: "250", merchant: "Antojo")
        app.buttons["Guardar"].tap()
        app.buttons["Presupuesto"].tap()
        let over = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS 'Te pasaste'")).firstMatch
        XCTAssertTrue(over.waitForExistence(timeout: 10), "No avisó que se pasó del presupuesto")
        snap("flujo-pasado-de-presupuesto")
    }

    // MARK: Utilidades

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
