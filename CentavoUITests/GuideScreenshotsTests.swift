import XCTest

/// Walks the real Atajos app through the automation the guide teaches, as a new person
/// would, and keeps a screenshot of every step: the guide's pictures come from here.
/// Only runs on demand, on a freshly erased iOS simulator with Al día installed:
///
///     TEST_RUNNER_CENTAVO_GUIA=1 xcodebuild test … -only-testing:CentavoUITests/GuideScreenshotsTests
@MainActor
final class GuideScreenshotsTests: XCTestCase {
    private var shortcuts: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CENTAVO_GUIA"] != nil,
                          "Solo se corre a mano para rehacer las imágenes de la guía")
        continueAfterFailure = false
        shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: shortcuts.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: shortcuts.debugDescription)
        tree.name = name + "-arbol"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 8) {
        if !element.waitForExistence(timeout: timeout) {
            snap("falta-" + what)
            XCTFail("No encontré «\(what)»")
        }
        element.tap()
    }

    func testRecorrerLaAutomatizacion() {
        // Like someone who just installed it: Al día opened once, so Atajos knows its actions.
        let alDia = XCUIApplication()
        alDia.launchArguments = ["-AppleLanguages", "(es-MX)", "-AppleLocale", "es_MX", "-centavo-empty"]
        alDia.launch()
        sleep(3)
        alDia.terminate()

        shortcuts.launch()
        let continueButton = shortcuts.buttons["Continuar"]
        if continueButton.waitForExistence(timeout: 4) {
            snap("00-novedades")
            continueButton.tap()
        }
        sleep(1)
        snap("01-todos-los-atajos")

        // The «+» at the bottom of «Todos los atajos».
        let add = shortcuts.buttons.matching(NSPredicate(format: "label IN %@", ["Agregar", "Nuevo atajo", "Add"])).firstMatch
        tap(add, "+")
        sleep(2)
        // With Apple Intelligence it may open «Describir un atajo» first; «Editar» leaves it.
        let edit = shortcuts.buttons.matching(NSPredicate(format: "label IN %@", ["Editar", "Editor"])).firstMatch
        if edit.waitForExistence(timeout: 3) {
            snap("01b-describir-un-atajo")
            edit.tap()
            sleep(1)
        }
        snap("02-nuevo-atajo")

        tap(shortcuts.buttons["Automatización"], "Automatización")
        sleep(1)
        snap("03-automatizacion")

        let notification = shortcuts.staticTexts["Notificación"]
        for _ in 0..<6 where !notification.isHittable { shortcuts.swipeUp() }
        snap("04-notificacion-en-la-lista")
        tap(notification, "Notificación")
        sleep(1)
        snap("05-bloque-notificacion")

        tap(shortcuts.buttons["App"], "App")
        sleep(1)
        snap("06-elegir-app")
        let wallet = shortcuts.staticTexts["Wallet"]
        for _ in 0..<4 where !wallet.isHittable { shortcuts.swipeUp() }
        snap("06b-wallet-en-la-lista")
        tap(wallet, "Wallet")
        sleep(1)
        snap("07-con-wallet")

        let search = shortcuts.searchFields.firstMatch
        tap(search, "Buscar")
        search.typeText("Registrar aviso")
        sleep(2)
        // The keyboard's one-time tip covers the results.
        let tip = shortcuts.buttons["Continuar"]
        if tip.exists { tip.tap() }
        snap("08-buscar-accion")
        let action = shortcuts.cells["Registrar aviso de Wallet"]
        tap(action, "Registrar aviso de Wallet")
        sleep(1)
        snap("09-accion-agregada")

        // The action's «Notificación» field, then the variable above the keyboard.
        let field = shortcuts.buttons["Notificación"].firstMatch
        tap(field, "campo Notificación")
        sleep(1)
        snap("10-elegir-variable")
        let variable = shortcuts.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Notificación")).element(boundBy: 0)
        tap(variable, "variable Notificación")
        sleep(1)
        snap("11-conectada")
        shortcuts.buttons["Cerrar"].firstMatch.tap()
        sleep(1)
        // What the trigger's options say about asking before it runs.
        let expand = shortcuts.buttons.matching(identifier: "Expandir").firstMatch
        if expand.exists { expand.tap() } else { shortcuts.buttons["Expandir"].firstMatch.tap() }
        sleep(1)
        snap("11b-opciones-del-disparador")

        tap(shortcuts.buttons["BackButton"], "regresar")
        sleep(2)
        snap("12-guardada")
    }
}
