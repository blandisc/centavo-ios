import XCTest

/// Not a test: types text into whatever field has the keyboard, in any app on the
/// simulator. Used to drive Atajos by hand (the simulator tool cannot type there).
///     TEST_RUNNER_CENTAVO_TEXTO="Registrar aviso" xcodebuild test-without-building …
final class TypingHelperTests: XCTestCase {
    @MainActor
    func testEscribir() throws {
        let text = ProcessInfo.processInfo.environment["CENTAVO_TEXTO"] ?? ""
        try XCTSkipIf(text.isEmpty, "Solo se usa a mano")
        let bundle = ProcessInfo.processInfo.environment["CENTAVO_APP"] ?? "com.apple.shortcuts"
        XCUIApplication(bundleIdentifier: bundle).typeText(text)
    }
}
