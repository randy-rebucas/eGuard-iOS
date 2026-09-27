import Foundation
import Testing
@testable import MyApp

@Suite("Accounts and sessions")
struct AccountTests {
    @Test func validationMirrorsTheAPIRules() {
        #expect(AccountValidator.validateName("R") != nil)
        #expect(AccountValidator.validateName("Randy Cruz") == nil)
        #expect(AccountValidator.validateEmail("randy@example") != nil)
        #expect(AccountValidator.validateEmail("randy@example.com") == nil)
        #expect(AccountValidator.validatePassword("short") != nil)
        #expect(AccountValidator.validatePassword("long-enough") == nil)
    }

    @Test func registerSignsInAndStartsAnEmptyFamily() async throws {
        let model = AppModel.mock()
        #expect(!model.isSignedIn)
        try await model.register(name: "Randy Cruz", email: "New@Example.com", password: "ChangeMe123!")
        #expect(model.isSignedIn)
        #expect(model.user?.email == "new@example.com")
        #expect(model.user?.isAdmin == true)
        #expect(model.user?.isEmailVerified == false)
        #expect(model.hasChildren == false)
        #expect(!model.isSetupComplete)
    }

    @Test func duplicateEmailIsAConflict() async {
        let model = AppModel.mock()
        await #expect(throws: APIError.self) {
            try await model.register(name: "Randy Cruz", email: "randy@example.com", password: "ChangeMe123!")
        }
    }

    @Test func loginChecksCredentialsAndLoadsTheDashboard() async throws {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api)
        await #expect(throws: APIError.self) {
            try await model.signIn(email: "randy@example.com", password: "wrong")
        }
        try await model.signIn(email: "RANDY@example.com", password: "ChangeMe123!")
        #expect(model.isSignedIn)
        #expect(model.children.count == 3)
        #expect(model.isSetupComplete)
        #expect(model.unreadAlerts > 0)
    }

    @Test func unauthorizedClearsTheSession() async {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api, signedIn: true)
        api.nextError = APIError.server(status: 401, code: "invalid_token", message: "Session ended.")
        await model.refreshDashboard()
        #expect(!model.isSignedIn)
        #expect(model.user == nil)
    }

    @Test func signOutEndsTheServerSession() async {
        let model = AppModel.mock(api: .seeded(), signedIn: true)
        await model.signOut()
        #expect(!model.isSignedIn)
        #expect(model.dashboard == nil)
    }

    @Test func appInfoGateBlocksOldBuilds() async {
        let api = MockEGuardAPI.seeded()
        api.appInfoValue.minimumAppVersion = "99.0"
        let model = AppModel.mock(api: api, signedIn: true)
        await model.bootstrap()
        #expect(model.bootstrapState == .updateRequired(minimum: "99.0"))
        #expect(AppInfo.compare("1.2", "1.10") < 0)
        #expect(AppInfo.compare("2.0", "2") == 0)
    }

    @Test func appleSignInRetriesWithGuardianConfirmation() async throws {
        let model = AppModel.mock()
        let isNew = try await model.signInWithApple(identityToken: "eyJhbGciOi.apple-token", fullName: "Randy Cruz")
        #expect(isNew)
        #expect(model.user?.isEmailVerified == true)
    }
}

@Suite("Onboarding flow against the mock server")
struct OnboardingFlowTests {
    @Test func childCanBeCreatedConfiguredAndVerified() async throws {
        let api = MockEGuardAPI.empty()
        let model = AppModel.mock(api: api)
        try await model.register(name: "Randy Cruz", email: "flow@example.com", password: "ChangeMe123!")

        let child = try await api.createChild(name: "Mia", age: 12, profile: nil)
        #expect(child.status == .notconfigured)

        let profiles = try await api.profiles(age: 12)
        #expect(profiles.first { $0.recommended }?.id == "PROTECTED")

        let recommendations = try await api.recommendations(childId: child.id, profile: "PROTECTED")
        #expect(recommendations.settings.count == 10)
        let bedtimeLabel = recommendations.settings.first { $0.key == "BEDTIME" }?.label ?? ""
        #expect(bedtimeLabel.hasPrefix("9:30") && bedtimeLabel.contains("6:00"))

        // Without a device everything is saved, not sent.
        let saved = try await api.setup(childId: child.id, profile: "PROTECTED", overrides: [])
        #expect(saved.batchId == nil)
        #expect(saved.saved.count == 10)

        // After pairing an iPhone, a batch runs; WEB is guided and needs the parent's confirmation.
        api.simulatePairing(childId: child.id, platform: .ios)
        let override = JSONValue.object(["key": .string("SCREEN_TIME"), "dailyMinutes": .number(150), "weekendMinutes": .number(200)])
        let response = try await api.setup(childId: child.id, profile: "PROTECTED", overrides: [override])
        let batchId = try #require(response.batchId)
        #expect(response.saved == ["NOTIFICATIONS"])

        var batch = try await api.batch(id: batchId)
        batch = try await api.batch(id: batchId)
        #expect(!batch.done)
        #expect(batch.items.first { $0.key == "WEB" }?.status == .awaitingParent)
        #expect(batch.items.first { $0.key == "SCREEN_TIME" }?.status == .verified)
        #expect(batch.items.first { $0.key == "SCREEN_TIME" }?.to == "2h 30m / day, 3h 20m weekends")

        batch = try await api.confirmBatch(id: batchId)
        batch = try await api.batch(id: batchId)
        #expect(batch.done)
        #expect(batch.items.allSatisfy { $0.status == .verified })

        let health = try await api.health(childId: child.id)
        #expect(health.score == health.total)
        #expect(health.fixCount == 0)
    }

    @Test func batchPollerFinishesWhenTheServerReportsDone() async throws {
        let api = MockEGuardAPI.seeded()
        let children = try await api.children()
        let mia = try #require(children.first)
        let batch = try await api.updateProtection(childId: mia.id, key: "bedtime", config: .object(["enabled": .bool(true), "start": .string("21:00"), "end": .string("06:30"), "days": .string("SCHOOL_NIGHTS")]))
        let poller = BatchPoller()
        poller.start(batchId: batch.batchId, api: api, initial: batch)
        for _ in 0..<40 where poller.phase == .polling {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(poller.phase == .done)
        #expect(poller.batch?.items.first?.status == .verified)
        let protections = try await api.protections(childId: mia.id)
        let label = protections.first { $0.key == "BEDTIME" }?.policyLabel ?? ""
        #expect(label.hasPrefix("9:00") && label.hasSuffix("School nights"))
    }

    @Test func alertsResolveAndAppRulesChange() async throws {
        let api = MockEGuardAPI.seeded()
        let page = try await api.alerts(filter: .apps, childId: nil, includeResolved: false, before: nil)
        #expect(page.alerts.allSatisfy { $0.category == .apps })
        let unreadBefore = try await api.unreadCount()
        _ = try await api.markAllAlertsRead()
        #expect(try await api.unreadCount() < unreadBefore || unreadBefore == 0)

        let mia = try #require(try await api.children().first)
        let pending = try await api.apps(childId: mia.id, filter: .pending)
        let request = try #require(pending.apps.first)
        let updated = try await api.updateApp(id: request.id, patch: AppPatch(approval: .allowed))
        #expect(updated.approval == .allowed)
        let afterwards = try await api.alerts(filter: .apps, childId: mia.id, includeResolved: false, before: nil)
        #expect(afterwards.alerts.allSatisfy { $0.action?.type != "REVIEW_APPS" })

        await #expect(throws: APIError.self) {
            _ = try await api.addApp(childId: mia.id, name: "roblox", approval: .allowed, dailyLimitMinutes: nil)
        }
    }
}

@Suite("Protection config labels")
struct ProtectionConfigTests {
    @Test func labelsMatchServerWording() {
        #expect(ProtectionConfigFormatter.label(key: "SCREEN_TIME", config: .object(["dailyMinutes": .number(180)])) == "3h / day")
        #expect(ProtectionConfigFormatter.label(key: "BEDTIME", config: .object(["enabled": .bool(false)])) == "Off")
        #expect(ProtectionConfigFormatter.label(key: "APP_RESTRICTIONS", config: .object(["maxAgeRating": .number(9)])) == "Apps rated 9+ and under")
        #expect(ProtectionConfigFormatter.label(key: "WEB", config: .object(["mode": .string("FILTER"), "blockedSites": .number(42)])) == "Filtered, 42 sites blocked")
        #expect(ProtectionConfigFormatter.label(key: "DOWNLOADS", config: .object(["requireApproval": .bool(true)])) == "Parent approval")
    }

    @Test func defaultsFollowTheProfileRules() {
        let protected = ProtectionDefaults.config(key: "SCREEN_TIME", age: 12, profile: "PROTECTED")
        let balanced = ProtectionDefaults.config(key: "SCREEN_TIME", age: 12, profile: "BALANCED")
        #expect(balanced["dailyMinutes"]?.intValue == (protected["dailyMinutes"]?.intValue ?? 0) + 60)
        #expect(ProtectionDefaults.config(key: "BEDTIME", age: 12, profile: "BALANCED")["start"]?.stringValue == "22:30")
        #expect(ProtectionDefaults.ratingTier(for: 12, bump: 0) == 9)
        #expect(ProtectionDefaults.ratingTier(for: 12, bump: 1) == 13)
    }

    @Test func jsonValueRoundTripsAndEdits() throws {
        let original = JSONValue.object(["enabled": .bool(true), "start": .string("21:30"), "minutes": .number(90), "nested": .array([.null, .number(1.5)])])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == original)
        #expect(original.setting("enabled", to: .bool(false))["enabled"]?.boolValue == false)
        #expect(original.removing("start")["start"] == nil)
        #expect(String(data: try JSONEncoder().encode(JSONValue.number(90)), encoding: .utf8) == "90")
    }
}

@Suite("Local alerts")
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
    }

    @Test func mergeDropsSameDayDuplicatesAndSortsNewestFirst() {
        let older = ProtectionAlert(category: .protection, title: "Downtime not configured", detail: "x", date: .now.addingTimeInterval(-600), feature: .downtime)
        let duplicate = ProtectionAlert(category: .protection, title: "Downtime not configured", detail: "x", date: .now, feature: .downtime)
        let other = ProtectionAlert(category: .location, title: "Location sharing turned on", detail: "x", date: .now)
        let merged = AlertGenerator.merge([duplicate, other], into: [older])
        #expect(merged.count == 2)
        #expect(merged.first?.title == "Location sharing turned on")
    }

    @Test func preferencesRecordVisits() {
        let model = AppModel.mock()
        model.recordVisit(LocationVisit(name: "Home", latitude: 10.0, longitude: 124.0))
        model.recordVisit(LocationVisit(name: "Home", latitude: 10.0005, longitude: 124.0005))
        #expect(model.preferences.visits.count == 1)
        #expect(model.preferences.lastKnownPlace == "Home")
    }
}
