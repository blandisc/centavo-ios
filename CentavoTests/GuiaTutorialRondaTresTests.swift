import XCTest
@testable import Centavo

/// Tercera ronda (2026-11-18): la guía vuelve al paso en que ibas, solo dentro de la misma
/// configuración.
final class GuiaTutorialRondaTresTests: XCTestCase {
    func testSameSessionReopensOnTheSavedStep() {
        XCTAssertEqual(GuideResume.step(saved: 4, savedSession: 100, session: 100, count: 8), 4)
        XCTAssertEqual(GuideResume.step(saved: 0, savedSession: 100, session: 100, count: 8), 0)
    }

    func testANewSetupStartsOnStepOne() {
        // Another session, none, or nothing saved: from the beginning.
        XCTAssertNil(GuideResume.step(saved: 4, savedSession: 100, session: 200, count: 8))
        XCTAssertNil(GuideResume.step(saved: 4, savedSession: 0, session: 0, count: 8))
        XCTAssertNil(GuideResume.step(saved: nil, savedSession: 100, session: 100, count: 8))
    }

    func testAStepThatNoLongerExistsIsIgnored() {
        // Saved on iOS 26 (8 steps), reopened with 7.
        XCTAssertNil(GuideResume.step(saved: 7, savedSession: 100, session: 100, count: 7))
        XCTAssertNil(GuideResume.step(saved: -1, savedSession: 100, session: 100, count: 7))
    }

    func testSaveKeepsTheSessionAndStaysOutOfTheBackup() throws {
        let name = "GuiaTutorialRondaTresTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(123.0, forKey: CaptureArrival.sessionKey)
        GuideResume.save(3, defaults: defaults)
        let saved = defaults.object(forKey: GuideResume.stepKey) as? Int
        XCTAssertEqual(GuideResume.step(saved: saved,
                                        savedSession: defaults.double(forKey: GuideResume.sessionKey),
                                        session: defaults.double(forKey: CaptureArrival.sessionKey),
                                        count: 8), 3)
        XCTAssertTrue(GuideResume.stepKey.hasPrefix("respaldo."))
        XCTAssertTrue(GuideResume.sessionKey.hasPrefix("respaldo."))
    }
}
