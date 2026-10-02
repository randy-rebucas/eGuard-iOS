import Foundation
import Observation
import OSLog
import UIKit

/// Holds the device token from `POST /pair`. The token is returned once and can't be recovered,
/// so it goes straight into the Keychain.
@Observable
final class DeviceTokenStore {
    private static let key = "deviceSession"
    private let store: CodableStore

    private(set) var session: DeviceSession?

    init(store: CodableStore) {
        self.store = store
        session = try? store.load(DeviceSession.self, forKey: Self.key)
    }

    static func live() -> DeviceTokenStore { DeviceTokenStore(store: KeychainStore()) }
    static func inMemory() -> DeviceTokenStore { DeviceTokenStore(store: InMemoryStore()) }

    var token: String? { session?.token }

    func save(_ session: DeviceSession) {
        self.session = session
        try? store.save(session, forKey: Self.key)
    }

    func clear() {
        session = nil
        try? store.remove(forKey: Self.key)
    }
}

/// Failures from the child device API. Unlike the parent API there is no `code`: branch on the status.
nonisolated enum DeviceAPIError: LocalizedError, Equatable, Sendable {
    case server(status: Int, message: String)
    case network(String)
    case decoding
    case notPaired

    var errorDescription: String? {
        switch self {
        case .server(_, let message): message
        case .network(let message): message
        case .decoding: "eGuard received an unexpected response. It will try again later."
        case .notPaired: "This device isn't paired with eGuard yet."
        }
    }

    var status: Int? {
        if case .server(let status, _) = self { return status }
        return nil
    }

    /// Any 401 means a parent removed the device: stop enforcing and show the removed screen.
    var isUnauthorized: Bool { status == 401 }

    /// 5xx, 429 and network failures are retried with backoff; 400s are bugs and are dropped.
    var isRetryable: Bool {
        switch self {
        case .network: true
        case .server(let status, _): status == 429 || status >= 500
        case .decoding, .notPaired: false
        }
    }
}

/// The device API's error shape: `{ "error": "…" }`, with no `code`.
nonisolated struct DeviceErrorBody: Decodable, Sendable {
    let error: String?
}

/// Sends requests to `/api/device/v1` with the device token. No `X-eGuard-Client` header: the
/// device API carries its facts in request bodies.
final class DeviceAPIClient {
    static let defaultBaseURL = URL(string: "https://www.eguard.family/api/device/v1")!

    let baseURL: URL
    private let tokenStore: DeviceTokenStore
    private let urlSession: URLSession
    private let decoder = APIClient.makeDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Called on any 401 so the app can treat the device as removed.
    var onUnauthorized: (() -> Void)?

    init(baseURL: URL = DeviceAPIClient.defaultBaseURL, tokenStore: DeviceTokenStore, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.urlSession = urlSession
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, requiresAuth: Bool = true, as type: Response.Type) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? encoder.encode(body)
        if requiresAuth {
            guard let token = tokenStore.token else { throw DeviceAPIError.notPaired }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw DeviceAPIError.network(Self.networkMessage(for: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw DeviceAPIError.network("eGuard received an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(DeviceErrorBody.self, from: data))?.error ?? Self.defaultMessage(for: http.statusCode)
            let error = DeviceAPIError.server(status: http.statusCode, message: message)
            if error.isUnauthorized, requiresAuth {
                EGuardLog.app.error("Device API 401 on \(path): the device was removed.")
                onUnauthorized?()
            }
            throw error
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            EGuardLog.app.error("Decoding device API \(path) failed: \(String(describing: error))")
            throw DeviceAPIError.decoding
        }
    }

    private static func networkMessage(for error: Error) -> String {
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            "You're offline. Protections keep working from the saved settings."
        case .timedOut:
            "The eGuard server took too long to respond."
        default:
            "eGuard couldn't reach its server."
        }
    }

    private static func defaultMessage(for status: Int) -> String {
        switch status {
        case 400: "Something in the request wasn't right."
        case 401: "This device was removed from eGuard."
        case 409: "Device limit reached for this plan."
        case 429: "Too many attempts. Wait a few minutes and try again."
        default: "Something went wrong on the eGuard server."
        }
    }
}

/// Facts about this phone or tablet, sent with `/pair`, `/sync` and `/report`.
enum DeviceFacts {
    static var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingCString: $0) }
        }
        return identifier?.isEmpty == false ? identifier! : UIDevice.current.model
    }

    static var osVersion: String { "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)" }
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var kind: String { UIDevice.current.userInterfaceIdiom == .pad ? "TABLET" : "PHONE" }
    static var defaultName: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    static var battery: Int? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Int((level * 100).rounded())
    }

    static var status: DeviceStatus {
        DeviceStatus(battery: battery, osVersion: osVersion, appVersion: appVersion)
    }
}
