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
}
