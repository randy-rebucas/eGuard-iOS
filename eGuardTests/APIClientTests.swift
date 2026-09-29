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
        let client = APIClient(baseURL: URL(string: "https://example.test/api/mobile/v1")!, sessionStore: store, urlSession: URLSession(configuration: configuration))
        return (client, store)
    }

    @Test func sendsBearerAndClientHeaders() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in (200, Data(#"{"unread": 4}"#.utf8)) }
        let count = try await client.send(.get("alerts/unread-count"), as: UnreadCount.self).unread
        #expect(count == 4)
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(request.value(forHTTPHeaderField: "X-eGuard-Client") == "ios")
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

    @Test func expiredSessionsAreDroppedOnLoad() {
        let store = InMemoryStore()
        try? store.save(APISession(token: "old", expiresAt: Date.now.addingTimeInterval(-60)), forKey: "apiSession")
        #expect(SessionStore(store: store).session == nil)
    }
}
