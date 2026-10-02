import XCTest

/// Drives the parent app against the in-memory mock server (`-uiTesting`).
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

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
    }

    /// Finds an element by identifier regardless of its accessibility type.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Taps a field until the keyboard appears, then types and presses Return so the pinned bar is tappable.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        dismissSavePasswordPromptIfNeeded(in: app)
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
            dismissSavePasswordPromptIfNeeded(in: app)
        }
        field.typeText(text + "\n")
    }

    /// iOS may offer to save the password after account creation; the sheet covers the whole screen.
    private func dismissSavePasswordPromptIfNeeded(in app: XCUIApplication, timeout: TimeInterval = 1) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: timeout) {
            notNow.tap()
        }
    }

    /// Scrolls until the element clears the pinned action bar, then taps it.
    private func tapScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        waitFor(element)
        let coveredBelow = app.frame.maxY - 170
        var attempts = 0
        while (!element.isHittable || element.frame.maxY > coveredBelow) && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        element.tap()
    }

    private func createAccount(in app: XCUIApplication) {
        let name = app.textFields["account.name"]
        waitFor(name)
        type("Randy Cruz", into: name, in: app)
        type("newparent@example.com", into: app.textFields["account.email"], in: app)
        type("safe-password-10", into: app.secureTextFields["account.password"], in: app)
        tapScrolling(element("account.guardian", in: app), in: app)
        tapScrolling(app.buttons["account.create"], in: app)
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

        // 03 Create Account (POST /auth/register)
        createAccount(in: app)

        // 04 Add Child (POST /children)
        waitFor(app.otherElements["onboarding.progress.2"])
        type("Mia", into: app.textFields["child.nameField"], in: app)
        XCTAssertTrue(app.buttons["child.continue"].isEnabled)
        app.buttons["child.continue"].tap()

        // 05 Protection Profile (GET /profiles)
        waitFor(app.otherElements["onboarding.progress.3"])
        waitFor(app.buttons["profile.option.protected"])
        app.buttons["profile.option.protected"].tap()
        app.buttons["profile.continue"].tap()

        // 06 Recommended Setup (GET /recommendations)
        waitFor(app.otherElements["onboarding.progress.4"])
        waitFor(app.buttons["recommended.edit.bedtime"])
        app.buttons["recommended.reviewSetup"].tap()

        // 07 Setup Progress: no device yet, so settings are saved (POST /setup → batchId null)
        waitFor(app.otherElements["onboarding.progress.5"])
        waitFor(app.buttons["setup.skip"])
        app.buttons["setup.skip"].tap()
        waitFor(element("setup.saved", in: app))
        app.buttons["configure.continue"].tap()

        // 08 Configuration Health (GET /health?childId=)
        waitFor(app.otherElements["onboarding.progress.6"])
        waitFor(element("health.score", in: app))
        app.buttons["health.continue"].tap()

        // 09 Complete
        waitFor(app.otherElements["onboarding.progress.7"])
        app.buttons["complete.goToDashboard"].tap()

        // Dashboard
        waitFor(app.buttons["dashboard.manageProtection"])
        waitFor(app.buttons["dashboard.viewHealth"])
    }

    @MainActor
    func testPairingAndGuidedSetupVerifyThroughABatch() throws {
        // A brand-new sign-up is unverified and can't pair, so sign in as the verified parent instead.
        let app = launch()
        app.buttons["welcome.signIn"].tap()
        type("randy@example.com", into: app.textFields["signIn.email"], in: app)
        type("ChangeMe123!", into: app.secureTextFields["signIn.password"], in: app)
        app.buttons["signIn.submit"].tap()
        dismissSavePasswordPromptIfNeeded(in: app, timeout: 4)
        waitFor(app.textFields["child.nameField"])
        type("Mia", into: app.textFields["child.nameField"], in: app)
        app.buttons["child.continue"].tap()
        waitFor(app.buttons["profile.continue"])
        app.buttons["profile.continue"].tap()
        waitFor(app.buttons["recommended.reviewSetup"])
        app.buttons["recommended.reviewSetup"].tap()

        // Pair a device with the code sheet (POST /pairing-code), simulated by the mock server.
        waitFor(app.buttons["setup.pair"])
        app.buttons["setup.pair"].tap()
        waitFor(element("pairing.code", in: app))
        app.buttons["pairing.simulate"].tap()
        waitFor(element("pairing.paired", in: app))
        app.buttons["pairing.close"].tap()

        // The batch runs; WEB is guided on iPhone and needs confirmation.
        let web = app.buttons["configure.feature.web"]
        tapScrolling(web, in: app)
        waitFor(app.buttons["guide.confirm"])
        app.buttons["guide.confirm"].tap()
        waitFor(element("setup.done", in: app), timeout: 20)
        app.buttons["configure.continue"].tap()
        waitFor(element("health.score", in: app))
    }

    @MainActor
    func testSignInWithWrongPasswordShowsServerMessage() throws {
        let app = launch()
        app.buttons["welcome.signIn"].tap()
        type("randy@example.com", into: app.textFields["signIn.email"], in: app)
        type("wrong-password-1", into: app.secureTextFields["signIn.password"], in: app)
        app.buttons["signIn.submit"].tap()
        waitFor(element("inlineError", in: app))
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
    func testModeChooserLeadsToTheParentSideOrChildSetup() throws {
        let app = launch(arguments: ["-modeUnset"])
        waitFor(app.buttons["mode.parent"])
        app.buttons["mode.child"].tap()
        waitFor(app.textFields["childSetup.code"])
        XCTAssertFalse(app.buttons["childSetup.continue"].isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        waitFor(app.buttons["mode.parent"])
        app.buttons["mode.parent"].tap()
        waitFor(app.buttons["welcome.getStarted"])
    }

    @MainActor
    func testHandingDownThisDeviceSwitchesToChildMode() throws {
        let app = launch(arguments: ["-setupComplete"])
        waitFor(app.buttons["dashboard.manageProtection"])
        app.tabBars.buttons["Settings"].tap()
        tapScrolling(app.buttons["settings.setUpChildDevice"], in: app)

        // Choose the child, confirm the hand-off, keep the suggested name, pair through the mock device API.
        waitFor(app.staticTexts["Mia"])
        app.staticTexts["Mia"].tap()
        app.buttons["handDown.continue"].tap()
        waitFor(app.buttons["handDown.confirm"])
        app.buttons["handDown.confirm"].tap()
        waitFor(app.textFields["handDown.name"])
        app.buttons["handDown.pair"].tap()

        // The install is now the child's: the parent session is gone and setup continues at permissions.
        // The seeded mock already has Screen Time approved, so Continue is available straight away.
        waitFor(app.buttons["childSetup.permissionsContinue"], timeout: 15)
        XCTAssertTrue(app.buttons["childSetup.permissionsContinue"].isEnabled)
        app.buttons["childSetup.permissionsContinue"].tap()
        waitFor(app.buttons["childSetup.finish"])
        app.buttons["childSetup.finish"].tap()
        waitFor(app.buttons["childSetup.done"])
        app.buttons["childSetup.done"].tap()
        waitFor(element("childHome.syncCard", in: app))
        waitFor(app.buttons["childHome.askApp"])
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
    }

    @MainActor
    func testTabsAndSettingsMenuAreReachable() throws {
        let app = launch(arguments: ["-setupComplete"])
        waitFor(app.buttons["dashboard.manageProtection"])
        app.tabBars.buttons["Alerts"].tap()
        waitFor(app.staticTexts["Alerts"])
        app.tabBars.buttons["Settings"].tap()
        waitFor(app.buttons["settings.signOut"])
        app.tabBars.buttons["Children"].tap()
        waitFor(app.buttons["children.child"].firstMatch)
    }
}
