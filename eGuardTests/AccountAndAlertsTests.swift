import Foundation
import Testing
@testable import MyApp

@Suite("Accounts")
struct AccountTests {
    @Test func validationCatchesBadInput() {
        #expect(AccountValidator.validateName("R") != nil)
        #expect(AccountValidator.validateName("Randy Cruz") == nil)
        #expect(AccountValidator.validateEmail("randy@example") != nil)
        #expect(AccountValidator.validateEmail("randy@example.com") == nil)
        #expect(AccountValidator.validatePassword("short") != nil)
        #expect(AccountValidator.validatePassword("long-enough") == nil)
    }

    @Test func passwordsAreHashedAndVerified() {
        let account = AccountValidator.makeEmailAccount(fullName: " Randy Cruz ", email: "Randy@Example.com", password: "safe-password-1")
        #expect(account.fullName == "Randy Cruz")
        #expect(account.email == "randy@example.com")
        #expect(account.passwordHash != "safe-password-1")
        #expect(account.verify(password: "safe-password-1"))
        #expect(!account.verify(password: "wrong"))
        #expect(account.firstName == "Randy")
    }

    @Test func signInChecksStoredAccount() throws {
        let model = AppModel.mock()
        #expect(!model.isSignedIn)
        #expect(throws: AccountError.noAccount) { try model.signIn(email: "a@b.co", password: "x") }

        model.createAccount(AccountValidator.makeEmailAccount(fullName: "Randy Cruz", email: "randy@example.com", password: "safe-password-1"))
        model.signOut()
        #expect(!model.isSignedIn)
        #expect(throws: AccountError.emailMismatch) { try model.signIn(email: "other@example.com", password: "safe-password-1") }
        #expect(throws: AccountError.wrongPassword) { try model.signIn(email: "randy@example.com", password: "nope") }
        try model.signIn(email: "RANDY@example.com", password: "safe-password-1")
        #expect(model.isSignedIn)
    }

    @Test func thirdPartySignInReusesMatchingAccount() {
        let model = AppModel.mock()
        model.signIn(provider: .apple, fullName: "Randy Cruz", email: "randy@privaterelay.appleid.com")
        #expect(model.account?.provider == .apple)
        model.signOut()
        model.signIn(provider: .apple, fullName: nil, email: nil)
        #expect(model.account?.fullName == "Randy Cruz")
    }

    @Test func childProfileWithPhotoRoundTrips() throws {
        let profile = ChildProfile(name: "Mia", age: 12, photoData: Data([0xFF, 0xD8]))
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(ChildProfile.self, from: data) == profile)
        #expect(profile.deviceName == "Mia's iPhone")

        // Older profiles without a photo still decode.
        let legacy = #"{"name":"Mia","age":12,"device":"iPhone","relationship":"childInFamilySharing"}"#
        #expect(try JSONDecoder().decode(ChildProfile.self, from: Data(legacy.utf8)).photoData == nil)
    }
}

@Suite("Alerts")
struct AlertTests {
    private func check(_ feature: ProtectionFeature, _ status: HealthStatus) -> ConfigurationCheck {
        ConfigurationCheck(feature: feature, status: status, mode: .automatic, explanation: "why")
    }

    @Test func reportsBecomeAlertsForNonPassingChecks() {
        let report = ConfigurationHealthReport(
            checks: [check(.downtime, .pass), check(.gaming, .warning), check(.webContent, .actionRequired), check(.purchases, .notConfigured), check(.screenTimePasscode, .unsupported)],
            generatedAt: .now
        )
        let alerts = AlertGenerator.alerts(from: report, deviceName: "Mia's iPhone")
        #expect(alerts.count == 3)
        #expect(alerts.first { $0.feature == .gaming }?.category == .apps)
        #expect(alerts.first { $0.feature == .webContent }?.category == .protection)
        #expect(alerts.first { $0.feature == .purchases }?.detail == "Mia's iPhone")
    }

    @Test func mergeDropsSameDayDuplicatesAndSortsNewestFirst() {
        let older = ProtectionAlert(category: .protection, title: "Downtime not configured", detail: "x", date: .now.addingTimeInterval(-600), feature: .downtime)
        let duplicate = ProtectionAlert(category: .protection, title: "Downtime not configured", detail: "x", date: .now, feature: .downtime)
        let other = ProtectionAlert(category: .location, title: "Location sharing turned on", detail: "x", date: .now)
        let merged = AlertGenerator.merge([duplicate, other], into: [older])
        #expect(merged.count == 2)
        #expect(merged.first?.title == "Location sharing turned on")
    }

    @Test func healthCheckRecordsAlertsOnlyAfterSetup() {
        let model = AppModel.mock(authorizationStatus: .approved)
        model.saveChildProfile(ChildProfile(name: "Mia", age: 12))
        model.chooseProfile(.balanced)
        model.performHealthCheck()
        #expect(model.alerts.isEmpty)

        model.completeSetup()
        model.performHealthCheck()
        #expect(!model.alerts.isEmpty)
        #expect(model.unreadAlertCount > 0)
        model.markAllAlertsRead()
        #expect(model.unreadAlertCount == 0)
    }

    @Test func preferencesRecordVisitsAndLocationToggleAlerts() {
        let model = AppModel.mock()
        model.setLocationSharing(true)
        #expect(model.preferences.isLocationSharingEnabled)
        #expect(model.alerts.first?.category == .location)

        model.recordVisit(LocationVisit(name: "Home", latitude: 10.0, longitude: 124.0))
        model.recordVisit(LocationVisit(name: "Home", latitude: 10.0005, longitude: 124.0005))
        #expect(model.preferences.visits.count == 1)
        #expect(model.preferences.lastKnownPlace == "Home")
    }

    @Test func resetForgetsAccountAndAlerts() {
        let model = AppModel.preview()
        #expect(model.isSignedIn)
        model.resetEverything()
        #expect(!model.isSignedIn)
        #expect(model.alerts.isEmpty)
        #expect(model.preferences == AppPreferences())
    }
}
