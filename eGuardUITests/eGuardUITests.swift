import XCTest

/// Drives every onboarding screen with mock platform services (`-uiTesting`).
final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
    }

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
    }

    /// Finds an element by identifier regardless of its accessibility type.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Taps a field until the keyboard appears, then types. A tap can land while the previous
    /// screen's keyboard is still dismissing, which leaves nothing focused.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        dismissSavePasswordPromptIfNeeded(in: app)
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
            dismissSavePasswordPromptIfNeeded(in: app)
        }
        // Return dismisses the keyboard so the pinned action bar is tappable afterwards.
        field.typeText(text + "\n")
    }

    /// iOS may offer to save the password after account creation; the sheet covers the whole screen.
    private func dismissSavePasswordPromptIfNeeded(in app: XCUIApplication, timeout: TimeInterval = 1) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: timeout) {
            notNow.tap()
        }
    }

    /// Scrolls until the element is hittable, since rows near the bottom sit under the pinned action bar.
    private func tapScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        waitFor(element)
        // The pinned action bar occupies roughly the bottom 170 points and is translucent,
        // so hit-testing still reports rows under it as hittable.
        let coveredBelow = app.frame.maxY - 170
        var attempts = 0
        while (!element.isHittable || element.frame.maxY > coveredBelow) && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        element.tap()
    }

    /// Fills the Create Account form, which precedes the child step for a new parent.
    private func createAccount(in app: XCUIApplication) {
        let name = app.textFields["account.name"]
        waitFor(name)
        type("Randy Cruz", into: name, in: app)
        type("randy@example.com", into: app.textFields["account.email"], in: app)
        type("safe-password-1", into: app.secureTextFields["account.password"], in: app)
        app.buttons["account.create"].tap()
        dismissSavePasswordPromptIfNeeded(in: app, timeout: 4)
        waitFor(app.textFields["child.nameField"])
    }

    @MainActor
    func testEveryOnboardingScreenInOrder() throws {
        let app = launch()

        // 01 Welcome
        waitFor(app.otherElements["onboarding.progress.1"])
        waitFor(app.buttons["welcome.signIn"])
        app.buttons["welcome.getStarted"].tap()

        // 02 Create Account
        createAccount(in: app)

        // 03 Child & Device
        waitFor(app.otherElements["onboarding.progress.2"])
        let nameField = app.textFields["child.nameField"]
        waitFor(nameField)
        type("Mia", into: nameField, in: app)
        app.buttons["child.relationship.childInFamilySharing"].tap()
        XCTAssertTrue(app.buttons["child.continue"].isEnabled)
        app.buttons["child.continue"].tap()

        // 04 Protection Profile
        waitFor(app.otherElements["onboarding.progress.3"])
        app.buttons["profile.option.protected"].tap()
        app.buttons["profile.continue"].tap()

        // 05 Recommended Setup
        waitFor(app.otherElements["onboarding.progress.4"])
        waitFor(app.buttons["recommended.edit.downtime"])
        app.buttons["recommended.reviewSetup"].tap()

        // 06 Configure Settings, including Apple authorization
        waitFor(app.otherElements["onboarding.progress.5"])
        app.buttons["configure.authorize"].tap()
        waitFor(app.buttons["authorization.continue"])
        app.buttons["authorization.continue"].tap()
        waitFor(app.buttons["authorization.done"])
        app.buttons["authorization.done"].tap()

        tapScrolling(app.buttons["configure.feature.webContent"], in: app)
        waitFor(app.buttons["feature.configure"])
        app.buttons["feature.configure"].tap()
        waitFor(app.otherElements["feature.result"])
        app.buttons["feature.continue"].tap()
        waitFor(app.buttons["configure.continue"])
        app.buttons["configure.continue"].tap()

        // 07 Configuration Health Check
        waitFor(app.otherElements["onboarding.progress.6"])
        waitFor(element("health.score", in: app))
        app.buttons["health.continue"].tap()

        // 08 Complete
        waitFor(app.otherElements["onboarding.progress.7"])
        app.buttons["complete.goToDashboard"].tap()

        // Dashboard
        waitFor(app.buttons["dashboard.manageProtection"])
        waitFor(app.buttons["dashboard.viewHealth"])
    }

    @MainActor
    func testDeniedAuthorizationOffersRetryAndContinueWithout() throws {
        let app = launch(arguments: ["-denyAuthorization"])
        app.buttons["welcome.getStarted"].tap()
        createAccount(in: app)
        let nameField = app.textFields["child.nameField"]
        waitFor(nameField)
        type("Mia", into: nameField, in: app)
        app.buttons["child.continue"].tap()
        app.buttons["profile.continue"].tap()
        waitFor(app.buttons["recommended.reviewSetup"])
        app.buttons["recommended.reviewSetup"].tap()
        waitFor(app.buttons["configure.authorize"])
        app.buttons["configure.authorize"].tap()
        waitFor(app.buttons["authorization.continue"])
        app.buttons["authorization.continue"].tap()

        waitFor(app.otherElements["authorization.denied"])
        XCTAssertTrue(app.buttons["authorization.tryAgain"].exists)
        app.buttons["authorization.continueWithout"].tap()
        waitFor(app.buttons["configure.authorize"])
    }

    @MainActor
    func testGuidedSettingCanBeDeferred() throws {
        let app = launch(arguments: ["-setupComplete"])
        waitFor(app.buttons["dashboard.manageProtection"])
        app.buttons["dashboard.manageProtection"].tap()
        tapScrolling(app.buttons["configure.feature.screenTimePasscode"], in: app)
        waitFor(app.buttons["feature.later"])
        app.buttons["feature.later"].tap()
        waitFor(app.buttons["configure.checkConfiguration"])
    }

    @MainActor
    func testCompletedSetupOpensDashboardAndHealthReview() throws {
        let app = launch(arguments: ["-setupComplete"])
        waitFor(app.buttons["dashboard.viewHealth"])
        app.buttons["dashboard.viewHealth"].tap()
        waitFor(element("health.score", in: app))
        waitFor(app.buttons["health.checkAgain"])
    }

    @MainActor
    func testTabsAndSettingsMenuAreReachable() throws {
        let app = launch(arguments: ["-setupComplete"])
        waitFor(app.buttons["dashboard.manageProtection"])
        app.tabBars.buttons["Alerts"].tap()
        waitFor(app.staticTexts["Alerts"])
        app.tabBars.buttons["Settings"].tap()
        waitFor(app.buttons["settings.reset"])
        app.tabBars.buttons["Children"].tap()
        waitFor(app.buttons["children.child"])
    }
}
