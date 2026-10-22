import XCTest

/// Smoke tests against the real app. There is no mock server, so these cover only the screens that
/// need no account or network: the mode chooser, child setup entry and the parent welcome screen.
/// Run them on a simulator with nothing signed in.
final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
    }

    /// The splash fades out over the first screen, so wait until taps can land before tapping.
    private func tapWhenHittable(_ element: XCUIElement, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element, timeout: timeout, file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: timeout), .completed, "Not hittable: \(element)", file: file, line: line)
        element.tap()
    }

    @MainActor
    func testModeChooserLeadsToTheParentSideOrChildSetup() throws {
        let app = XCUIApplication()
        app.launch()

        // "Who's using this device?"
        waitFor(app.buttons["mode.parent"])
        tapWhenHittable(app.buttons["mode.child"])

        // Child setup asks for a code and can go back; nothing is stored until pairing succeeds.
        waitFor(app.textFields["childSetup.code"])
        XCTAssertFalse(app.buttons["childSetup.continue"].isEnabled)
        tapWhenHittable(app.navigationBars.buttons.firstMatch)

        // The parent side starts at Welcome.
        tapWhenHittable(app.buttons["mode.parent"])
        waitFor(app.buttons["welcome.getStarted"])
        waitFor(app.buttons["welcome.signIn"])
    }
}
