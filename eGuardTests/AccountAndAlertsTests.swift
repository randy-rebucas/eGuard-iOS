import Foundation
import Testing
@testable import eGuard

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

    @Test func signInFailsWhenTheServerRejectsTheNewSession() async {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api)
        api.nextDashboardError = APIError.server(status: 401, code: "unauthorized", message: "Sign in again to continue.")
        await #expect(throws: APIError.self) {
            try await model.signIn(email: "randy@example.com", password: "ChangeMe123!")
        }
        #expect(!model.isSignedIn)
        #expect(model.dashboard == nil)
        #expect(model.sessionEndedMessage == "Sign in again to continue.")
    }

    @Test func signInKeepsTheSessionWhenTheDashboardFailsForOtherReasons() async throws {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api)
        api.nextDashboardError = APIError.network("Offline.")
        try await model.signIn(email: "randy@example.com", password: "ChangeMe123!")
        #expect(model.isSignedIn)
        #expect(model.dashboard == nil)
        #expect(model.refreshError == "Offline.")
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

    @Test func appleSignInAsksForGuardianConfirmationBeforeCreatingAnAccount() async throws {
        let api = MockEGuardAPI.empty()
        let model = AppModel.mock(api: api, mode: .unset)
        let nonce = AppleNonce()
        do {
            _ = try await model.signInWithApple(identityToken: "eyJhbGciOi.apple-token", fullName: "Randy Cruz", nonce: nonce, guardianConfirmed: false)
            Issue.record("A new sign-up must ask the guardian question first")
        } catch let error as APIError {
            #expect(error.code == "guardian_required")
        }
        #expect(!model.isSignedIn)
        let outcome = try await model.signInWithApple(identityToken: "eyJhbGciOi.apple-token", fullName: "Randy Cruz", nonce: nonce, guardianConfirmed: true)
        #expect(outcome == .signedIn(isNew: true))
        #expect(api.lastSocialNonce == nonce.raw)
        #expect(model.user?.isEmailVerified == true)
        #expect(model.user?.canUsePassword == false)
        #expect(model.mode == .parent)
    }

    @Test func appleNonceIsHashedForAppleAndDroppedForOlderServers() async throws {
        let nonce = AppleNonce()
        #expect(nonce.raw.count == 64)
        #expect(nonce.hashed.count == 64)
        #expect(nonce.hashed != nonce.raw)
        #expect(AppleNonce().raw != nonce.raw)
        #expect(AppleNonce(raw: "abc").hashed == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        let api = MockEGuardAPI.empty()
        api.rejectsNonce = true
        let model = AppModel.mock(api: api, mode: .unset)
        let outcome = try await model.signInWithApple(identityToken: "eyJhbGciOi.apple-token", fullName: "Randy Cruz", nonce: nonce, guardianConfirmed: true)
        #expect(outcome == .signedIn(isNew: true))
        #expect(api.lastSocialNonce == nil)
    }

    @Test func twoStepVerificationGatesSignIn() async throws {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api, signedIn: true)
        let setup = try await api.setupTwoFactor()
        #expect(setup.uri.hasPrefix("otpauth://"))
        let codes = try await api.confirmTwoFactor(code: MockEGuardAPI.authenticatorCode)
        #expect(codes.count == 10)
        await model.signOut()
        #expect(model.mode == .unset)

        guard case .twoFactorRequired(let challenge) = try await model.signIn(email: "randy@example.com", password: "ChangeMe123!") else {
            Issue.record("Expected a two-step challenge")
            return
        }
        #expect(!model.isSignedIn)
        await #expect(throws: APIError.self) {
            _ = try await model.completeTwoFactor(challenge: challenge, code: "000000")
        }
        let response = try await model.completeTwoFactor(challenge: challenge, code: codes[0])
        #expect(response.usedRecoveryCode == true)
        #expect(response.recoveryCodesLeft == 9)
        #expect(model.isSignedIn)
        #expect(model.mode == .parent)
    }

    @Test func forgotPasswordLinkSetsAPasswordAndSignsIn() async throws {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api, mode: .unset)
        let sent = try await api.forgotPassword(email: "RANDY@example.com")
        #expect(sent.message?.isEmpty == false)
        let token = try #require(api.lastLinkToken)
        await #expect(throws: APIError.self) {
            _ = try await model.resetPassword(token: token, password: "short")
        }
        #expect(try await model.resetPassword(token: token, password: "brand-new-password") == .signedIn(isNew: false))
        #expect(model.isSignedIn)
        // The link works once.
        await #expect(throws: APIError.self) {
            _ = try await model.resetPassword(token: token, password: "brand-new-password")
        }
    }

    @Test func invitationsReplaceTemporaryPasswords() async throws {
        let api = MockEGuardAPI.seeded()
        let sent = try await api.inviteMember(name: "Jo Cruz", email: "jo@example.com")
        #expect(sent.pending == true)
        #expect(try await api.family().members.first { $0.id == sent.id }?.isPending == true)
        let token = try #require(api.lastLinkToken)
        let preview = try await api.invitation(token: token)
        #expect(preview.familyName == "Cruz Family")

        let model = AppModel.mock(api: api, mode: .unset)
        try await model.acceptInvitation(token: token, password: "jo-chooses-this-1")
        #expect(model.user?.email == "jo@example.com")
        #expect(model.user?.isAdmin == false)
        #expect(model.user?.isEmailVerified == true)
    }

    @Test func deletionsCarryTheRightConfirmation() throws {
        let encoder = JSONEncoder()
        #expect(String(data: try encoder.encode(DeletionConfirmation.password("pw")), encoding: .utf8) == #"{"password":"pw"}"#)
        #expect(String(data: try encoder.encode(DeletionConfirmation.typedDelete), encoding: .utf8) == #"{"confirm":"DELETE"}"#)

        var user = APIUser(id: "u", name: "Randy", firstName: "Randy", email: "r@e.x", role: .familyAdmin, family: FamilyRef(id: "f", name: "F", timezone: "Asia/Manila"),
                           notifications: NotificationPrefs(notifyPush: true, notifyEmail: true, notifyApproval: true, weeklySummary: true), twoFactor: false, hasPassword: true, emailVerified: true, createdAt: .now)
        #expect(DeletionConfirmation.make(user: user, input: "secret") == .password("secret"))
        #expect(DeletionConfirmation.make(user: user, input: "") == nil)
        user.hasPassword = false
        #expect(DeletionConfirmation.make(user: user, input: "DELETE") == .typedDelete)
        #expect(DeletionConfirmation.make(user: user, input: "delete") == nil)
    }

    @Test func unpairingNeedsTheParentsPassword() async throws {
        let api = MockEGuardAPI.seeded()
        let device = try #require(try await api.devices().devices.first)
        await #expect(throws: APIError.self) {
            try await api.unpairDevice(id: device.id, confirmation: .password("wrong"))
        }
        await #expect(throws: APIError.self) {
            try await api.unpairDevice(id: device.id, confirmation: .typedDelete)
        }
        try await api.unpairDevice(id: device.id, confirmation: .password("ChangeMe123!"))
        #expect(try await api.devices().devices.contains { $0.id == device.id } == false)
        #expect(try await api.alerts(filter: .devices, childId: nil, includeResolved: false, before: nil).alerts.first?.title == "Device removed")
    }

    @Test func deletingTheAdminAccountEndsTheFamilyAndTheMode() async throws {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api, signedIn: true)
        let result = try await model.deleteAccount(confirmation: .password("ChangeMe123!"))
        #expect(result.deleted == "family")
        #expect(!model.isSignedIn)
        #expect(model.mode == .unset)
    }

    @Test func loginResultDecodesBothShapes() throws {
        let decoder = APIClient.makeDecoder()
        let challenge = try decoder.decode(LoginResult.self, from: Data(#"{"twoFactorRequired":true,"challenge":"abc","expiresAt":"2026-10-27T05:59:56.772Z"}"#.utf8))
        guard case .twoFactorRequired(let value) = challenge else { Issue.record("Expected a challenge"); return }
        #expect(value.challenge == "abc")
        let session = try decoder.decode(LoginResult.self, from: Data(#"""
        {"token":"t","expiresAt":"2026-10-27T05:59:56.772Z","user":{"id":"u","name":"Randy Cruz","firstName":"Randy","email":"r@e.x","role":"FAMILY_ADMIN","emailVerified":true,"family":{"id":"f","name":"Cruz Family","timezone":"Asia/Manila"},"notifications":{"notifyPush":true,"notifyEmail":true,"notifyApproval":true,"weeklySummary":true},"hasPassword":false,"twoFactor":false,"createdAt":"2026-09-27T05:56:40.493Z"}}
        """#.utf8))
        #expect(session.auth?.user.canUsePassword == false)
    }

    @Test func unknownServerEnumValuesFallBackInsteadOfFailing() throws {
        let decoder = APIClient.makeDecoder()
        struct Box: Decodable { let status: ChildStatus; let severity: AlertSeverity; let category: APIAlertCategory; let check: CheckStatus }
        let box = try decoder.decode(Box.self, from: Data(#"{"status":"brand_new","severity":"URGENT","category":"BILLING","check":"MAYBE"}"#.utf8))
        #expect(box.status == .attention)
        #expect(box.severity == .info)
        #expect(box.category == .system)
        #expect(box.check == .warning)
    }

    @Test func healthWordingNeverSaysVerifiedWhileADeviceIsOffline() {
        #expect(HealthScore(score: 10, total: 10, offline: 0, verified: true).grade == "Fully protected")
        #expect(HealthScore(score: 10, total: 10, offline: 1, verified: false).grade == "Last known: all set")
        #expect(HealthScore(score: 10, total: 10, offline: 1, verified: false).isVerified == false)
        #expect(HealthScore(score: 0, total: 0).grade == "No devices yet")
        #expect(HealthScore(score: 0, total: 0).text == "–")
        #expect(HealthScore(score: 6, total: 10).grade == "Needs attention")
    }

    @Test func pushAlertsOpenOnlyOnTheParentSide() async throws {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api, signedIn: true)
        let alert = try #require(try await api.alerts(filter: .all, childId: nil, includeResolved: false, before: nil).alerts.first { !$0.read })
        let unreadBefore = try await api.unreadCount()

        #expect(PushAlert(userInfo: ["type": "alert", "alertId": alert.id, "category": "PROTECTION"]) == PushAlert(alertId: alert.id, category: "PROTECTION"))
        #expect(PushAlert(userInfo: ["type": "news", "alertId": alert.id]) == nil)

        model.pendingPushAlert = PushAlert(alertId: alert.id, category: alert.category.rawValue, childId: alert.childId)
        let opened = await model.consumePushAlert()
        #expect(opened?.alertId == alert.id)
        #expect(model.pendingPushAlert == nil)
        #expect(try await api.unreadCount() < unreadBefore)

        // Tokens register only for a signed-in parent, and a rotated token re-registers.
        model.updatePushToken("fcm-token-1")
        model.updatePushToken("fcm-token-1")
        await model.signOut()
        model.pendingPushAlert = PushAlert(alertId: alert.id)
        #expect(await model.consumePushAlert() == nil)
    }

    @Test func deepLinksParseOnlyKnownParentLinks() {
        #expect(DeepLink(url: URL(string: "https://www.eguard.family/verify-email?token=abc")!) == .verifyEmail(token: "abc"))
        #expect(DeepLink(url: URL(string: "https://www.eguard.family/reset-password?token=r1")!) == .resetPassword(token: "r1"))
        #expect(DeepLink(url: URL(string: "eguard://accept-invite?token=i1")!) == .acceptInvite(token: "i1"))
        #expect(DeepLink(url: URL(string: "https://www.eguard.family/privacy")!) == nil)
        #expect(DeepLink(url: URL(string: "https://www.eguard.family/verify-email")!) == nil)
    }
}

@Suite("Plan entitlements and limits")
struct PlanGatingTests {
    @Test func thirtyDayReportsAndLocationFollowThePlan() async throws {
        let api = MockEGuardAPI.seeded()
        let mia = try #require(try await api.children().first)
        _ = try await api.screenTime(childId: mia.id, period: .week)
        do {
            _ = try await api.screenTime(childId: mia.id, period: .month)
            Issue.record("30d needs advanced reports")
        } catch let error as APIError {
            #expect(error.code == "plan_required")
        }
        api.entitlements.advancedReports = true
        #expect(try await api.screenTime(childId: mia.id, period: .month).days.count == 30)

        api.entitlements.locationSharing = false
        await #expect(throws: APIError.self) { _ = try await api.location(childId: mia.id) }
        #expect(try await api.child(id: mia.id).location.locationState == .planRequired)
    }

    @Test func appMonitoringLimitListsRequestsFirst() async throws {
        let api = MockEGuardAPI.seeded()
        let mia = try #require(try await api.children().first)
        api.entitlements.appMonitoringLimit = 3
        let response = try await api.apps(childId: mia.id, filter: nil)
        #expect(response.apps.count == 3)
        #expect(response.limited?.hidden == 5)
        #expect(response.apps.first?.isRequested == true)
        // A blocked app the child asked for again stays blocked but shows Approve/Decline.
        let snapchat = try #require(try await api.apps(childId: mia.id, filter: .pending).apps.first { $0.name == "Snapchat" })
        #expect(snapchat.approval == .blocked && snapchat.isRequested)
        _ = try await api.updateApp(id: snapchat.id, patch: AppPatch(approval: .blocked))
        #expect(try await api.apps(childId: mia.id, filter: .pending).apps.contains { $0.name == "Snapchat" } == false)
    }

    @Test func familyAndSubscriptionShareEntitlements() async throws {
        let api = MockEGuardAPI.seeded()
        let family = try await api.family()
        #expect(family.plan == "eGuard Plus")
        #expect(family.slotsUsed == family.deviceCount + 1)
        let subscription = try await api.subscription()
        #expect(subscription.planId == "PLUS")
        #expect(subscription.entitlements == family.entitlements)
        #expect(subscription.usage.childLimit == 5)
        #expect(!subscription.isSponsored)
        #expect(subscription.upgrade == nil)
    }

    @Test func organizationsJoinAndLeaveWithACode() async throws {
        let api = MockEGuardAPI.seeded()
        #expect(try await api.organizations().organizations.count == 1)
        let preview = try await api.previewOrganization(code: "cmty-4kid")
        #expect(preview.name == "Leyte Parents Circle" && !preview.alreadyJoined)
        let joined = try await api.joinOrganization(code: "CMTY4KID")
        #expect(joined.organizations?.count == 2)
        await #expect(throws: APIError.self) { _ = try await api.previewOrganization(code: "NOPE0000") }
        _ = try await api.leaveOrganization(id: "org_2")
        #expect(try await api.organizations().organizations.count == 1)
    }

    @Test func browserRequestsResolveAndAlwaysUpdatesThePolicy() async throws {
        let api = MockEGuardAPI.seeded()
        let sophie = try #require(try await api.children().first { $0.name == "Sophie" })
        let requests = try await api.browserAccessRequests(childId: sophie.id)
        let request = try #require(requests.pending.first)
        let before = try await api.browserPolicy(childId: sophie.id)
        let decided = try await api.decideBrowserAccessRequest(id: request.id, decision: .approve(.always))
        #expect(decided.status == "APPROVED")
        let after = try await api.browserPolicy(childId: sophie.id)
        #expect(after.allowedDomains.contains("discord.com"))
        #expect(after.version == before.version + 1)
        await #expect(throws: APIError.self) {
            _ = try await api.decideBrowserAccessRequest(id: request.id, decision: .deny)
        }
        // A stale save is refused instead of undoing the newer change.
        await #expect(throws: APIError.self) {
            _ = try await api.updateBrowserPolicy(childId: sophie.id, policy: before.update)
        }
        #expect(try await api.browsers().count == 1)
        try await api.removeBrowser(id: try #require(try await api.browsers().first?.id), confirmation: .password("ChangeMe123!"))
        #expect(try await api.browsers().isEmpty)
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
