import Foundation

/// The error shape every eGuard API response uses: `{ "error": "...", "code": "..." }`.
nonisolated struct APIErrorBody: Codable, Sendable {
    let error: String
    let code: String?
}

/// Failures surfaced by the API client. `errorDescription` is always safe to show to the parent.
nonisolated enum APIError: LocalizedError, Equatable, Sendable {
    /// The server answered with an error status and a parent-friendly message.
    case server(status: Int, code: String, message: String)
    /// The request never completed.
    case network(String)
    /// The response could not be decoded.
    case decoding(String)
    /// No session token is stored, but the endpoint needs one.
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .server(_, _, let message): message
        case .network(let message): message
        case .decoding: "eGuard received an unexpected response. Please try again."
        case .notSignedIn: "Sign in to continue."
        }
    }

    var status: Int? {
        if case .server(let status, _, _) = self { return status }
        return nil
    }

    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }

    /// Any 401 means the session is gone and the app must sign out locally.
    var isUnauthorized: Bool { status == 401 }

    /// The field named at the start of a 400 message, e.g. "email" in "email: Enter a valid email address."
    var fieldName: String? {
        guard status == 400, case .server(_, _, let message) = self,
              let colon = message.firstIndex(of: ":") else { return nil }
        let field = message[..<colon]
        return field.contains(" ") ? nil : String(field)
    }
}
