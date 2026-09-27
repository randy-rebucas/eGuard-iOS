import Foundation
import Observation

/// A signed-in server session. Lives in the Keychain; the token lasts 30 days.
nonisolated struct APISession: Codable, Equatable, Sendable {
    let token: String
    let expiresAt: Date

    var isExpired: Bool { expiresAt <= .now }
}

/// Holds the current API session and persists it securely.
@Observable
final class SessionStore {
    private static let key = "apiSession"
    private let store: CodableStore

    private(set) var session: APISession?

    init(store: CodableStore) {
        self.store = store
        session = try? store.load(APISession.self, forKey: Self.key)
        if session?.isExpired == true {
            session = nil
            try? store.remove(forKey: Self.key)
        }
    }

    static func live() -> SessionStore {
        SessionStore(store: KeychainStore())
    }

    static func inMemory() -> SessionStore {
        SessionStore(store: InMemoryStore())
    }

    var token: String? { session?.token }

    func save(_ session: APISession) {
        self.session = session
        try? store.save(session, forKey: Self.key)
    }

    func clear() {
        session = nil
        try? store.remove(forKey: Self.key)
    }
}
