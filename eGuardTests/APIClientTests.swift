import Foundation
import Testing
@testable import eGuard

/// Serves canned responses so the client can be tested without a network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let (status, data) = Self.handler?(request) ?? (200, Data("{}".utf8))
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("API client", .serialized)
struct APIClientTests {
    private func makeClient(signedIn: Bool = true) -> (APIClient, SessionStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let store = SessionStore.inMemory()
        if signedIn { store.save(APISession(token: "abc123", expiresAt: Date.now.addingTimeInterval(3600))) }
        let client = APIClient(baseURL: URL(string: "https://example.test/api/mobile/v1")!, sessionStore: store, installID: "install-0123456789", urlSession: URLSession(configuration: configuration))
        return (client, store)
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        // URLProtocol sees the body as a stream
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func createAccountTakesTwoStepsAndSendsTheInstallID() async throws {
        let (client, _) = makeClient(signedIn: false)
        let api = LiveEGuardAPI(client: client)

        // Step 1: 202, a ticket and no token
        StubURLProtocol.handler = { _ in (202, Data(#"{"verificationRequired":true,"signup":"sgn_0123456789abcdefghij","email":"new@example.com","expiresAt":"2026-10-15T12:30:00.000Z"}"#.utf8)) }
        let signup = try await api.register(name: "Randy Cruz", email: "New@Example.com", password: "ChangeMe123!", familyName: nil)
        var request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.path == "/api/mobile/v1/auth/register")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "X-eGuard-Install") == "install-0123456789")
        #expect(try body(of: request)["guardian"] as? Bool == true)
        #expect(signup.signup == "sgn_0123456789abcdefghij")
        #expect(signup.email == "new@example.com")
        #expect(signup.verificationRequired == true)

        // Step 2: 201 with a session, like sign-in
        StubURLProtocol.handler = { _ in
            (201, Data(#"{"token":"tok","expiresAt":"2026-11-14T12:00:00.000Z","user":{"id":"u1","name":"Randy Cruz","firstName":"Randy","email":"new@example.com","role":"FAMILY_ADMIN","family":{"id":"f1","name":"Cruz Family","timezone":"Asia/Manila"},"notifications":{"notifyPush":true,"notifyEmail":true,"notifyApproval":true,"weeklySummary":true},"twoFactor":false,"hasPassword":true,"emailVerified":true,"createdAt":"2026-10-15T12:15:00.000Z"}}"#.utf8))
        }
        let session = try await api.verifySignup(signup: signup.signup, code: "246810")
        request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.path == "/api/mobile/v1/auth/register/verify")
        #expect(request.value(forHTTPHeaderField: "X-eGuard-Install") == "install-0123456789")
        let sent = try body(of: request)
        #expect(sent["signup"] as? String == signup.signup)
        #expect(sent["code"] as? String == "246810")
        #expect(session.token == "tok")
        #expect(session.user.isEmailVerified)

        // Send a new code
        StubURLProtocol.handler = { _ in (200, Data(#"{"ok":true,"email":"new@example.com","expiresAt":"2026-10-15T12:45:00.000Z"}"#.utf8)) }
        let resent = try await api.resendSignupCode(signup: signup.signup)
        request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.path == "/api/mobile/v1/auth/register/resend")
        #expect(try body(of: request)["signup"] as? String == signup.signup)
        #expect(resent.expiresAt > signup.expiresAt)

        // The code step's errors keep their codes
        StubURLProtocol.handler = { _ in (400, Data(#"{"error":"This sign-up has expired. Fill in the form again to get a new code.","code":"signup_expired"}"#.utf8)) }
        await #expect(throws: APIError.server(status: 400, code: "signup_expired", message: "This sign-up has expired. Fill in the form again to get a new code.")) {
            _ = try await api.verifySignup(signup: signup.signup, code: "000000")
        }
    }

    @Test func sendsBearerAndClientHeaders() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in (200, Data(#"{"unread": 4}"#.utf8)) }
        let count = try await client.send(.get("alerts/unread-count"), as: UnreadCount.self).unread
        #expect(count == 4)
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(request.value(forHTTPHeaderField: "X-eGuard-Client") == "ios")
        #expect(request.value(forHTTPHeaderField: "X-eGuard-Install") == "install-0123456789")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("eGuard/") == true)
        #expect(request.url?.path == "/api/mobile/v1/alerts/unread-count")
    }

    @Test func publicEndpointsSkipTheToken() async throws {
        let (client, _) = makeClient(signedIn: false)
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"name":"eGuard","apiVersion":"1","minimumAppVersion":"1.0.0","signIn":{"password":true,"apple":false,"google":false},"supportEmail":"s@e.x"}"#.utf8))
        }
        let info = try await client.send(.get("app-info", requiresAuth: false), as: AppInfo.self)
        #expect(info.signIn.apple == false)
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func serverErrorsKeepTheParentFriendlyMessage() async {
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in (400, Data(#"{"error":"email: Enter a valid email address.","code":"invalid"}"#.utf8)) }
        do {
            _ = try await client.send(.get("me"), as: APIUser.self)
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.status == 400)
            #expect(error.code == "invalid")
            #expect(error.fieldName == "email")
            #expect(error.localizedDescription == "email: Enter a valid email address.")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func unauthorizedClearsTheSessionThroughTheCallback() async {
        let (client, store) = makeClient()
        var reason: String?
        client.onUnauthorized = { error in reason = error.localizedDescription; store.clear() }
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":"Your session has ended.","code":"invalid_token"}"#.utf8)) }
        _ = try? await client.send(.get("dashboard"), as: Dashboard.self)
        #expect(reason == "Your session has ended.")
        #expect(store.session == nil)
    }

    @Test func planLimitMessagesNeverInviteAnUpgrade() async {
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in (409, Data(#"{"error":"Free covers 1 child. Upgrade to eGuard Plus to add up to 5.","code":"plan_limit"}"#.utf8)) }
        do {
            _ = try await client.send(.json(.post, "children", body: ["name": "Mia"]), as: ChildSummary.self)
            Issue.record("Expected a 409")
        } catch let error as APIError {
            #expect(error.status == 409)
            #expect(error.localizedDescription == APIClient.planLimitMessage)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        #expect(APIClient.storeSafeMessage("That email is already in use.", status: 409) == "That email is already in use.")
        // 403 plan_required names a plan to buy ("included with eGuard Plus"): neutral on iOS
        #expect(APIClient.storeSafeMessage("Push alerts are included with eGuard Plus.", status: 403, code: "plan_required") == APIClient.planFeatureMessage)
        #expect(APIClient.storeSafeMessage("30-day reports are included with Family Pro.", status: 403, code: "plan_required") == APIClient.planFeatureMessage)
        #expect(APIClient.storeSafeMessage("Only the family admin can do that.", status: 403, code: "forbidden") == "Only the family admin can do that.")
    }

    @Test func planRequiredMessagesNeverInviteAnUpgradeEither() async {
        // 403 plan_required is the other place the server could mention a plan by name or price.
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in (403, Data(#"{"error":"Location sharing is included with eGuard Plus (₱149/month).","code":"plan_required"}"#.utf8)) }
        do {
            _ = try await client.send(.get("locations"), as: FamilyLocations.self)
            Issue.record("Expected a 403")
        } catch let error as APIError {
            #expect(error.status == 403)
            #expect(error.code == "plan_required")
            #expect(error.localizedDescription == APIClient.planFeatureMessage)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        // Other 403s keep their wording: only selling language is replaced.
        #expect(APIClient.storeSafeMessage("Verify your email before pairing a device.", status: 403) == "Verify your email before pairing a device.")
        #expect(APIClient.storeSafeMessage("Saved places aren't included in your plan.", status: 403) == "Saved places aren't included in your plan.")
    }

    @Test func missingTokenFailsBeforeTheNetwork() async {
        let (client, _) = makeClient(signedIn: false)
        await #expect(throws: APIError.notSignedIn) {
            _ = try await client.send(.get("me"), as: APIUser.self)
        }
    }

    @Test func decodesIsoDatesWithAndWithoutFractions() throws {
        let decoder = APIClient.makeDecoder()
        struct Box: Decodable { let a: Date; let b: Date }
        let box = try decoder.decode(Box.self, from: Data(#"{"a":"2026-09-27T05:28:40.136Z","b":"2026-10-11T16:00:00Z"}"#.utf8))
        #expect(box.a < box.b)
    }

    @Test func decodesParentSetWhereTheServerSendsIt() throws {
        let decoder = APIClient.makeDecoder()
        // GET /health: `parentSet` is optional; true reads "Set by you", not "Not supported"
        let checks = try decoder.decode([HealthCheck].self, from: Data(#"[{"key":"CONTENT","name":"Content","status":"UNSUPPORTED","detail":"Set by you","parentSet":true},{"key":"NOTIFICATIONS","name":"Notifications","status":"UNSUPPORTED"}]"#.utf8))
        #expect(checks[0].isParentSet)
        #expect(checks[0].displayStatus == .setByYou)
        #expect(checks[0].displayStatus.title == "Set by you")
        #expect(!checks[0].displayStatus.isEvaluated)
        #expect(!checks[1].isParentSet)
        #expect(checks[1].displayStatus.title == "Not supported")

        // Batch items: a VERIFIED PARENT_SET step is the parent's word, never "Verified"
        let device = try decoder.decode(BatchDevice.self, from: Data(#"{"requestId":"r1","deviceId":"d1","deviceName":"Galaxy","platform":"ANDROID","mode":"GUIDED","status":"VERIFIED","failureReason":null,"offline":false,"parentSet":true,"from":"Not set up yet","guide":["Open the Play Store"]}"#.utf8))
        #expect(device.isGuided)
        #expect(device.statusTitle == "Set by you, not verified")
        let older = try decoder.decode(BatchDevice.self, from: Data(#"{"requestId":"r2","deviceId":"d2","deviceName":"iPad","platform":"IOS","mode":"APPLY","status":"VERIFIED","offline":false}"#.utf8))
        #expect(!older.isParentSet)
        #expect(older.statusTitle == "Verified")
        let item = BatchItem(key: "CONTENT", name: "Content", icon: nil, status: .verified, to: "Rated 13+ and under", devices: [device])
        #expect(item.isParentSetOnly)
        #expect(item.statusTitle == "Set by you, not verified")

        // The PARENT_SET capability: guided everywhere, "Set by you" once confirmed, "Not set up yet" before
        let capabilities = try decoder.decode([Capability].self, from: Data(#"["PARENT_SET","GUIDED","SOMETHING_NEW"]"#.utf8))
        #expect(capabilities == [.parentSet, .guided, .verifyOnly])
        #expect(Capability.parentSet.isGuided)
        #expect(Capability.parentSet.statusTitle(.unsupported) == "Set by you")
        #expect(Capability.parentSet.statusTitle(.notConfigured) == "Not set up yet")
        #expect(Capability.parentSet.healthStatus(.unsupported) == .setByYou)
        #expect(Capability.unsupported.statusTitle(.unsupported) == "Not supported")
        #expect(!Capability.available.isGuided)
    }

    @Test func expiredSessionsAreDroppedOnLoad() {
        let store = InMemoryStore()
        try? store.save(APISession(token: "old", expiresAt: Date.now.addingTimeInterval(-60)), forKey: "apiSession")
        #expect(SessionStore(store: store).session == nil)
    }

    @Test func confirmingOneProtectionSendsItsKey() async throws {
        let (client, _) = makeClient()
        let api = LiveEGuardAPI(client: client)
        let batchJSON = #"{"batchId":"b1","childId":"c1","done":false,"summary":{"total":2,"verified":1,"setByYou":1,"failed":0,"awaitingParent":1,"inProgress":0,"cancelled":0},"items":[],"health":{"score":1,"total":2},"confirmed":1}"#
        StubURLProtocol.handler = { _ in (200, Data(batchJSON.utf8)) }

        // One protection's guided steps: `?key=` so the batch's other guided steps aren't confirmed with it
        let batch = try await api.confirmBatch(id: "b1", key: "LOCATION")
        var request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/mobile/v1/batches/b1/confirm")
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items == [URLQueryItem(name: "key", value: "LOCATION")])
        #expect(batch.confirmed == 1)

        // No key: the whole batch, and no query at all
        _ = try await api.confirmBatch(id: "b1", key: nil)
        request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.path == "/api/mobile/v1/batches/b1/confirm")
        #expect(request.url?.query == nil)
    }

    @Test func batchSummarySaysDoneAndCountsSetByYou() throws {
        let decoder = APIClient.makeDecoder()
        let withSetByYou = try decoder.decode(BatchSummary.self, from: Data(#"{"total":10,"verified":3,"setByYou":2,"failed":0,"awaitingParent":1,"inProgress":6,"cancelled":0}"#.utf8))
        #expect(withSetByYou.setByYouCount == 2)
        #expect(withSetByYou.progressText == "3 of 10 done · 2 set by you")
        let none = try decoder.decode(BatchSummary.self, from: Data(#"{"total":4,"verified":4,"setByYou":0,"failed":0,"awaitingParent":0,"inProgress":0,"cancelled":0}"#.utf8))
        #expect(none.progressText == "4 of 4 done")
        // Older servers leave it out
        let older = try decoder.decode(BatchSummary.self, from: Data(#"{"total":2,"verified":1,"failed":0,"awaitingParent":0,"inProgress":1,"cancelled":0}"#.utf8))
        #expect(older.setByYouCount == 0)
        #expect(older.progressText == "1 of 2 done")
    }

    @Test func decodesTheLocationNote() throws {
        let decoder = APIClient.makeDecoder()
        let note = "iPhone shares its location while eGuard is open on it, so this updates when your child opens eGuard."
        let response = try decoder.decode(LocationResponse.self, from: Data(#"{"childId":"c1","sharing":true,"state":"waiting","note":"\#(note)","current":null,"devices":[],"history":{"enabled":true,"visits":[]}}"#.utf8))
        #expect(response.note == note)
        let without = try decoder.decode(LocationResponse.self, from: Data(#"{"childId":"c1","sharing":true,"current":null,"devices":[],"history":{"enabled":true,"visits":[]}}"#.utf8))
        #expect(without.note == nil)
        let family = try decoder.decode(FamilyLocations.self, from: Data(#"{"children":[{"childId":"c1","name":"Mia","hue":200,"sharing":true,"state":"waiting","location":null,"note":"\#(note)"},{"childId":"c2","name":"Lucas","hue":20,"sharing":false,"state":"sharing_off"}]}"#.utf8))
        #expect(family.children[0].note == note)
        #expect(family.children[1].note == nil)
    }

    @Test func mapsTheUserAlertIcons() {
        // Devices alerts "Switched to another user" / "Used on another user"
        #expect(LucideIcon.symbol(for: "users") == "person.2.fill")
        #expect(LucideIcon.symbol(for: "user-check") == "person.crop.circle.badge.checkmark")
        #expect(LucideIcon.symbol(for: "user") == "person.fill")
    }
}

/// The Keychain outlives an uninstall; the first launch of an install clears what it kept.
@Suite("Fresh install reset")
struct FreshInstallResetTests {
    private func makeDefaults() -> UserDefaults {
        let name = "FreshInstallResetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A Keychain that can't be read, as before the first unlock after a restart.
    private final class LockedStore: CodableStore {
        var removed = false
        func load<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? { throw KeychainError.unhandled(-25308) }
        func save<T: Encodable>(_ value: T, forKey key: String) throws {}
        func remove(forKey key: String) throws { removed = true }
        func removeAll() throws { removed = true }
    }

    @Test func firstLaunchClearsTheStoredSessionOnce() throws {
        let defaults = makeDefaults()
        let store = InMemoryStore()
        try store.save(APISession(token: "previous-install", expiresAt: Date.now.addingTimeInterval(3600)), forKey: "apiSession")
        try store.save(AppMode.parent, forKey: "appMode")

        #expect(FreshInstallReset.run(defaults: defaults, secureStore: store))
        #expect(SessionStore(store: store).session == nil)
        #expect(try store.load(AppMode.self, forKey: "appMode") == nil)
        #expect(defaults.bool(forKey: FreshInstallReset.flagKey))

        // Later launches keep a new sign-in
        let session = APISession(token: "this-install", expiresAt: Date.now.addingTimeInterval(3600))
        SessionStore(store: store).save(session)
        #expect(!FreshInstallReset.run(defaults: defaults, secureStore: store))
        #expect(SessionStore(store: store).session == session)
    }

    @Test func anUpdateFromAVersionWithoutTheFlagKeepsTheSession() throws {
        let defaults = makeDefaults()
        let store = InMemoryStore()
        let session = APISession(token: "kept", expiresAt: Date.now.addingTimeInterval(3600))
        try store.save(session, forKey: "apiSession")
        #expect(!FreshInstallReset.run(defaults: defaults, secureStore: store, hasExistingData: true))
        #expect(SessionStore(store: store).session == session)
        #expect(defaults.bool(forKey: FreshInstallReset.flagKey))
    }

    @Test func aLockedKeychainIsLeftForALaterLaunch() {
        let defaults = makeDefaults()
        let store = LockedStore()
        #expect(!FreshInstallReset.run(defaults: defaults, secureStore: store))
        #expect(!store.removed)
        #expect(!defaults.bool(forKey: FreshInstallReset.flagKey))
    }
}

/// `X-eGuard-Install`: one id per install, kept in the Keychain, new after a reinstall.
@Suite("Install id")
struct InstallIDTests {
    private func makeDefaults() -> UserDefaults {
        let name = "InstallIDTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theIdIsMadeOnceAndKept() throws {
        let defaults = makeDefaults()
        let store = InMemoryStore()
        let id = InstallID.load(defaults: defaults, secureStore: store)
        #expect(InstallID.isValid(id))
        #expect(InstallID.load(defaults: defaults, secureStore: store) == id)
        #expect(try store.load(String.self, forKey: InstallID.storeKey) == id)
    }

    @Test func aReinstallGetsANewIdThoughTheKeychainKeptTheOldOne() throws {
        let store = InMemoryStore()
        let old = InstallID.load(defaults: makeDefaults(), secureStore: store)
        // UserDefaults goes with the app; the Keychain item doesn't
        let id = InstallID.load(defaults: makeDefaults(), secureStore: store)
        #expect(id != old)
        #expect(try store.load(String.self, forKey: InstallID.storeKey) == id)
    }

    @Test func onlyWhatTheServerAcceptsIsValid() {
        #expect(InstallID.isValid(UUID().uuidString))
        #expect(InstallID.isValid("abc_DEF-12"))
        #expect(!InstallID.isValid("short"))
        #expect(!InstallID.isValid(String(repeating: "a", count: 65)))
        #expect(!InstallID.isValid("has space1"))
        #expect(!InstallID.isValid("ünicode-id"))
    }
}

@Suite("Mock server location")
struct MockLocationNoteTests {
    @Test func theMockSendsTheLocationNoteForIPhonesOnly() async throws {
        let api = MockEGuardAPI.seeded()
        let children = try await api.children()
        let mia = try #require(children.first { $0.name == "Mia" })
        let lucas = try #require(children.first { $0.name == "Lucas" })
        #expect(try await api.location(childId: mia.id).note == MockEGuardAPI.iPhoneLocationNote)
        #expect(try await api.location(childId: lucas.id).note == nil)
        let family = try await api.familyLocations()
        #expect(family.children.first { $0.childId == mia.id }?.note == MockEGuardAPI.iPhoneLocationNote)
        #expect(family.children.first { $0.childId == lucas.id }?.note == nil)
    }
}
