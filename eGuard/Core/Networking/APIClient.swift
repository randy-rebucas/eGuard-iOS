import Foundation
import OSLog
import UIKit

/// One HTTP call to the eGuard API.
nonisolated struct APIRequest: Sendable {
    enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    var method: Method
    var path: String
    var query: [URLQueryItem] = []
    var body: Data? = nil
    var contentType: String? = nil
    var requiresAuth = true

    static func get(_ path: String, query: [URLQueryItem] = [], requiresAuth: Bool = true) -> APIRequest {
        APIRequest(method: .get, path: path, query: query, requiresAuth: requiresAuth)
    }

    /// Builds a request with a JSON body. `nil` values are dropped so PATCH bodies only carry the fields to change.
    static func json<Body: Encodable>(
        _ method: Method,
        _ path: String,
        body: Body,
        query: [URLQueryItem] = [],
        requiresAuth: Bool = true
    ) -> APIRequest {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return APIRequest(
            method: method,
            path: path,
            query: query,
            body: try? encoder.encode(body),
            contentType: "application/json",
            requiresAuth: requiresAuth
        )
    }

    static func empty(_ method: Method, _ path: String, query: [URLQueryItem] = []) -> APIRequest {
        APIRequest(method: method, path: path, query: query)
    }
}

/// Sends requests to the eGuard API with the bearer token, client headers, and shared error handling.
final class APIClient {
    static let defaultBaseURL = URL(string: "https://e-guard-web.vercel.app/api/mobile/v1")!

    let baseURL: URL
    private let sessionStore: SessionStore
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    /// Called on any 401 so the app can sign out locally.
    var onUnauthorized: (() -> Void)?

    init(baseURL: URL = APIClient.defaultBaseURL, sessionStore: SessionStore, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.sessionStore = sessionStore
        self.urlSession = urlSession
        decoder = APIClient.makeDecoder()
    }

    /// Decodes ISO-8601 timestamps with or without fractional seconds.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractional.date(from: raw) ?? ISO8601DateFormatter.plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date \(raw)")
        }
        return decoder
    }

    /// A readable User-Agent, shown to the parent in the sessions list.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let device = UIDevice.current
        return "eGuard/\(version) (\(device.model); iOS \(device.systemVersion))"
    }

    // MARK: Sending

    func send<Response: Decodable>(_ request: APIRequest, as type: Response.Type) async throws -> Response {
        let data = try await sendData(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            EGuardLog.app.error("Decoding \(request.path) failed: \(String(describing: error))")
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends and ignores the body, for endpoints that only return `{ ok: true }`.
    func send(_ request: APIRequest) async throws {
        _ = try await sendData(request)
    }

    /// Sends and returns the raw body, for images.
    func sendData(_ request: APIRequest) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)!
        if !request.query.isEmpty {
            components.queryItems = request.query
        }
        guard let url = components.url else { throw APIError.network("Invalid request.") }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.setValue("ios", forHTTPHeaderField: "X-eGuard-Client")
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType = request.contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if request.requiresAuth {
            guard let token = sessionStore.token else { throw APIError.notSignedIn }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw APIError.network(Self.networkMessage(for: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("eGuard received an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            let error = APIError.server(
                status: http.statusCode,
                code: body?.code ?? Self.defaultCode(for: http.statusCode),
                message: body?.error ?? Self.defaultMessage(for: http.statusCode)
            )
            if error.isUnauthorized, request.requiresAuth {
                onUnauthorized?()
            }
            throw error
        }
        return data
    }

    // MARK: Helpers

    private static func networkMessage(for error: Error) -> String {
        let urlError = error as? URLError
        switch urlError?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "You're offline. Connect to the internet and try again."
        case .timedOut:
            return "The eGuard server took too long to respond. Please try again."
        default:
            return "eGuard couldn't reach its server. Please try again."
        }
    }

    private static func defaultCode(for status: Int) -> String {
        switch status {
        case 401: "unauthorized"
        case 403: "forbidden"
        case 404: "not_found"
        case 409: "conflict"
        case 429: "rate_limited"
        default: "server_error"
        }
    }

    private static func defaultMessage(for status: Int) -> String {
        switch status {
        case 401: "Your session has ended. Please sign in again."
        case 403: "You don't have permission to do that."
        case 404: "That item couldn't be found."
        case 429: "Too many attempts. Please wait a few minutes and try again."
        default: "Something went wrong on the eGuard server. Please try again."
        }
    }
}

nonisolated extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
