import CentavoCore
import XCTest
@testable import Centavo

/// «Cómo funciona» sin presupuesto (2026-11-18): sin él no hay «Hoy puedes gastar» y arriba
/// queda el total del mes, así que las historias de la cifra no la señalan como si existiera.
final class GuiaTutorialTests: XCTestCase {
    func testWithBudgetTheStoriesStayAsTheyWere() {
        for story in TutorialStory.allCases {
            XCTAssertEqual(story.text(hasBudget: true), story.text)
        }
    }

    func testWithoutBudgetTheFigureIsNotThePromisedOne() {
        let figure = TutorialStory.figure.text(hasBudget: false)
        XCTAssertFalse(figure.contains("esa es la cifra de arriba"))
        XCTAssertTrue(figure.hasPrefix("Con un presupuesto"))
        XCTAssertTrue(TutorialStory.leftover.text(hasBudget: false).hasPrefix("Con un presupuesto"))
        // The rest don't depend on a budget.
        for story in TutorialStory.allCases where story != .figure && story != .leftover {
            XCTAssertEqual(story.text(hasBudget: false), story.text)
        }
    }

    func testTheTimeFollowsTheTextShown() {
        let story = TutorialStory.figure
        XCTAssertEqual(story.duration(hasBudget: false),
                       StoryTiming.duration(for: [story.title, story.text(hasBudget: false)]))
    }

    // MARK: Segunda ronda (2026-11-18)

    /// Con VoiceOver no hay «mantener presionado»: la historia dice el camino por la hoja.
    func testUncountedWithVoiceOverSaysTheSheet() {
        let spoken = TutorialStory.uncounted.text(hasBudget: true, voiceOver: true)
        XCTAssertFalse(spoken.contains("mantenlo presionado"))
        XCTAssertTrue(spoken.contains("«Tipo»"))
        XCTAssertEqual(TutorialStory.uncounted.text(hasBudget: true, voiceOver: false), TutorialStory.uncounted.text)
        for story in TutorialStory.allCases where story != .uncounted {
            XCTAssertEqual(story.text(hasBudget: false, voiceOver: true), story.text(hasBudget: false))
        }
    }

    /// La barra de una historia que no cabe no salta a llena: se queda vacía hasta «Siguiente».
    func testBarOfAStoryThatScrollsStaysEmpty() {
        XCTAssertEqual(TutorialView.barFill(1, current: 2, scrolls: true), 1)
        XCTAssertEqual(TutorialView.barFill(2, current: 2, scrolls: true), 0)
        XCTAssertEqual(TutorialView.barFill(2, current: 2, scrolls: false), 1)
        XCTAssertEqual(TutorialView.barFill(3, current: 2, scrolls: false), 0)
    }

    /// Un solo orden para toda la guía: el dibujo primero hasta medir; los pasos primero solo
    /// en pantallas cortas.
    func testGuideOrderIsDecidedByOneHeight() {
        XCTAssertEqual(GuideLayout.blocks(roomHeight: nil), [.picture, .taps])
        XCTAssertEqual(GuideLayout.blocks(roomHeight: 0), [.picture, .taps])
        XCTAssertEqual(GuideLayout.blocks(roomHeight: 380), [.taps, .picture])
        XCTAssertEqual(GuideLayout.blocks(roomHeight: Theme.Size.guideRoomyHeight), [.picture, .taps])
        XCTAssertEqual(GuideLayout.blocks(roomHeight: 620), [.picture, .taps])
    }

    /// «Toca para abrir la guía»: la guía empieza en el paso 1, no promete seguir donde iba.
    func testWaitingDoesNotPromiseToResume() {
        XCTAssertFalse(CaptureCopy.waiting.contains("Toca para seguir"))
        XCTAssertTrue(CaptureCopy.waiting.hasSuffix("Toca para abrir la guía."))
    }

    /// En iOS 26 días sin pagos sin contacto no son un atajo roto: lo dice.
    func testQuietSaysWhatIOS26Catches() {
        if ShortcutsVersion.isIOS27 {
            XCTAssertEqual(CaptureCopy.quiet, "Si sí pagaste, toca para revisar el atajo.")
        } else {
            XCTAssertTrue(CaptureCopy.quiet.contains("acercando el iPhone"))
            XCTAssertTrue(CaptureCopy.quiet.contains("en línea"))
        }
    }

    /// Las pruebas corren en español: ahí las capturas de la guía de iOS 27 coinciden.
    func testPhotosMatchSpanish() {
        XCTAssertTrue(GuideFrame.photosMatchLanguage)
    }
}
