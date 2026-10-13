import XCTest

/// Uses the app the way a person does and checks what comes out. Each test starts from a
/// fresh in-memory store, so none depends on another.
@MainActor
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
        if refund { app.switches["devolucion"].tap() }
    }

    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
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

        fillExpense(app, amount: "USD 20", merchant: "Steam")
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
        app.buttons["hoja-cancelar"].firstMatch.tap()
        app.buttons["hoja-cancelar"].firstMatch.tap()
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
