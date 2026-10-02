import Foundation
import Observation

/// Which side of eGuard this install runs: nobody has chosen yet, a parent's phone, or a child's device.
/// The app never holds a parent token and a device token together; switching deletes the old one first.
nonisolated enum AppMode: String, Codable, Sendable {
    case unset = "UNSET"
    case parent = "PARENT"
    case child = "CHILD"
}

/// Persists `AppMode` in secure storage so launch can route on it before any network call.
@Observable
final class ModeStore {
    private static let key = "appMode"
    private let store: CodableStore

    private(set) var mode: AppMode

    init(store: CodableStore, initial: AppMode? = nil) {
        self.store = store
        if let initial {
            mode = initial
            try? store.save(initial, forKey: Self.key)
        } else {
            mode = (try? store.load(AppMode.self, forKey: Self.key)) ?? .unset
        }
    }

    static func live() -> ModeStore {
        ModeStore(store: KeychainStore())
    }

    static func inMemory(_ mode: AppMode = .unset) -> ModeStore {
        ModeStore(store: InMemoryStore(), initial: mode)
    }

    func set(_ mode: AppMode) {
        self.mode = mode
        try? store.save(mode, forKey: Self.key)
    }
}

/// Links eGuard emails open: verification, password reset, and invitations. Parents handle them;
/// in child device mode the app shows a notice instead.
nonisolated enum DeepLink: Hashable, Sendable {
    case verifyEmail(token: String)
    case resetPassword(token: String)
    case acceptInvite(token: String)

    /// Parses `https://www.eguard.family/verify-email?token=…` and the `eguard://` equivalents.
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = components.path.split(separator: "/").last.map(String.init) ?? components.host ?? ""
        guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty else { return nil }
        switch path {
        case "verify-email": self = .verifyEmail(token: token)
        case "reset-password": self = .resetPassword(token: token)
        case "accept-invite": self = .acceptInvite(token: token)
        default: return nil
        }
    }
}
