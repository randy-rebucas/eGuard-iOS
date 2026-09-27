import Foundation
import OSLog

/// Stores JSON files in Application Support with complete file protection.
final class ProtectedFileStore: CodableStore {
    private let directory: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(directoryName: String = "eGuard") throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try encoder.encode(value)
        try data.write(to: fileURL(for: key), options: [.atomic, .completeFileProtection])
    }

    func remove(forKey key: String) throws {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path()) else { return }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        directory.appending(path: "\(key).json")
    }
}

/// The single local persistence layer. The child's profile lives in the Keychain; the rest in protected files.
final class LocalStateRepository: EGuardStateRepository {
    private enum Key {
        static let childProfile = "childProfile"
        static let settings = "protectionSettings"
        static let selections = "protectionSelections"
        static let progress = "setupProgress"
        static let healthReport = "healthReport"
        static let alerts = "protectionAlerts"
        static let preferences = "appPreferences"
    }

    private let secureStore: CodableStore
    private let fileStore: CodableStore

    init(secureStore: CodableStore, fileStore: CodableStore) {
        self.secureStore = secureStore
        self.fileStore = fileStore
    }

    static func live() -> LocalStateRepository {
        let fileStore: CodableStore
        do {
            fileStore = try ProtectedFileStore()
        } catch {
            EGuardLog.app.error("Protected file store unavailable; falling back to memory.")
            fileStore = InMemoryStore()
        }
        return LocalStateRepository(secureStore: KeychainStore(), fileStore: fileStore)
    }

    static func inMemory() -> LocalStateRepository {
        LocalStateRepository(secureStore: InMemoryStore(), fileStore: InMemoryStore())
    }

    // MARK: ChildProfileRepository

    func loadChildProfile() throws -> ChildProfile? {
        try secureStore.load(ChildProfile.self, forKey: Key.childProfile)
    }

    func saveChildProfile(_ profile: ChildProfile) throws {
        try secureStore.save(profile, forKey: Key.childProfile)
    }

    func deleteChildProfile() throws {
        try secureStore.remove(forKey: Key.childProfile)
    }

    // MARK: ProtectionSettingsRepository

    func loadSettings() throws -> ProtectionSettings? {
        try fileStore.load(ProtectionSettings.self, forKey: Key.settings)
    }

    func saveSettings(_ settings: ProtectionSettings) throws {
        try fileStore.save(settings, forKey: Key.settings)
    }

    // MARK: ProtectionSelectionsRepository

    func loadSelections() throws -> ProtectionSelections? {
        try fileStore.load(ProtectionSelections.self, forKey: Key.selections)
    }

    func saveSelections(_ selections: ProtectionSelections) throws {
        try fileStore.save(selections, forKey: Key.selections)
    }

    // MARK: SetupProgressRepository

    func loadProgress() throws -> SetupProgress? {
        try fileStore.load(SetupProgress.self, forKey: Key.progress)
    }

    func saveProgress(_ progress: SetupProgress) throws {
        try fileStore.save(progress, forKey: Key.progress)
    }

    // MARK: HealthReportRepository

    func loadHealthReport() throws -> ConfigurationHealthReport? {
        try fileStore.load(ConfigurationHealthReport.self, forKey: Key.healthReport)
    }

    func saveHealthReport(_ report: ConfigurationHealthReport) throws {
        try fileStore.save(report, forKey: Key.healthReport)
    }

    // MARK: AlertsRepository

    func loadAlerts() throws -> [ProtectionAlert]? {
        try fileStore.load([ProtectionAlert].self, forKey: Key.alerts)
    }

    func saveAlerts(_ alerts: [ProtectionAlert]) throws {
        try fileStore.save(alerts, forKey: Key.alerts)
    }

    // MARK: PreferencesRepository

    func loadPreferences() throws -> AppPreferences? {
        try fileStore.load(AppPreferences.self, forKey: Key.preferences)
    }

    func savePreferences(_ preferences: AppPreferences) throws {
        try fileStore.save(preferences, forKey: Key.preferences)
    }

    // MARK: EGuardStateRepository

    func eraseAll() throws {
        try secureStore.removeAll()
        try fileStore.removeAll()
    }
}
