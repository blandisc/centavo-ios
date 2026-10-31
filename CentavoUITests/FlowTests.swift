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
                         "-centavo-sin-animaciones"]
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

    /// Turns a switch on. Its knob sits at the right edge (the middle of the row is the label),
    /// and the keyboard may still be settling, so it retries and checks.
    private func turnOn(_ toggle: XCUIElement, _ name: String) {
        for _ in 0..<4 where (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            usleep(400_000)
        }
        XCTAssertEqual(toggle.value as? String, "1", "No se encendió «\(name)»")
    }

    /// Opens the new-expense sheet and fills it in. Leaves the sheet open.
    private func fillExpense(_ app: XCUIApplication, amount: String, merchant: String,
                             refund: Bool = false) {
        app.buttons["Anotar gasto"].tap()
        let amountField = require(app.textFields["monto"], "No abrió la hoja de gasto")
        amountField.tap()
        amountField.typeAmount(amount)
        let merchantField = require(app.textFields["comercio"], "No está el comercio")
        merchantField.tap()
        merchantField.typeText(merchant)
        if refund {
            pickKind(app, "Devolución")
        }
    }

    /// «Más detalles» open: «Tipo», «Fecha» and «Se repite» are under it.
    private func openDetails(_ app: XCUIApplication) {
        let details = app.buttons["mas-detalles"]
        for _ in 0..<6 where !isClear(details, app) { scrollForm(app) }
        require(details, "No está «Más detalles»")
        if !app.buttons["tipo"].exists { details.tap() }
        require(app.buttons["tipo"], "«Más detalles» no se abrió")
    }

    /// «Tipo» in the expense sheet: «Gasto», «Devolución» or «No cuenta».
    private func pickKind(_ app: XCUIApplication, _ kind: String) {
        openDetails(app)
        let picker = app.buttons["tipo"]
        for _ in 0..<4 where !isClear(picker, app) { scrollForm(app) }
        picker.tap()
        require(app.buttons[kind], "«Tipo» no ofrece «\(kind)»").tap()
    }

    /// The currency next to the amount, a menu since 2026-10-29.
    private func pickCurrency(_ app: XCUIApplication, _ code: String) {
        for _ in 0..<4 where !app.buttons["moneda"].isHittable { app.swipeDown() }
        require(app.buttons["moneda"], "No está la moneda junto al monto").tap()
        require(app.buttons[code], "La moneda no ofrece \(code)").tap()
    }

    /// The row for a payment. The list is lazy, so a row off screen is not in the hierarchy
    /// at all: scroll down, then back up, until it turns up.
    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        let element = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if element.exists { return element }
        for _ in 0..<4 where !element.exists { scrollForm(app) }
        for _ in 0..<8 where !element.exists { app.swipeDown() }
        return element
    }

    /// Scrolls a list row until the month bar is no longer sitting on it. `swipeUp()` starts
    /// mid-screen and can change the carousel page, so this drags from the list itself.
    ///
    /// The demo's Uber of today («No cuenta») is two lines of meta and pushed Cinépolis
    /// under the glass of «OCT 2026»; a swipe there hits the bar instead of the row. The
    /// app is fine: SwipeToDelete still works on a row you can actually touch.
    private func uncoverListRow(_ app: XCUIApplication, _ element: XCUIElement) {
        let bar = app.toolbars.firstMatch
        for _ in 0..<8 {
            guard element.exists else { return }
            let limit = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if element.frame.maxY <= limit { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            start.press(forDuration: 0.05,
                        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
        }
    }

    /// Whether a payment is in the list, without the long search `row` does when it is not:
    /// these months are short, so two swipes reach the bottom.
    private func hasRow(_ app: XCUIApplication, containing text: String) -> Bool {
        let element = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        for _ in 0..<2 where !element.exists { scrollForm(app) }
        return element.exists
    }

    /// «Borrar gasto» sits at the bottom of the sheet, under the categories: on a smaller
    /// phone it has to be scrolled to.
    private func deleteButton(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["borrar-gasto"]
        require(app.textFields["monto"], "No abrió el gasto")
        for _ in 0..<4 where !isClear(button, app) { scrollForm(app) }
        return require(button, "No hay botón de borrar")
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

    // MARK: Girar el teléfono

    /// Back from landscape, the screen fits the phone again: each row starting at the left
    /// margin, not left wider and pushed off to the left; and the carousel resting square on its
    /// page, on either page and after several turns, not halfway with the other one peeking in
    /// and the calendar cut short (owner, 2026-10-27).
    func testAlGirarLaPantallaSeAcomoda() {
        let app = launch(demo: true, budget: true)
        // The carousel's first page is «En qué se va»; the bar stays over it (2026-10-29).
        let budget = app.descendants(matching: .any)["en-que-se-va"]
        require(budget, "No está el carrusel")

        func turn(_ orientation: UIDeviceOrientation) {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
        }
        /// Where the calendar page stands: from its first day to its last.
        func calendarFrame() -> CGRect {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Día "))
                .allElementsBoundByIndex.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        }
        func expectResting(onCalendar: Bool, _ moment: String) {
            snap(moment)
            let screen = app.windows.firstMatch.frame
            let page = onCalendar ? calendarFrame() : budget.frame
            XCTAssertTrue(page.minX >= screen.minX && page.maxX <= screen.maxX,
                          "\(moment): la página quedó cortada: \(page) en \(screen)")
            // The carousel is as tall as the page: the dots right under it, not over its last row.
            let dots = app.buttons["Presupuesto"]
            XCTAssertGreaterThanOrEqual(dots.frame.minY, page.maxY - 1,
                                        "\(moment): la página quedó tapada: \(page), puntos en \(dots.frame)")
            if screen.width < screen.height {
                // Upright, the page's content runs from margin to margin (24 pt each side).
                XCTAssertEqual(page.minX, 24, accuracy: 1, "\(moment): la página quedó corrida: \(page)")
                XCTAssertEqual(page.width, screen.width - 48, accuracy: 1,
                               "\(moment): la página no mide lo que la pantalla: \(page) en \(screen)")
            }
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "$")).element(boundBy: 0)
            XCTAssertGreaterThanOrEqual(row.frame.minX, screen.minX, "\(moment): renglones corridos: \(row.frame)")
            XCTAssertLessThanOrEqual(row.frame.maxX, screen.maxX, "\(moment): renglones anchos: \(row.frame)")
        }

        turn(.landscapeLeft)
        expectResting(onCalendar: false, "horizontal-presupuesto")
        app.buttons["Calendario"].tap()
        sleep(1)
        turn(.portrait)
        expectResting(onCalendar: true, "vertical-calendario")
        turn(.landscapeRight)
        expectResting(onCalendar: true, "horizontal-calendario")
        app.buttons["Presupuesto"].tap()
        sleep(1)
        turn(.portrait)
        expectResting(onCalendar: false, "vertical-presupuesto")
    }

    func testUnaDevolucionRestaDelTotal() {
        let app = launch()
        fillExpense(app, amount: "100", merchant: "Tienda")
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$100.00")

        fillExpense(app, amount: "30", merchant: "Tienda", refund: true)
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$70.00", "La devolución no restó")
        XCTAssertTrue(row(app, containing: "+$30.00").exists, "La devolución no sale como +$30.00")
        snap("flujo-devolucion")
    }

    func testUnGastoEnOtraMonedaNoSeMezclaConElTotal() {
        let app = launch()
        fillExpense(app, amount: "50", merchant: "Super")
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$50.00")

        fillExpense(app, amount: "20", merchant: "Steam")
        pickCurrency(app, "USD")
        app.buttons["hoja-guardar"].tap()
        let others = require(app.staticTexts["otras-monedas"], "El gasto en USD no salió aparte")
        XCTAssertTrue(others.label.contains("USD 20.00"), "Otras monedas dice: \(others.label)")
        expectTotal(app, "$50.00", "El total mezcló monedas")
        snap("flujo-otra-moneda")
    }

    /// The owner's case: the main currency ended up in dollars while the payments are pesos.
    /// The screen offers to add up in pesos, and one tap fixes it.
    func testSiLosPagosSonEnPesosOfreceSumarEnPesos() {
        let app = launch(budget: true)
        app.buttons["Más"].tap()
        require(app.buttons["Ajustes"], "No está «Ajustes» en «Más»").tap()
        let currency = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Moneda principal'")).firstMatch
        require(currency, "No está la moneda en «Ajustes»").tap()
        require(app.buttons["Dólares (USD)"], "No ofrece dólares").tap()
        // Asking about the budget closes «Ajustes» if it is still up.
        if app.buttons["ajustes-listo"].waitForExistence(timeout: 2) { app.buttons["ajustes-listo"].tap() }
        require(app.buttons["Así está bien"], "No preguntó por el presupuesto al cambiar de moneda").tap()

        for (amount, merchant) in [("100", "Oxxo"), ("200", "Soriana")] {
            fillExpense(app, amount: amount, merchant: merchant)
            pickCurrency(app, "MXN")
            app.buttons["hoja-guardar"].tap()
        }
        require(app.buttons["sumar-en-moneda"], "No ofreció sumar en pesos")
        snap("flujo-sumar-en-pesos")
        app.buttons["sumar-en-moneda"].tap()
        require(app.buttons["Así está bien"], "No preguntó por el presupuesto").tap()
        expectTotal(app, "$300.00", "No quedó sumando en pesos")
        XCTAssertFalse(app.staticTexts["otras-monedas"].exists, "Los pesos siguen aparte")
        XCTAssertFalse(app.buttons["sumar-en-moneda"].exists, "La sugerencia no se fue")
    }

    /// A phone set to the US region still adds up in pesos unless told otherwise.
    func testConRegionDeEstadosUnidosSumaEnPesos() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "en_US",
                               "-centavo-sin-animaciones", "-centavo-demo"]
        app.launch()
        let total = require(app.staticTexts["total-mes"], "No abrió", timeout: 20)
        XCTAssertTrue(total.label.hasPrefix("$"), "El total dice \(total.label)")
        let others = require(app.staticTexts["otras-monedas"], "Los dólares no salieron aparte")
        XCTAssertTrue(others.label.contains("USD"), "Aparte dice \(others.label)")
    }

    func testEscribirPesosNoSacaElGastoDelTotal() {
        let app = launch()
        fillExpense(app, amount: "89 pesos", merchant: "Oxxo")
        app.buttons["hoja-guardar"].tap()
        expectTotal(app, "$89.00", "«89 pesos» no contó en el total")
    }

    /// Owner's feedback: the thousands go in by themselves, a place already visited is one
    /// tap, and its category comes with it.
    func testComasSolasComercioSugeridoYCategoriaConUnToque() {
        let app = launch(demo: true)
        app.buttons["Anotar gasto"].tap()
        let amount = require(app.textFields["monto"], "No abrió la hoja de gasto")
        amount.tap()
        amount.typeAmount("12500")
        XCTAssertEqual(amount.value as? String, "12,500", "No puso la coma de los miles")

        app.textFields["comercio"].tap()
        require(app.buttons["Oxxo"], "No sugirió un comercio ya visitado").tap()
        // A slow simulator can read the field before the pick lands.
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Oxxo"),
                                               object: app.textFields["comercio"])
        XCTAssertEqual(XCTWaiter().wait(for: [picked], timeout: 5), .completed,
                       "El comercio dice: \(app.textFields["comercio"].value as? String ?? "")")
        let despensa = require(app.buttons["categoria-Despensa"], "No hay categorías con un toque")
        XCTAssertTrue(despensa.isSelected, "No tomó la categoría de la última vez")
        snap("flujo-captura-rapida")

        // Picking a suggested merchant closes the keyboard, so the categories are in view.
        XCTAssertEqual(app.keyboards.count, 0, "El teclado siguió tapando las categorías")
        // The demo never used Comida: it waits behind «Ver todas».
        let food = app.buttons["categoria-Comida"]
        if !food.exists { require(app.buttons["ver-todas-categorias"], "No ofrece «Ver todas»").tap() }
        require(food, "No está Comida en «Ver todas»").tap()
        XCTAssertTrue(app.buttons["categoria-Comida"].isSelected, "No cambió de categoría con un toque")
        XCTAssertFalse(app.buttons["categoria-Despensa"].isSelected)
        app.buttons["hoja-guardar"].tap()
        require(row(app, containing: "12,500.00"), "El gasto no se guardó con su monto")
    }

    /// Owner's request: the whole expense in one sentence fills the sheet (plain rules; the
    /// on-device model is off in the demo modes, so this is the same on every machine).
    func testDiloEnUnaFraseLlenaLaHoja() {
        let app = launch(demo: true)
        app.buttons["Anotar gasto"].tap()
        require(app.textFields["monto"], "No abrió la hoja de gasto")
        let button = app.buttons["en-una-frase"]
        for _ in 0..<4 where !isClear(button, app) { scrollForm(app) }
        require(button, "No está «Dilo en una frase»").tap()
        let sentence = require(app.alerts.textFields.firstMatch, "No pidió la frase")
        sentence.tap()
        sentence.typeText("230 de tacos ayer, en efectivo")
        app.alerts.buttons["Llenar"].tap()
        // Back up to the amount. Give the fill a moment first: with changes in it, the sheet
        // can't be swiped away; without them, swiping down would close it.
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<4 where !app.textFields["monto"].isHittable { app.swipeDown() }
        // The sheet fills a moment after «Llenar» (the sentence is read off the main thread).
        let filled = expectation(for: NSPredicate(format: "value == %@", "230"),
                                 evaluatedWith: app.textFields["monto"])
        wait(for: [filled], timeout: 10)
        XCTAssertEqual(app.textFields["monto"].value as? String, "230", "No tomó el monto de la frase")
        XCTAssertEqual(app.textFields["comercio"].value as? String, "Tacos", "No tomó el comercio de la frase")
    }

    /// Owner's request: set up how you pay (one by default) and categories of your own, each
    /// with an icon, and find them ready when writing an expense down.
    func testTarjetasYCategoriasPropias() {
        let app = launch(demo: true)
        app.buttons["Más"].tap()
        require(app.buttons["Pagos y categorías"], "No está en «Más»").tap()
        // The cards that came with payments show up without setting them up.
        require(app.buttons["fuente-BBVA"], "No aparecen las tarjetas de los pagos")

        func create(_ add: String, _ name: String, icon: String) {
            require(app.buttons[add], "No se puede agregar").tap()
            let field = require(app.textFields["nombre-nuevo"], "No pide el nombre")
            field.tap()
            // «Listo» on the keyboard, as a person would, so the icons are not under it.
            field.typeText(name + "\n")
            // The icon grid scrolls; the bottom «Guardar» bar leaves less of it in view.
            let iconButton = app.buttons[icon]
            for _ in 0..<4 where !iconButton.isHittable { scrollForm(app) }
            iconButton.tap()
            app.buttons["guardar-nuevo"].tap()
        }
        create("agregar-fuente", "Nu", icon: "creditcard.fill")
        create("agregar-fuente", "Efectivo", icon: "banknote")
        create("agregar-categoria", "Mascotas", icon: "pawprint")
        // Each card is a tile whose menu makes it the default (2026-10-29).
        require(app.buttons["fuente-Efectivo"], "No aparece el efectivo").tap()
        require(app.buttons["Usar por defecto"], "No deja elegir la predeterminada").tap()
        require(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS[c] %@",
                                                 "Efectivo", "predeterminada")).firstMatch,
                "La estrella no pasó al efectivo")
        snap("flujo-tarjetas-y-categorias")
        app.buttons["Listo"].tap()

        app.buttons["Anotar gasto"].tap()
        let amount = require(app.textFields["monto"], "No abrió la hoja de gasto")
        amount.tap()
        amount.typeAmount("350")
        app.textFields["comercio"].tap()
        app.textFields["comercio"].typeText("Veterinaria")
        // Out of the way: on a smaller phone the keyboard covers the tiles.
        if app.keyboards.count > 0 { app.keyboards.buttons.element(boundBy: app.keyboards.buttons.count - 1).tap() }
        if app.keyboards.count > 0 { app.swipeDown() }
        // Below the categories: on any phone it takes a scroll.
        let cash = app.buttons["tarjeta-Efectivo"]
        // Scrolled at least once: on a Pro Max «Efectivo» shows without scrolling, and the
        // point is that scrolling closes the number pad.
        scrollForm(app)
        for _ in 0..<3 where !isClear(cash, app) { scrollForm(app) }
        XCTAssertTrue(require(cash, "No ofrece el efectivo").isSelected,
                      "La predeterminada no vino elegida")
        let pets = app.buttons["categoria-Mascotas"]
        // Not used yet, so it may wait behind «Ver todas».
        if !pets.exists, app.buttons["ver-todas-categorias"].exists { app.buttons["ver-todas-categorias"].tap() }
        for _ in 0..<4 where !pets.isSelected {
            if !pets.isHittable { app.swipeDown() }
            require(pets, "No ofrece la categoría propia").tap()
            usleep(400_000)
        }
        XCTAssertTrue(pets.isSelected, "No se eligió la categoría propia")
        snap("flujo-gasto-con-tarjeta-y-categoria")
        app.buttons["hoja-guardar"].tap()
        let saved = require(row(app, containing: "Veterinaria"), "No se guardó")
        XCTAssertTrue(saved.label.localizedCaseInsensitiveContains("Mascotas"), "Dice: \(saved.label)")
        XCTAssertTrue(saved.label.localizedCaseInsensitiveContains("Efectivo"), "Dice: \(saved.label)")
    }

    /// Owner's feedback: with no cards set up, the payment part was a lone tile that said
    /// nothing. Cash is always there, the button says what it adds, and scrolling closes
    /// the number pad that covered it.
    func testElMetodoDePagoSeEntiendeSinTarjetas() {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        require(app.textFields["monto"], "No abrió la hoja de gasto")
        XCTAssertTrue(app.keyboards.count > 0, "El monto no abrió el teclado")
        let cash = app.buttons["tarjeta-Efectivo"]
        // Scrolled at least once: on a Pro Max «Efectivo» shows without scrolling, and the
        // point is that scrolling closes the number pad.
        scrollForm(app)
        for _ in 0..<3 where !isClear(cash, app) { scrollForm(app) }
        XCTAssertEqual(app.keyboards.count, 0, "Al bajar no se cerró el teclado")
        require(cash, "No ofrece efectivo sin configurar nada")
        XCTAssertEqual(app.buttons["nueva-forma-de-pago"].label, "Nueva forma de pago", "El botón no dice qué agrega")
        XCTAssertTrue(app.staticTexts["Forma de pago · opcional"].exists
                      || app.staticTexts["FORMA DE PAGO · OPCIONAL"].exists, "Falta el título de la sección")
        snap("flujo-metodo-de-pago-sin-tarjetas")
        cash.tap()
        XCTAssertTrue(cash.isSelected, "No se eligió el efectivo")
    }

    func testNoSePuedeGuardarCeroNiUnMontoAbsurdo() {
        let app = launch()
        fillExpense(app, amount: "0", merchant: "Nada")
        XCTAssertFalse(app.buttons["hoja-guardar"].isEnabled, "Dejó guardar un gasto de $0")

        let amount = app.textFields["monto"]
        amount.tap()
        amount.clearAndType("1234567890123")
        // The field stops at 12 digits, the most an amount can have: a 13th is not typed.
        let digits = (amount.value as? String ?? "").filter(\.isNumber)
        XCTAssertLessThanOrEqual(digits.count, 12, "Dejó escribir un monto de \(digits.count) dígitos")
        snap("flujo-monto-invalido")
    }

    func testSinMontoOSinComercioNoSePuedeGuardar() {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        require(app.textFields["monto"], "No abrió la hoja de gasto")
        XCTAssertFalse(app.buttons["hoja-guardar"].isEnabled)
        app.textFields["monto"].tap()
        app.textFields["monto"].typeAmount("10")
        XCTAssertFalse(app.buttons["hoja-guardar"].isEnabled, "Dejó guardar sin comercio")
    }

    /// 2026-10-29: amount and category are enough; the expense is named after the category.
    func testSinComercioPeroConCategoriaSeGuarda() {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        let amount = require(app.textFields["monto"], "No abrió la hoja de gasto")
        amount.tap()
        amount.typeAmount("75")
        // «Siguiente» over the number pad goes on to the merchant.
        require(app.buttons["siguiente-teclado"], "No hay «Siguiente» sobre el teclado").tap()
        XCTAssertTrue(app.textFields["comercio"].value(forKey: "hasKeyboardFocus") as? Bool ?? false,
                      "«Siguiente» no pasó al comercio")
        scrollForm(app)
        require(app.buttons["categoria-Despensa"], "No hay categorías").tap()
        XCTAssertTrue(app.buttons["hoja-guardar"].isEnabled, "No dejó guardar con categoría y sin comercio")
        app.buttons["hoja-guardar"].tap()
        require(row(app, containing: "Despensa"), "No se guardó con el nombre de la categoría")
    }

    /// A sentence with no amount says so instead of doing nothing.
    func testUnaFraseSinMontoLoDice() {
        let app = launch()
        app.buttons["Anotar gasto"].tap()
        require(app.textFields["monto"], "No abrió la hoja de gasto")
        require(app.buttons["en-una-frase"], "No está «Dilo en una frase»").tap()
        let sentence = require(app.alerts.textFields.firstMatch, "No pidió la frase")
        sentence.tap()
        sentence.typeText("tacos ayer")
        app.alerts.buttons["Llenar"].tap()
        require(app.staticTexts["frase-sin-monto"], "No dijo que faltaba el monto")
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
        deleteButton(app).tap()

        let confirm = require(app.buttons["Borrar"], "No pidió confirmación")
        snap("flujo-confirmar-borrado")
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(row(app, containing: "Cinépolis")),
                      "El gasto sigue en la lista")
    }

    func testDeshacerRegresaElGastoBorrado() {
        let app = launch(demo: true)
        require(row(app, containing: "Cinépolis"), "No hay fila de Cinépolis").tap()
        deleteButton(app).tap()
        require(app.buttons["Borrar"], "No pidió confirmación").tap()
        let undo = require(app.buttons["deshacer-borrado"], "No ofreció deshacer", timeout: 4)
        snap("flujo-deshacer")
        undo.tap()
        require(row(app, containing: "Cinépolis"), "Deshacer no regresó el gasto")
        expectTotal(app, "$2,366.00", "El total no volvió a ser el de antes")
    }

    func testTocarUnDiaMuestraSoloSusGastos() {
        let app = launch(demo: true)
        app.buttons["Calendario"].tap()
        let day12 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Día 12'")).firstMatch
        require(day12, "No se puede tocar el día 12").tap()
        require(app.buttons["ver-todo-el-mes"], "No dice que está filtrado")
        require(row(app, containing: "Cinépolis"), "No muestra el gasto del día 12")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Liverpool'")).firstMatch.exists,
                       "Muestra gastos de otros días")
        snap("flujo-dia-filtrado")
        app.buttons["ver-todo-el-mes"].tap()
        require(row(app, containing: "Liverpool"), "No regresó a todo el mes")
    }

    /// Arrastrar despacio, como un dedo (dueño, 2026-10-30: «se regresa» y «cambia de golpe»): unos
    /// puntos y soltar regresa a la misma página; 70 pt y soltar sin impulso cambia de página, en
    /// los dos sentidos, empezando sobre la cifra o sobre el calendario.
    func testArrastrarDespacioCambiaDePaginaYUnPocoRegresa() {
        let app = launch(demo: true, budget: true)
        let calendar = require(app.buttons["Calendario"], "No hay puntito del calendario")
        let budget = require(app.buttons["Presupuesto"], "No hay puntito del presupuesto")
        let figure = require(app.staticTexts["hoy-puedes-gastar"], "No está la cifra")
        func drag(from start: XCUICoordinate, by dx: CGFloat) {
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)),
                        withVelocity: 60, thenHoldForDuration: 0.3)
            sleep(1)
        }
        let onFigure = figure.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 120, dy: 0))
        drag(from: onFigure, by: -20)
        XCTAssertTrue(budget.isSelected, "Unos puntos cambiaron de página")
        drag(from: onFigure, by: -70)
        XCTAssertTrue(calendar.isSelected, "Arrastrar 70 pt despacio no llevó al calendario")
        let day = require(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Día 12")).firstMatch,
                          "No se ve el calendario")
        drag(from: day.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), by: 70)
        XCTAssertTrue(budget.isSelected, "Arrastrar 70 pt despacio sobre el calendario no regresó")
    }

    /// Con «En qué se va» a la vista (barra o mosaico), cada página tiene su propia altura (decisión
    /// del 2026-10-30: el hueco bajo el mosaico): al pasar al calendario, este se ve completo, con su
    /// último día arriba de los puntitos, y el título «Cada día del mes» no se mueve.
    func testElCalendarioSeVeCompletoYSuTituloNoSeMueve() {
        for style in ["bar", "mosaic"] {
            let app = launch(demo: true, budget: true, extra: ["-whereItGoesStyle", style])
            let title = require(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Cada día del mes")).firstMatch, "No está el título (\(style))")
            let titleY = title.frame.minY
            let dot = require(app.buttons["Calendario"], "No hay puntito del calendario (\(style))")
            dot.tap()
            require(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Día 12'")).firstMatch,
                    "No abrió el calendario (\(style))")
            let days = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Día '"))
            let last = days.element(boundBy: days.count - 1)
            XCTAssertLessThanOrEqual(last.frame.maxY, dot.frame.minY + 1,
                                     "El calendario quedó cortado (\(style))")
            XCTAssertEqual(title.frame.minY, titleY, accuracy: 1, "El título se movió (\(style))")
            app.terminate()
        }
    }

    /// Mantener presionado un bloque del mosaico abre su detalle completo (el bloque puede ser
    /// demasiado chico para su nombre y su monto) y ofrece ver sus gastos.
    func testMantenerPresionadoUnBloqueOfreceVerSusGastos() {
        let app = launch(demo: true, budget: true, extra: ["-whereItGoesStyle", "mosaic"])
        require(app.buttons["parte-Ropa"], "No hay bloque de Ropa").press(forDuration: 1.2)
        snap("flujo-mosaico-detalle")
        require(app.buttons["Ver sus gastos"], "No ofrece ver los gastos de la categoría").tap()
        require(app.buttons["ver-todo-el-mes"], "No filtró por la categoría")
        require(row(app, containing: "Liverpool"), "No muestra el gasto de Ropa")
    }

    func testTocarUnaCategoriaMuestraSoloSusGastos() {
        let app = launch(demo: true, budget: true, extra: ["-whereItGoesStyle", "mosaic"])
        require(app.buttons["parte-Ropa"], "No hay bloque de Ropa").tap()
        require(app.buttons["ver-todo-el-mes"], "No dice que está filtrado")
        require(row(app, containing: "Liverpool"), "No muestra el gasto de Ropa")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Cinépolis'")).firstMatch.exists,
                       "Muestra gastos de otras categorías")
        snap("flujo-categoria-filtrada")
        app.buttons["ver-todo-el-mes"].tap()
        require(row(app, containing: "Cinépolis"), "No regresó a todo el mes")
    }

    func testDeslizarUnGastoPideBorrarlo() {
        let app = launch(demo: true)
        let cinepolis = require(row(app, containing: "Cinépolis"), "No hay fila de Cinépolis")
        uncoverListRow(app, cinepolis)
        cinepolis.swipeLeft(velocity: .fast)
        let confirm = require(app.buttons["Borrar"], "Deslizar no pidió confirmación")
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(row(app, containing: "Cinépolis")), "El gasto sigue en la lista")
    }

    func testDeslizarPocoMuestraBorrarYTocarLoCierra() {
        let app = launch(demo: true)
        let cinepolis = require(row(app, containing: "Cinépolis"), "No hay fila de Cinépolis")
        uncoverListRow(app, cinepolis)
        let start = cinepolis.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: cinepolis.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
        require(app.buttons["deslizar-borrar"], "Deslizar no mostró «Borrar»")
        snap("flujo-deslizar-borrar")
        cinepolis.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(waitForDisappearance(app.buttons["deslizar-borrar"]), "Tocar el gasto abierto no lo cerró")
        XCTAssertFalse(app.textFields["monto"].exists, "Tocar el gasto abierto lo abrió en vez de cerrarlo")
    }

    func testOcultarUnaCategoriaLaQuitaAlAnotar() {
        let app = launch()
        app.buttons["Más"].tap()
        require(app.buttons["Pagos y categorías"], "No está en «Más»").tap()
        // A tile per category (2026-10-29); its menu hides it.
        let cafe = app.buttons["mostrar-Café"]
        for _ in 0..<4 where !cafe.isHittable { app.swipeUp() }
        require(cafe, "No se pueden ocultar las categorías de siempre").tap()
        require(app.buttons["Ocultar al anotar"], "El menú no ofrece ocultarla").tap()
        snap("flujo-ocultar-categoria")
        app.buttons["Listo"].tap()
        app.buttons["Anotar gasto"].tap()
        require(app.textFields["monto"], "No abrió la hoja de gasto")
        require(app.buttons["categoria-Despensa"], "No hay categorías")
        XCTAssertFalse(app.buttons["categoria-Café"].exists, "Café sigue saliendo aunque se ocultó")
    }

    func testCancelarLaConfirmacionNoBorra() {
        let app = launch(demo: true)
        require(row(app, containing: "Cinépolis"), "No hay fila de Cinépolis").tap()
        deleteButton(app).tap()
        require(app.buttons["Borrar"], "No pidió confirmación")
        app.buttons["Conservar"].tap()
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
        field.typeAmount("5000")
        app.buttons["hoja-guardar"].tap()

        let ticket = require(app.otherElements["presupuesto-ticket"],
                             "No apareció el ticket del presupuesto")
        XCTAssertTrue(ticket.label.contains("$5,000.00"), "El ticket dice: \(ticket.label)")
        snap("flujo-presupuesto-fijado")

        app.buttons["Más"].tap()
        app.buttons["Presupuesto del mes"].tap()
        // «Quitar presupuesto» goes under the «Hoy puedes gastar» choice: scroll the sheet to it.
        let remove = app.buttons["quitar-presupuesto"]
        require(app.textFields["presupuesto-monto"], "No abrió la hoja del presupuesto")
        // With the keyboard up it sits under «Guardar» and still reads as hittable: scroll once,
        // like a person would, which puts the keyboard away (`scrollDismissesKeyboard`).
        app.swipeUp()
        for _ in 0..<3 where !remove.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(app.keyboards.count, 0, "Al deslizar no se escondió el teclado")
        require(remove, "No ofrece quitar el presupuesto").tap()
        require(app.buttons["fijar-presupuesto"], "No quitó el presupuesto")
    }

    /// What is spent today comes off today's figure peso for peso; it used to be spread over
    /// the days left and barely moved (audit 2026-10-22, #3).
    func testGastarHoyRestaDeLoQuePuedesGastarHoy() {
        let app = launch(budget: true)
        let figure = require(app.staticTexts["hoy-puedes-gastar"], "No dice cuánto puedes gastar hoy")
        let before = wholeAmount(figure.label)
        fillExpense(app, amount: "100", merchant: "Antojo")
        app.buttons["hoja-guardar"].tap()
        let expected = before - 100
        let updated = NSPredicate { _, _ in self.wholeAmount(figure.label) == expected }
        let waited = XCTWaiter().wait(for: [expectation(for: updated, evaluatedWith: nil)], timeout: 10)
        XCTAssertEqual(waited, .completed, "Pasó de \(before) a «\(figure.label)», no a \(expected)")
    }

    /// "$8,000" → 8000.
    private func wholeAmount(_ label: String) -> Int {
        Int(label.filter(\.isNumber)) ?? -1
    }

    func testPasarseDelPresupuestoLoDice() {
        let app = launch()
        app.buttons["Más"].tap()
        app.buttons["Presupuesto del mes"].tap()
        let field = require(app.textFields["presupuesto-monto"], "No abrió la hoja del presupuesto")
        field.tap()
        field.typeAmount("100")
        app.buttons["hoja-guardar"].tap()

        fillExpense(app, amount: "250", merchant: "Antojo")
        app.buttons["hoja-guardar"].tap()
        // The bar is always in view now, over the carousel: no page to go back to.
        let ticket = require(app.otherElements["presupuesto-ticket"], "No apareció el ticket")
        XCTAssertTrue(ticket.label.contains("Te pasaste"), "El ticket dice: \(ticket.label)")
        snap("flujo-pasado-de-presupuesto")
        expectFitsOnScreen(app, ticket)
    }

    /// Opening the app already over budget once locked the page wider than the screen:
    /// "Gastado" and the budget line were cut off and the brass spilled onto the calendar.
    func testAbrirYaPasadoDelPresupuestoCabeEnPantalla() {
        let app = launch(demo: true, extra: ["-monthlyBudget", "1000"])
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
        // Past the budget the hero is «te-pasaste» instead of the total; same margins.
        let hero = app.staticTexts["total-mes"].exists ? app.staticTexts["total-mes"] : app.staticTexts["te-pasaste"]
        let total = hero.frame
        let screen = app.windows.firstMatch.frame
        // «te-pasaste» is pulled 3 pt left on purpose (its «$» lines up with the caption).
        let margin = total.minX - screen.minX + (app.staticTexts["total-mes"].exists ? 0 : 3)
        XCTAssertEqual(element.frame.minX, screen.minX + margin, accuracy: 1,
                       "No respeta el margen izquierdo: \(element.frame), total en \(total)")
        XCTAssertEqual(element.frame.maxX, screen.maxX - margin, accuracy: 1,
                       "No respeta el margen derecho: \(element.frame) en \(screen)")
    }

    // MARK: Primera vez

    func testLaPrimeraVezDejaTodoListo() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX",
                               "-centavo-empty", "-centavo-onboarding"]
        app.launch()
        let next = require(app.buttons["bienvenida-siguiente"], "No apareció la bienvenida", timeout: 20)
        snap("bienvenida-1")
        next.tap()
        require(app.buttons["Pesos"], "No ofrece pesos").tap()
        let budget = require(app.textFields["bienvenida-presupuesto"], "No pide presupuesto")
        budget.tap(); budget.typeAmount("9000")
        require(app.staticTexts["bienvenida-por-dia"], "No dice cuánto puedes gastar al día")
        snap("bienvenida-2")
        // «Continuar» rides above the number pad: nothing covers it.
        XCTAssertTrue(next.isHittable, "El teclado tapa «Continuar»")
        next.tap()
        let name = require(app.textFields["bienvenida-fijo-nombre"], "No pide gastos fijos")
        name.tap(); name.typeText("Renta")
        let amount = app.textFields["bienvenida-fijo-monto"]
        amount.tap(); amount.typeAmount("6500")
        app.buttons["bienvenida-fijo-agregar"].tap()
        snap("bienvenida-3")
        next.tap()
        snap("bienvenida-4")
        require(app.buttons["bienvenida-despues"], "No ofrece conectar después").tap()

        require(app.staticTexts["hoy-puedes-gastar"], "No quedó el presupuesto", timeout: 10)
        require(row(app, containing: "Renta"), "No se anotó la renta")
        XCTAssertTrue(row(app, containing: "Fijo").exists, "La renta no quedó como fija")
        snap("bienvenida-listo")
    }

    func testSinBienvenidaSiYaHayGastos() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX",
                               "-centavo-demo", "-centavo-onboarding"]
        app.launch()
        require(app.buttons["Anotar gasto"], "La pantalla principal no abrió", timeout: 20)
        XCTAssertFalse(app.buttons["bienvenida-siguiente"].exists, "Mostró la bienvenida con gastos")
    }

    // MARK: Intentar romperla

    /// The worst a person can type, all in one month: nothing may leave the screen.
    func testDatosExtremosNoRompenLaPantalla() {
        let app = launch(budget: true)
        let longName = String(repeating: "Farmacia del Ahorro Sucursal ", count: 5)
        fillExpense(app, amount: "999999999999.99", merchant: longName)
        app.buttons["hoja-guardar"].tap()
        fillExpense(app, amount: "20", merchant: "Steam")
        pickCurrency(app, "USD")
        app.buttons["hoja-guardar"].tap()
        fillExpense(app, amount: "30", merchant: "Devolución", refund: true)
        app.buttons["hoja-guardar"].tap()
        snap("extremos-principal")

        let screen = app.windows.firstMatch.frame
        // Past the budget the hero says by how much («te-pasaste») instead of the total.
        let hero = app.staticTexts["te-pasaste"].exists ? app.staticTexts["te-pasaste"] : app.staticTexts["total-mes"]
        for element in [hero, row(app, containing: "Farmacia")] {
            XCTAssertTrue(element.exists)
            XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX - 1, "Se sale: \(element.frame)")
            XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX + 1, "Se sale: \(element.frame)")
        }
        app.buttons["Calendario"].tap()
        snap("extremos-calendario")
        app.buttons["Mes anterior"].tap()
        snap("extremos-mes-anterior")
    }

    // MARK: Gastos fijos

    func testUnGastoFijoSeMarcaComoFijo() {
        let app = launch()
        fillExpense(app, amount: "8500", merchant: "Renta")
        openDetails(app)
        let toggle = app.switches["se-repite"]
        // «Se repite» is under «Más detalles», so it can start under «Guardar»: isHittable is
        // true there, but the knob tap lands on Guardar and the sheet closes. Scroll until the
        // save bar is clear of it.
        for _ in 0..<8 where !isClear(toggle, app) { scrollForm(app) }
        require(toggle, "No ofrece repetir cada mes")
        turnOn(toggle, "Se repite cada mes")
        app.buttons["hoja-guardar"].tap()
        require(row(app, containing: "Fijo"), "La lista no marca el gasto como fijo")
        snap("flujo-gasto-fijo")
    }

    /// Owner's request: «todos los lunes me cobran 500»: set up once in «Más › Gastos fijos».
    func testUnGastoFijoSemanalDesdeGastosFijos() {
        let app = launch()
        app.buttons["Más"].tap()
        require(app.buttons["Gastos fijos"], "No está «Gastos fijos» en «Más»").tap()
        require(app.buttons["agregar-fijo"], "No se puede agregar un gasto fijo").tap()
        let amount = require(app.textFields["fijo-monto"], "No abrió la hoja del gasto fijo")
        amount.tap()
        amount.typeAmount("500")
        app.textFields["fijo-nombre"].tap()
        app.textFields["fijo-nombre"].typeText("Limpieza")
        app.segmentedControls["frecuencia"].buttons["Semana"].tap()
        app.buttons["hoja-guardar"].tap()
        require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Limpieza")).firstMatch,
                "No aparece en la lista de fijos")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "cada ")).firstMatch.exists,
                      "No dice cada cuándo se repite")
        snap("flujo-gastos-fijos")
    }

    // MARK: El código del mes

    /// A finger on the month's barcode reads a day, and letting go on it shows only that day,
    /// the same as tapping it in the calendar (owner, 2026-10-29).
    func testElCodigoDelMesMuestraUnDia() {
        let app = launch(demo: true, budget: true)
        // The code heads the carousel's first page, in every view (2026-10-30).
        let code = require(app.descendants(matching: .any)["codigo-del-mes"], "No está el código del mes")
        XCTAssertTrue(app.staticTexts["folio"].exists || app.descendants(matching: .any)["folio"].exists,
                      "No está el folio")
        // Day 12, the demo's Cinépolis: the middle of the 12th bar of the month's 31.
        let start = code.coordinate(withNormalizedOffset: CGVector(dx: (2 - 0.5) / 31, dy: 0.3))
        let point = code.coordinate(withNormalizedOffset: CGVector(dx: (12 - 0.5) / 31, dy: 0.3))
        // Along the code with the finger down, reading days on the way, and let go on the 12th.
        start.press(forDuration: 0.6, thenDragTo: point, withVelocity: 60, thenHoldForDuration: 1.2)
        snap("flujo-codigo-del-mes")
        require(app.buttons["ver-todo-el-mes"], "Soltar en un día no lo filtró")
        require(row(app, containing: "Cinépolis"), "No muestra el gasto de ese día")
        // A quick swipe on the boleto goes to the calendar (owner, 2026-10-30).
        code.swipeLeft()
        require(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Día ")).firstMatch,
                "Deslizar el boleto no llevó al calendario")
        app.buttons["Presupuesto"].tap()
        sleep(1)
        // A tap anywhere else lets the day go (owner, 2026-10-30).
        app.staticTexts["hoy-puedes-gastar"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.buttons["ver-todo-el-mes"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 3), .completed, "Tocar fuera no quitó el filtro")
        // One tap on a day picks it.
        point.tap()
        require(app.buttons["ver-todo-el-mes"], "Un toque en un día no lo eligió")
        app.staticTexts["hoy-puedes-gastar"].tap()
        // A sideways swipe on the figure also goes to the calendar (owner, 2026-10-30).
        app.staticTexts["hoy-puedes-gastar"].swipeLeft()
        require(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Día ")).firstMatch,
                "Deslizar sobre la cifra no llevó al calendario")
    }

    // MARK: En qué se va

    func testElPresupuestoDiceEnQueSeVa() {
        let app = launch(demo: true, budget: true)
        let shares = require(app.descendants(matching: .any)["en-que-se-va"], "No dice en qué se va")
        XCTAssertTrue(app.staticTexts["Ropa: 42 % de lo gastado"].exists
                      || shares.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Ropa'")).count > 0,
                      "No aparece la categoría más grande")
    }

    /// With the biggest accessibility text, «En qué se va» used to hide the category names and
    /// cut the amounts («$2,3…»). Each line has to carry its name and its whole amount, and fit.
    func testEnQueSeVaConLetraDeAccesibilidadMuestraNombresYMontosCompletos() {
        let app = launch(demo: true, budget: true, extra: [
            "-whereItGoesStyle", "bar",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let section = app.descendants(matching: .any)["en-que-se-va"]
        for _ in 0..<6 where !section.isHittable { app.swipeUp() }
        require(section, "No aparece «En qué se va»")
        let lines = section.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'parte-'"))
        XCTAssertGreaterThanOrEqual(lines.count, 2, "«En qué se va» no tiene renglones de categoría")
        let window = app.windows.firstMatch.frame
        let whole = try! NSRegularExpression(pattern: #"^(.+): \$[\d,]+\.\d{2}, \d+\s?% de lo gastado$"#)
        for index in 0..<lines.count {
            let line = lines.element(boundBy: index)
            let name = String(line.identifier.dropFirst("parte-".count))
            let label = line.label
            let match = whole.firstMatch(in: label, range: NSRange(label.startIndex..., in: label))
            XCTAssertNotNil(match, "Renglón sin monto completo: «\(label)»")
            XCTAssertTrue(label.hasPrefix(name), "Renglón sin el nombre «\(name)»: «\(label)»")
            XCTAssertFalse(label.contains("…"), "Renglón cortado: «\(label)»")
            if line.isHittable {
                XCTAssertLessThanOrEqual(line.frame.maxX, window.maxX + 0.5, "«\(name)» se sale de la pantalla")
                XCTAssertGreaterThanOrEqual(line.frame.minX, window.minX - 0.5, "«\(name)» se sale de la pantalla")
            }
        }
        snap("flujo-en-que-se-va-letra-de-accesibilidad")
    }

    /// «Mosaico» with the largest text: blocks sized by their share had no room for a name or an
    /// amount. In accessibility sizes each category is a full-width block as tall as its text;
    /// each has to fit across the screen, be tappable (it filters the list) and say everything.
    func testMosaicoConLetraDeAccesibilidadMuestraCadaCategoriaCompleta() {
        let app = launch(demo: true, budget: true, extra: [
            "-whereItGoesStyle", "mosaic",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let section = app.descendants(matching: .any)["en-que-se-va"]
        for _ in 0..<6 where !section.isHittable { app.swipeUp() }
        require(section, "No aparece «En qué se va»")
        let tiles = section.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'parte-'"))
        XCTAssertGreaterThanOrEqual(tiles.count, 2, "El mosaico no tiene bloques de categoría")
        let window = app.windows.firstMatch.frame
        for index in 0..<tiles.count {
            let tile = tiles.element(boundBy: index)
            let name = String(tile.identifier.dropFirst("parte-".count))
            XCTAssertTrue(tile.label.hasPrefix(name), "Bloque sin el nombre «\(name)»: «\(tile.label)»")
            XCTAssertTrue(tile.label.contains("$"), "Bloque sin monto: «\(tile.label)»")
            XCTAssertLessThanOrEqual(tile.frame.maxX, window.maxX + 0.5, "«\(name)» se sale de la pantalla")
            XCTAssertGreaterThanOrEqual(tile.frame.minX, window.minX - 0.5, "«\(name)» se sale de la pantalla")
            XCTAssertGreaterThanOrEqual(tile.frame.height, 44, "«\(name)» es muy chico para tocarlo")
        }
        snap("flujo-mosaico-letra-de-accesibilidad")
    }

    /// With the largest text the day's divider in the list («HOY · 23 OCT  ——  $1,234») was cut
    /// to «HO…». In accessibility sizes the day gets its own lines and the total goes under it:
    /// every divider has to fit across the screen and carry the whole day and month.
    func testElDivisorDelDiaConLetraDeAccesibilidadCabeCompleto() {
        let app = launch(demo: true, budget: true, extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let divider = app.descendants(matching: .any)["divisor-dia"].firstMatch
        for _ in 0..<12 where !divider.isHittable { app.swipeUp() }
        require(divider, "No aparece el divisor del día con letra grande")
        let window = app.windows.firstMatch.frame
        let dividers = app.descendants(matching: .any).matching(identifier: "divisor-dia")
        let day = try! NSRegularExpression(pattern: #"\d{1,2} (de )?[a-záéíóú]{3}"#, options: .caseInsensitive)
        for index in 0..<dividers.count {
            let element = dividers.element(boundBy: index)
            guard element.isHittable else { continue }
            let label = element.label
            XCTAssertNotNil(day.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
                            "Divisor sin día y mes: «\(label)»")
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX + 0.5, "«\(label)» se sale de la pantalla")
            XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX - 0.5, "«\(label)» se sale de la pantalla")
        }
        snap("flujo-divisor-del-dia-letra-de-accesibilidad")
    }

    // MARK: Salud de la captura

    func testDiceCuandoLlegoElUltimoPagoDeWallet() {
        let app = launch(demo: true)
        let health = require(app.buttons["salud-captura"], "No dice cómo va la captura")
        XCTAssertTrue(health.label.localizedCaseInsensitiveContains("último pago"), "Dice: \(health.label)")
    }

    /// The budget sheet explains both rules with a drawing and switches it with the choice
    /// (2026-10-29). «Para cerrar el mes» is gone: the owner found it too much.
    func testElPlanDelMesYLaHojaDelPresupuesto() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX",
                               "-centavo-demo", "-monthlyBudget", "2000"]
        app.launch()
        require(app.buttons["Más"], "La pantalla principal no abrió", timeout: 20)
        XCTAssertFalse(app.buttons["para-cerrar-el-mes"].exists, "Sigue «Para cerrar el mes»")
        app.buttons["Más"].tap()
        app.buttons["Presupuesto del mes"].tap()
        require(app.textFields["presupuesto-monto"], "No abrió la hoja del presupuesto")
        sleep(7)
        snap("presupuesto-acumula")
        require(app.buttons["Se reparte"], "No ofrece repartir").tap()
        let suits = app.staticTexts["modo-te-conviene"]
        XCTAssertTrue(suits.label.contains("parejo"), "No explica repartir: \(suits.label)")
        sleep(8)
        snap("presupuesto-reparte")
    }

    /// Tapping the bar unfolds the sum in place and tapping again folds it (2026-10-29).
    func testLaCuentaSeAbreYSeCierraAlTocarLaBarra() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX",
                               "-centavo-demo", "-monthlyBudget", "2000", "-planCerradoMes", "2026-10"]
        app.launch()
        // The line «Llevas … · Ver cuenta» opens the sum: the bar is now the boleto (2026-10-30).
        let bar = require(app.buttons["ver-cuenta"], "No ofrece ver la cuenta", timeout: 20)
        sleep(2)
        bar.tap()
        require(app.descendants(matching: .any)["la-cuenta"], "La barra no abrió la cuenta")
        sleep(2)
        snap("cuenta-abierta")
        bar.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.descendants(matching: .any)["la-cuenta"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 3), .completed, "La cuenta no se cerró")
        sleep(1)
    }

    func testSinPagosDeWalletInvitaAConfigurarYAbreLaGuia() {
        let app = launch(budget: true, extra: ["-centavo-demo-large"])
        let health = require(app.buttons["salud-captura"], "No dice cómo va la captura")
        XCTAssertTrue(health.label.localizedCaseInsensitiveContains("sin conectar"), "Dice: \(health.label)")
        // Past the budget the plan sits above it: bring the line out from under the bottom bar.
        for _ in 0..<3 where !health.isHittable || health.frame.maxY > app.windows.firstMatch.frame.maxY - 120 {
            app.swipeUp()
        }
        health.tap()
        stepByStep(app)
        require(app.buttons["guia-siguiente"], "No abrió la guía")
    }

    /// iOS 27 opens on adding the ready-made automation; the step-by-step guide is behind
    /// «Prefiero hacerlo paso a paso».
    private func stepByStep(_ app: XCUIApplication) {
        let way = app.buttons["atajo-paso-a-paso"]
        if way.waitForExistence(timeout: 5) { way.tap() }
    }

    func testElAtajoArmadoSeAgregaConUnBoton() throws {
        let app = launch(demo: true)
        app.buttons["Más"].tap()
        app.buttons["Configurar atajo"].firstMatch.tap()
        let add = app.buttons["atajo-agregar"]
        try XCTSkipUnless(add.waitForExistence(timeout: 5), "Solo en iOS 27: antes no hay atajo armado")
        require(app.descendants(matching: .any)["guia-comprobacion"], "No dice si ya llegó un pago")
        snap("flujo-atajo-armado")
        add.tap()
        // The share sheet offers Atajos, which imports the file.
        let shortcuts = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Atajos", "Shortcuts"])).firstMatch
        require(shortcuts, "La hoja no ofrece Atajos")
    }

    // MARK: Guía del atajo

    /// Opens the guide from the menu, or from the empty screen on a first launch.
    private func walkGuideToTheEnd(_ app: XCUIApplication, fromMenu: Bool = true) -> XCUIElement {
        if fromMenu {
            app.buttons["Más"].tap()
            app.buttons["Configurar atajo"].firstMatch.tap()
        } else {
            require(app.buttons["vacio-wallet"], "La pantalla vacía no ofrece conectar Wallet").tap()
        }
        stepByStep(app)
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
        XCTAssertFalse(hasRow(app, containing: "Cinépolis"),
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
        XCTAssertFalse(hasRow(app, containing: "Retroactivo"),
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

    /// Scrolls a sheet up by dragging its form, above the keyboard. `swipeUp()` starts at the
    /// middle of the screen, which on smaller iPhones is already the keyboard: nothing moved.
    /// Whether `element` can really be tapped in a sheet: on screen and above the «Guardar»
    /// bar. On an iPhone Pro Max the last rows rest under the bar, where XCUITest calls them
    /// hittable but a tap lands on the bar.
    private func isClear(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let bar = app.staticTexts["resumen-guardar"]
        guard bar.exists else { return true }
        return element.frame.midY < bar.frame.minY - 12
    }

    private func scrollForm(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
    }

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
    /// Types an amount at a person's pace. The field puts the thousands' commas in as you
    /// type; a test typing every 10 ms can outrun that, a person (150 ms or more) cannot.
    func typeAmount(_ text: String) {
        for character in text {
            typeText(String(character))
            usleep(150_000)
        }
    }

    /// Replaces whatever is in the field.
    func clearAndType(_ text: String) {
        guard let current = value as? String, !current.isEmpty else {
            typeText(text)
            return
        }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeAmount(text)
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
    func testZonasTactilesDelMosaico() throws {
        var issues: [String] = []
        let app = launch(extra: ["-whereItGoesStyle", "mosaic"])
        try app.performAccessibilityAudit(for: .hitRegion) { issue in
            issues.append("\(issue.compactDescription) — \(issue.element?.debugDescription.prefix(220) ?? "sin elemento")")
            return true
        }
        XCTAssertTrue(issues.isEmpty, "Zonas táctiles menores de 44 pt:\n" + issues.joined(separator: "\n"))
    }

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
