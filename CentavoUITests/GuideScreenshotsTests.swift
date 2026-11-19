import XCTest

/// Walks the real Atajos app through the automation the guide teaches, as a new person
/// would, and keeps a screenshot of every step: the guide's pictures come from here.
/// Only runs on demand, on a freshly erased iOS simulator with Al día installed:
///
///     TEST_RUNNER_CENTAVO_GUIA=1 xcodebuild test … -only-testing:CentavoUITests/GuideScreenshotsTests
///
/// In English (Shortcuts and Al día both in English; every attachment name ends in «-en»):
///
///     TEST_RUNNER_CENTAVO_GUIA=1 TEST_RUNNER_CENTAVO_GUIA_IDIOMA=en xcodebuild test …
///
/// The CI does both by hand («Guía de Atajos», input `guia`). Every screenshot comes with
/// «-arbol» (the accessibility tree: how a label that changed is found) and «-marca» (where the
/// ring goes, in pixels), which `Tools/guia-aros.py` turns into the guide's imagesets.
/// A missing element leaves «falta-…» with its tree before failing.
@MainActor
final class GuideScreenshotsTests: XCTestCase {
    private var shortcuts: XCUIApplication!
    private var words = Words.es
    /// «» in Spanish (the names the Spanish set was made from), «-en» in English.
    private var tag = ""

    /// Every label the test looks for, per language. One string is looked up as before
    /// (`query["…"]`, identifier or label); several are alternatives (`label IN …`), for the
    /// labels not yet seen on a real run: the «falta-…-arbol» of a failed run says which is right.
    struct Words {
        var languages: [String]
        var locale: String
        var continueButton: [String]
        var add: [String]
        var edit: [String]
        var automation: [String]
        var notificationTrigger: [String]
        var app: [String]
        var wallet: [String]
        var searchText: String
        var action: [String]
        var noticeField: [String]
        /// What the variable's label contains (the bell above the keyboard).
        var noticeVariable: String
        var selectVariable: [String]
        var closeKeyboard: [String]
        var expand: [String]
        var back: [String]
        var merchantField: [String]
        var subtitle: [String]
        var showWhenRun: [String]

        static let es = Words(
            languages: ["(es-MX)"], locale: "es_MX",
            continueButton: ["Continuar"],
            add: ["Agregar", "Nuevo atajo", "Add"],
            edit: ["Editar", "Editor"],
            automation: ["Automatización"],
            notificationTrigger: ["Notificación"],
            app: ["App"],
            wallet: ["Wallet"],
            searchText: "Registrar aviso",
            action: ["Registrar aviso de Wallet"],
            noticeField: ["Notificación"],
            noticeVariable: "Notificación",
            selectVariable: ["Seleccionar variable", "Seleccionar la variable"],
            closeKeyboard: ["Cerrar"],
            expand: ["Expandir"],
            back: ["BackButton"],
            merchantField: ["Comercio"],
            subtitle: ["Subtítulo"],
            showWhenRun: ["Mostrar al ejecutar"]
        )

        static let en = Words(
            languages: ["(en)"], locale: "en_US",
            continueButton: ["Continue", "Get Started"],
            add: ["Add", "New Shortcut", "Create Shortcut", "Add Shortcut", "Create New Shortcut"],
            edit: ["Edit", "Editor", "Open Editor"],
            automation: ["Automation", "Automations"],
            notificationTrigger: ["Notification", "Notifications"],
            app: ["App", "Choose App", "Choose"],
            wallet: ["Wallet"],
            searchText: "Log Wallet",
            action: ["Log Wallet notification", "Log Wallet Notification"],
            noticeField: ["Notification"],
            noticeVariable: "Notification",
            selectVariable: ["Select Variable", "Select variable"],
            closeKeyboard: ["Close", "Done", "Dismiss"],
            expand: ["Expand", "Show More", "More"],
            back: ["BackButton", "Back"],
            merchantField: ["Merchant"],
            subtitle: ["Subtitle"],
            showWhenRun: ["Show When Run", "Show when run"]
        )
    }

    override func setUp() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["CENTAVO_GUIA"] != nil,
                          "Solo se corre a mano para rehacer las imágenes de la guía")
        continueAfterFailure = false
        if environment["CENTAVO_GUIA_IDIOMA"]?.lowercased().hasPrefix("en") == true {
            words = .en
            tag = "-en"
        }
        // Dark, as the Spanish set was taken (the guide sits on the app's dark paper).
        XCUIDevice.shared.appearance = .dark
        shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        // In the set's language whatever the simulator's: the labels below are Atajos' own.
        shortcuts.launchArguments = ["-AppleLanguages", words.languages[0], "-AppleLocale", words.locale]
    }

    // MARK: - Helpers

    /// `query` filtered to one of `labels`: one label as before (`query["…"]`), several as
    /// alternatives by label or identifier.
    private func find(_ query: XCUIElementQuery, _ labels: [String]) -> XCUIElement {
        if labels.count == 1 { return query[labels[0]] }
        return query.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", labels, labels)).firstMatch
    }

    /// The screenshot, its tree and, when there is one, where the ring goes: `mark`'s frame
    /// in the screenshot's pixels. `ring` false keeps the place without a ring (a result, or
    /// the row the next step scrolls). `row` widens it to the whole width of the screen.
    private func snap(_ name: String, mark: XCUIElement? = nil, ring: Bool = true, row: Bool = false) {
        let shot = shortcuts.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name + tag
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: shortcuts.debugDescription)
        tree.name = name + tag + "-arbol"
        tree.lifetime = .keepAlways
        add(tree)
        guard let mark, mark.exists else { return }
        let scale = shot.image.scale
        let frame = mark.frame
        guard !frame.isEmpty, !frame.isInfinite else { return }
        let fields: [String: Any] = [
            "x": frame.minX * scale, "y": frame.minY * scale,
            "w": frame.width * scale, "h": frame.height * scale,
            "pantallaW": shot.image.size.width * scale, "pantallaH": shot.image.size.height * scale,
            "aro": ring, "fila": row,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
            let place = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            place.name = name + tag + "-marca"
            place.lifetime = .keepAlways
            add(place)
        }
    }

    /// Waits for `element` or leaves «falta-…» (screenshot and tree) and fails.
    private func require(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 8) {
        if !element.waitForExistence(timeout: timeout) {
            snap("falta-" + what)
            XCTFail("No encontré «\(what)»")
        }
    }

    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 8) {
        require(element, what, timeout: timeout)
        element.tap()
    }

    /// Like `tap`, for the steps the guide can do without (its Spanish pictures come from the
    /// owner's iPhone): leaves «falta-…» and says false instead of failing.
    private func tapIfThere(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 6) -> Bool {
        if !element.waitForExistence(timeout: timeout) {
            snap("falta-" + what)
            return false
        }
        element.tap()
        return true
    }

    // MARK: - The walk

    func testRecorrerLaAutomatizacion() {
        // Like someone who just installed it: Al día opened once, so Atajos knows its actions.
        let alDia = XCUIApplication()
        alDia.launchArguments = ["-AppleLanguages", words.languages[0], "-AppleLocale", words.locale, "-centavo-empty"]
        alDia.launch()
        // Long enough for iOS to hand Atajos the app's actions: with 3 s on a busy Mac the
        // search for «Registrar aviso» came back empty (local run, 2026-11-18).
        _ = alDia.wait(for: .runningForeground, timeout: 20)
        sleep(8)
        alDia.terminate()
        sleep(5)

        shortcuts.launch()
        let continueButton = find(shortcuts.buttons, words.continueButton)
        if continueButton.waitForExistence(timeout: 4) {
            snap("00-novedades", mark: continueButton)
            continueButton.tap()
        }
        sleep(1)

        // The «+» at the bottom of «Todos los atajos».
        let add = shortcuts.buttons.matching(NSPredicate(format: "label IN %@", words.add)).firstMatch
        require(add, "+")
        snap("01-todos-los-atajos", mark: add)
        tap(add, "+")
        sleep(2)
        // With Apple Intelligence it may open «Describir un atajo» first; «Editar» leaves it.
        let edit = shortcuts.buttons.matching(NSPredicate(format: "label IN %@", words.edit)).firstMatch
        if edit.waitForExistence(timeout: 3) {
            snap("01b-describir-un-atajo", mark: edit)
            edit.tap()
            sleep(1)
        }
        var automation = find(shortcuts.buttons, words.automation)
        // In English the editor opened with the actions drawer up, covering the bottom where
        // «Automation» sits (CI, 2026-11-19): pull the drawer down; failing that, back out to
        // the app's own «Automation» tab.
        if !automation.waitForExistence(timeout: 4) {
            let search = shortcuts.searchFields.firstMatch
            if search.exists {
                let from = search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                from.press(forDuration: 0.1, thenDragTo: shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
                sleep(1)
            }
            automation = find(shortcuts.buttons, words.automation)
        }
        if !automation.waitForExistence(timeout: 3) {
            let back = find(shortcuts.buttons, words.back)
            if back.exists { back.tap(); sleep(1) }
            automation = find(shortcuts.buttons, words.automation)
            if !automation.exists { automation = find(shortcuts.tabBars.buttons, words.automation) }
        }
        require(automation, "Automatización")
        snap("02-nuevo-atajo", mark: automation)

        tap(automation, "Automatización")
        sleep(1)
        snap("03-automatizacion")

        let notification = find(shortcuts.staticTexts, words.notificationTrigger)
        for _ in 0..<6 where !notification.isHittable { shortcuts.swipeUp() }
        snap("04-notificacion-en-la-lista", mark: notification)
        tap(notification, "Notificación")
        sleep(1)

        let app = find(shortcuts.buttons, words.app)
        require(app, "App")
        snap("05-bloque-notificacion", mark: app)
        tap(app, "App")
        sleep(1)
        snap("06-elegir-app")
        let wallet = find(shortcuts.staticTexts, words.wallet)
        for _ in 0..<4 where !wallet.isHittable { shortcuts.swipeUp() }
        snap("06b-wallet-en-la-lista", mark: wallet)
        tap(wallet, "Wallet")
        sleep(1)
        // What the trigger says now («… de Wallet»): a result, no ring.
        // In English «Wallet» is the value of the trigger's «App» field, not a text of its own.
        let chosen = find(shortcuts.staticTexts, words.wallet)
        snap("07-con-wallet", mark: chosen.exists ? chosen : shortcuts.buttons.matching(identifier: "enum").firstMatch, ring: false)

        let search = shortcuts.searchFields.firstMatch
        tap(search, "Buscar")
        focus(search)
        search.typeText(words.searchText)
        sleep(2)
        // The keyboard's one-time tip covers the results.
        let tip = find(shortcuts.buttons, words.continueButton)
        if tip.exists { tip.tap() }
        let action = find(shortcuts.cells, words.action)
        // On a freshly erased iPhone Atajos may not know Al día's actions yet (local runs on
        // a busy Mac, 2026-11-18): the library has no «Apps» and the search comes back empty.
        // Pull the drawer down, give it time and search again, up to three times.
        for _ in 0..<3 where !action.waitForExistence(timeout: 15) {
            let from = search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.1, thenDragTo: shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            sleep(30)
            let again = shortcuts.searchFields.firstMatch
            guard again.waitForExistence(timeout: 5) else { break }
            again.tap()
            focus(again)
            if let typed = again.value as? String, !typed.isEmpty, typed != again.placeholderValue {
                again.buttons.firstMatch.tap()
                sleep(1)
            }
            again.typeText(words.searchText)
            sleep(2)
        }
        require(action, "Registrar aviso de Wallet", timeout: 15)
        snap("08-buscar-accion", mark: action)
        tap(action, "Registrar aviso de Wallet")
        sleep(1)

        // The action's «Notificación» field, then the variable above the keyboard.
        let notice = field()
        require(notice, "campo Notificación")
        snap("09-accion-agregada", mark: notice)
        tap(notice, "campo Notificación")
        sleep(1)
        // The row above the keyboard starts on «Seleccionar variable»: the ring takes the row.
        let selectVariable = find(shortcuts.buttons, words.selectVariable)
        snap("10-elegir-variable", mark: selectVariable, row: true)
        let variable = barVariable()
        require(variable, "variable Notificación")
        // Slide the row until the bell shows, as the guide says to.
        // «isHittable» is true off screen too (XCUITest scrolls on tap): go by the frame.
        let onScreen = { self.shortcuts.frame.contains(variable.frame) }
        if selectVariable.exists && !onScreen() {
            let rowY = selectVariable.frame.midY
            for _ in 0..<4 where !onScreen() {
                let from = shortcuts.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: shortcuts.frame.width * 0.85, dy: rowY))
                let to = shortcuts.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: shortcuts.frame.width * 0.15, dy: rowY))
                from.press(forDuration: 0.05, thenDragTo: to)
                sleep(1)
            }
        }
        snap("10b-variable-a-la-vista", mark: variable)
        tap(variable, "variable Notificación")
        sleep(1)
        snap("11-conectada", mark: field(), ring: false)
        tap(find(shortcuts.buttons, words.closeKeyboard).firstMatch, "cerrar el teclado")
        sleep(1)
        // «Así debe verse» for the notice, without the keyboard.
        snap("11c-conectada", mark: field(), ring: false)

        connectSubtitle()

        // What the trigger's options say about asking before it runs.
        let expand = shortcuts.buttons.matching(NSPredicate(format: "identifier IN %@ OR label IN %@", words.expand, words.expand)).firstMatch
        tap(expand, "Expandir")
        sleep(1)
        let back = shortcuts.buttons.matching(NSPredicate(format: "identifier IN %@ OR label IN %@", words.back, words.back)).firstMatch
        snap("11b-opciones-del-disparador", mark: back)

        tap(back, "regresar")
        // On a busy Mac the editor took a while to leave (2026-11-18): wait for the list.
        let saved = find(shortcuts.staticTexts, words.action).firstMatch
        _ = shortcuts.searchFields.firstMatch.waitForNonExistence(timeout: 10)
        _ = saved.waitForExistence(timeout: 10)
        sleep(2)
        snap("12-guardada", mark: saved, ring: false)
    }

    /// «Comercio» from the notification's subtitle. Since 2026-10-22 the action's summary puts
    /// «Comercio» on its line («Registrar Notificación con comercio Comercio»), so there is no
    /// chevron to open first; an Atajos that still hides it behind one gets the chevron step.
    /// A step not found leaves its «falta-…» and the walk goes on to save.
    private func connectSubtitle() {
        let merchant = find(shortcuts.buttons, words.merchantField).firstMatch
        if merchant.waitForExistence(timeout: 4) {
            snap("13-comercio", mark: merchant)
        } else {
            // The action's chevron: the last «Expandir» on screen (the trigger's is above it).
            let expanders = shortcuts.buttons.matching(NSPredicate(format: "identifier IN %@ OR label IN %@", words.expand, words.expand))
            // Only one means it is the trigger's: tapping it would hide the «Expandir» saved for later.
            guard expanders.count > 1 else { snap("falta-flechita"); return }
            let chevron = expanders.element(boundBy: expanders.count - 1)
            snap("13-flechita", mark: chevron)
            guard tapIfThere(chevron, "flechita") else { return }
            sleep(1)
        }

        guard tapIfThere(merchant, "campo Comercio") else { return }
        sleep(1)
        let variable = barVariable()
        guard tapIfThere(variable, "variable Notificación en Comercio") else { closeKeyboard(); return }
        sleep(1)
        closeKeyboard()

        // «Comercio» now holds a «Notificación»: the field keeps its label («Comercio») and the
        // variable is its value, so the field itself is the token. Never the first
        // «Notificación»: that one is the notice's, and «Subtítulo» there logs nothing.
        guard tapIfThere(merchant, "Notificación en Comercio") else { return }
        sleep(1)
        let subtitle = find(shortcuts.buttons, words.subtitle).firstMatch
        let subtitleAny = subtitle.exists ? subtitle : find(shortcuts.staticTexts, words.subtitle).firstMatch
        guard subtitleAny.waitForExistence(timeout: 4) else { snap("falta-Subtitulo"); return }
        snap("14-subtitulo", mark: subtitleAny)
        subtitleAny.tap()
        sleep(1)
        // The variable's sheet stays up after choosing: pull it down to see the action.
        if subtitleAny.exists && subtitleAny.isHittable {
            let top = shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49))
            top.press(forDuration: 0.1, thenDragTo: shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            sleep(2)
        }

        let show = find(shortcuts.switches, words.showWhenRun).firstMatch
        for _ in 0..<3 where show.exists && !show.isHittable { shortcuts.swipeUp() }
        guard show.waitForExistence(timeout: 4) else {
            // No «Mostrar al ejecutar» without a chevron: the result is the action's line.
            snap("16-accion-lista", mark: field(), ring: false)
            return
        }
        snap("15-mostrar", mark: show)
        show.tap()
        sleep(1)
        for _ in 0..<3 where !find(shortcuts.cells, words.action).isHittable && !field().isHittable { shortcuts.swipeDown() }
        snap("16-accion-lista", mark: field(), ring: false)
    }

    /// A tap on the drawer's search field may only bring the drawer up (a busy Mac, 2026-11-18):
    /// taps again until the field has the keyboard.
    private func focus(_ field: XCUIElement) {
        for _ in 0..<3 where (field.value(forKey: "hasKeyboardFocus") as? Bool) != true {
            sleep(2)
            field.tap()
        }
    }

    /// The action's «Notificación» field (`textInput`), never the bell of the same name in the
    /// row above the keyboard.
    private func field() -> XCUIElement {
        shortcuts.buttons.matching(NSPredicate(format: "identifier == 'textInput' AND label IN %@", words.noticeField)).firstMatch
    }

    /// The «Notificación» variable in the row above the keyboard (the bell), never a field.
    private func barVariable() -> XCUIElement {
        shortcuts.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND identifier != 'textInput'", words.noticeVariable)).firstMatch
    }

    private func closeKeyboard() {
        let close = find(shortcuts.buttons, words.closeKeyboard).firstMatch
        if close.exists { close.tap(); sleep(1) }
    }
}
