import Foundation

@MainActor
protocol ChildProfileRepository: AnyObject {
    func loadChildProfile() throws -> ChildProfile?
    func saveChildProfile(_ profile: ChildProfile) throws
    func deleteChildProfile() throws
}

@MainActor
protocol ProtectionSettingsRepository: AnyObject {
    func loadSettings() throws -> ProtectionSettings?
    func saveSettings(_ settings: ProtectionSettings) throws
}

@MainActor
protocol ProtectionSelectionsRepository: AnyObject {
    func loadSelections() throws -> ProtectionSelections?
    func saveSelections(_ selections: ProtectionSelections) throws
}

@MainActor
protocol SetupProgressRepository: AnyObject {
    func loadProgress() throws -> SetupProgress?
    func saveProgress(_ progress: SetupProgress) throws
}

@MainActor
protocol HealthReportRepository: AnyObject {
    func loadHealthReport() throws -> ConfigurationHealthReport?
    func saveHealthReport(_ report: ConfigurationHealthReport) throws
}

@MainActor
protocol AlertsRepository: AnyObject {
    func loadAlerts() throws -> [ProtectionAlert]?
    func saveAlerts(_ alerts: [ProtectionAlert]) throws
}

@MainActor
protocol PreferencesRepository: AnyObject {
    func loadPreferences() throws -> AppPreferences?
    func savePreferences(_ preferences: AppPreferences) throws
}

/// Everything eGuard persists locally. One object implements all repositories.
@MainActor
protocol EGuardStateRepository: ChildProfileRepository, ProtectionSettingsRepository,
    ProtectionSelectionsRepository, SetupProgressRepository, HealthReportRepository,
    AlertsRepository, PreferencesRepository {
    func eraseAll() throws
}
