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

    @MainActor
    func testEveryOnboardingScreenInOrder() throws {
        let app = launch()

        // 01 Welcome
        waitFor(app.otherElements["onboarding.progress.1"])
        waitFor(app.buttons["welcome.checkSetup"])
        app.buttons["welcome.getStarted"].tap()

        // 02 Child & Device
        waitFor(app.otherElements["onboarding.progress.2"])
        let nameField = app.textFields["child.nameField"]
        waitFor(nameField)
        nameField.tap()
        nameField.typeText("Mia")
        app.buttons["child.relationship.childInFamilySharing"].tap()
        XCTAssertTrue(app.buttons["child.continue"].isEnabled)
        app.buttons["child.continue"].tap()

        // 03 Protection Profile
        waitFor(app.otherElements["onboarding.progress.3"])
        app.buttons["profile.option.protected"].tap()
        app.buttons["profile.continue"].tap()

        // 04 Recommended Setup
        waitFor(app.otherElements["onboarding.progress.4"])
        waitFor(app.buttons["recommended.edit.downtime"])
        app.buttons["recommended.reviewSetup"].tap()

        // 05 Configure Settings, including Apple authorization
        waitFor(app.otherElements["onboarding.progress.5"])
        app.buttons["configure.authorize"].tap()
        waitFor(app.buttons["authorization.continue"])
        app.buttons["authorization.continue"].tap()
        waitFor(app.buttons["authorization.done"])
        app.buttons["authorization.done"].tap()

        waitFor(app.buttons["configure.feature.webContent"])
        app.buttons["configure.feature.webContent"].tap()
        waitFor(app.buttons["feature.configure"])
        app.buttons["feature.configure"].tap()
        waitFor(app.otherElements["feature.result"])
        app.buttons["feature.continue"].tap()
        waitFor(app.buttons["configure.continue"])
        app.buttons["configure.continue"].tap()

        // 06 Configuration Health Check
        waitFor(app.otherElements["onboarding.progress.6"])
        waitFor(app.staticTexts["health.score"])
        app.buttons["health.continue"].tap()

        // 07 Complete
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
        let nameField = app.textFields["child.nameField"]
        waitFor(nameField)
        nameField.tap()
        nameField.typeText("Mia")
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
        waitFor(app.buttons["configure.feature.screenTimePasscode"])
        app.buttons["configure.feature.screenTimePasscode"].tap()
        waitFor(app.buttons["feature.later"])
        app.buttons["feature.later"].tap()
        waitFor(app.buttons["configure.checkConfiguration"])
    }

    @MainActor
    func testCompletedSetupOpensDashboardAndHealthReview() throws {
        let app = launch(arguments: ["-setupComplete"])
        waitFor(app.staticTexts["dashboard.healthScore"])
        app.buttons["dashboard.viewHealth"].tap()
        waitFor(app.staticTexts["health.score"])
        waitFor(app.buttons["health.checkAgain"])
    }
}
