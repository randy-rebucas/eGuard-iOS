import Foundation
import Observation
import OSLog

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

/// The `X-eGuard-Install` id: random, made once per install, kept in the Keychain. Signing in from an install the
/// parent hasn't used before emails them "New sign-in". Keychain items outlive an uninstall, so a UserDefaults marker
/// (deleted with the app) decides whether the stored id belongs to this install: without it, a new id is made.
enum InstallID {
    static let markerKey = "hasInstallID"
    static let storeKey = "installID"

    /// The id for this install, made and stored on first use. If the Keychain can't be written (before the first
    /// unlock after a restart), the new id serves this launch only and the stored one is read on a later launch.
    static func load(defaults: UserDefaults = .standard, secureStore: CodableStore) -> String {
        if defaults.bool(forKey: markerKey), let stored = try? secureStore.load(String.self, forKey: storeKey), isValid(stored) {
            return stored
        }
        let id = UUID().uuidString
        do {
            try secureStore.save(id, forKey: storeKey)
            defaults.set(true, forKey: markerKey)
        } catch {
            EGuardLog.app.error("Couldn't store the install id; using a temporary one for this launch.")
        }
        return id
    }

    /// What the server accepts: 8–64 of `A–Z a–z 0–9 _ -`.
    static func isValid(_ id: String) -> Bool {
        (8...64).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

/// Keychain items outlive an uninstall, so a reinstalled app would open signed in to the previous account
/// (or still holding an old device token). UserDefaults is deleted with the app, so a missing flag means
/// this is the first launch of the install: the app's own Keychain items (session, device token, mode) go.
/// App Group data, which the Screen Time extensions read, isn't touched.
enum FreshInstallReset {
    static let flagKey = "hasLaunchedBefore"
    private static let probeKey = "apiSession"

    /// Returns true when it cleared the store. Call before any store reads the Keychain.
    /// `hasExistingData`: the app's own files are already there, so this is an update from a version without the
    /// flag, not a reinstall (an uninstall deletes them). Nothing is cleared then: a paired child's device stays paired.
    @discardableResult
    static func run(defaults: UserDefaults = .standard, secureStore: CodableStore, hasExistingData: Bool = false) -> Bool {
        guard !defaults.bool(forKey: flagKey) else { return false }
        if hasExistingData {
            defaults.set(true, forKey: flagKey)
            return false
        }
        do {
            // Before the first unlock after a restart, neither UserDefaults nor the Keychain can be read, so a
            // missing flag means nothing then. Leave everything and decide on a later launch.
            _ = try secureStore.load(APISession.self, forKey: probeKey)
        } catch is KeychainError {
            return false
        } catch {
            // An unreadable value is still cleared below.
        }
        do {
            try secureStore.removeAll()
        } catch {
            EGuardLog.app.error("Couldn't clear secure storage on first launch.")
            return false
        }
        defaults.set(true, forKey: flagKey)
        return true
    }

    /// Whether the app's protected files (`ProtectedFileStore`: parent cache, child device state) exist yet.
    static func hasAppFiles(directoryNames: [String] = ["eGuard", "eGuardChild"]) -> Bool {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        return directoryNames.contains { name in
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: base.appending(path: name).path())) ?? []
            return !contents.isEmpty
        }
    }
}
