import Foundation
import OSLog
import Observation

/// The composition root and shared application state.
/// Views read state from here; view models call its methods to change it.
@Observable
final class AppModel {
    // MARK: Dependencies

    let authorization: ParentalControlAuthorizationService
    let restrictions: RestrictionService
    let schedules: ActivityScheduleService
    let systemSettings: SystemSettingsService
    let repository: EGuardStateRepository
    let environment: PlatformEnvironment
    let capabilityResolver: CapabilityResolver
    let recommendSetup = RecommendSetupUseCase()
    let applyProtection: ApplyProtectionUseCase
    let runHealthCheck: RunHealthCheckUseCase
    private let network: NetworkMonitor?

    // MARK: State

    private(set) var account: UserAccount?
    private(set) var childProfile: ChildProfile?
    private(set) var settings: ProtectionSettings
    private(set) var selections: ProtectionSelections
    private(set) var progress: SetupProgress
    private(set) var lastHealthReport: ConfigurationHealthReport?
    private(set) var authorizationStatus: ParentalControlAuthorizationStatus
    private(set) var alerts: [ProtectionAlert]
    private(set) var preferences: AppPreferences
    private(set) var persistenceError: String?

    /// Whether the launch splash should be skipped, e.g. under UI tests.
    let skipsSplash: Bool

    var isOnline: Bool { network?.isOnline ?? true }
    var isSetupComplete: Bool { progress.isSetupComplete }
    var isSignedIn: Bool { account != nil }
    var unreadAlertCount: Int { alerts.filter { !$0.isRead }.count }

    // MARK: Init

    init(
        authorization: ParentalControlAuthorizationService,
        restrictions: RestrictionService,
        schedules: ActivityScheduleService,
        systemSettings: SystemSettingsService,
        repository: EGuardStateRepository,
        environment: PlatformEnvironment,
        network: NetworkMonitor? = nil,
        skipsSplash: Bool = false
    ) {
        self.authorization = authorization
        self.restrictions = restrictions
        self.schedules = schedules
        self.systemSettings = systemSettings
        self.repository = repository
        self.environment = environment
        self.network = network
        self.skipsSplash = skipsSplash
        self.capabilityResolver = CapabilityResolver(environment: environment)
        self.applyProtection = ApplyProtectionUseCase(
            restrictions: restrictions,
            schedules: schedules,
            authorization: authorization,
            capabilities: capabilityResolver
        )
        self.runHealthCheck = RunHealthCheckUseCase(
            restrictions: restrictions,
            schedules: schedules,
            authorization: authorization,
            capabilities: capabilityResolver
        )

        account = try? repository.loadAccount()
        childProfile = try? repository.loadChildProfile()
        settings = (try? repository.loadSettings()) ?? .off
        selections = (try? repository.loadSelections()) ?? ProtectionSelections()
        progress = (try? repository.loadProgress()) ?? SetupProgress()
        lastHealthReport = try? repository.loadHealthReport()
        alerts = (try? repository.loadAlerts()) ?? []
        preferences = (try? repository.loadPreferences()) ?? AppPreferences()
        authorizationStatus = authorization.authorizationStatus
    }

    // MARK: Factories

    /// Builds the model for the current process. UI tests and previews get mocks.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        if arguments.contains("-uiTesting") {
            let model = mock(
                authorizationStatus: arguments.contains("-setupComplete") ? .approved : .notDetermined,
                authorizationBehavior: arguments.contains("-denyAuthorization") ? .deny : .approve,
                skipsSplash: true
            )
            if arguments.contains("-setupComplete") {
                model.seedCompletedSetup()
            }
            return model
        }
        return live()
    }

    static func live() -> AppModel {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        let environment = PlatformEnvironment(
            isFamilyControlsAvailable: !ProcessInfo.processInfo.isiOSAppOnMac,
            isSimulator: isSimulator
        )
        return AppModel(
            authorization: FamilyControlsAuthorizationService(),
            restrictions: ManagedSettingsRestrictionService(),
            schedules: DeviceActivityScheduleService(),
            systemSettings: SystemSettingsOpener(),
            repository: LocalStateRepository.live(),
            environment: environment,
            network: NetworkMonitor()
        )
    }

    static func mock(
        authorizationStatus: ParentalControlAuthorizationStatus = .notDetermined,
        authorizationBehavior: MockAuthorizationService.Behavior = .approve,
        environment: PlatformEnvironment = .iPhone,
        skipsSplash: Bool = true
    ) -> AppModel {
        AppModel(
            authorization: MockAuthorizationService(status: authorizationStatus, behavior: authorizationBehavior),
            restrictions: MockRestrictionService(),
            schedules: MockActivityScheduleService(),
            systemSettings: SystemSettingsOpener(),
            repository: LocalStateRepository.inMemory(),
            environment: environment,
            skipsSplash: skipsSplash
        )
    }

    /// A signed-in, fully configured model for previews of the main app.
    static func preview() -> AppModel {
        let model = make(arguments: ["-uiTesting", "-setupComplete"])
        return model
    }

    // MARK: Account

    func createAccount(_ newAccount: UserAccount) {
        account = newAccount
        persist { try repository.saveAccount(newAccount) }
    }

    /// Signs in against the account stored on this device.
    func signIn(email: String, password: String) throws {
        guard let stored = try? repository.loadAccount() else { throw AccountError.noAccount }
        guard stored.normalizedEmail == email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            throw AccountError.emailMismatch
        }
        if stored.provider == .email {
            guard stored.verify(password: password) else { throw AccountError.wrongPassword }
        }
        account = stored
    }

    /// Signs in with a third-party identity. Reuses the stored account when the email matches.
    func signIn(provider: AccountProvider, fullName: String?, email: String?) {
        if let stored = try? repository.loadAccount(),
           stored.provider == provider || stored.normalizedEmail == email?.lowercased() {
            account = stored
            return
        }
        let name = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false ? name : nil) ?? "Parent"
        let resolvedEmail = email ?? "Hidden by \(provider.title)"
        createAccount(UserAccount(fullName: resolvedName, email: resolvedEmail, provider: provider))
    }

    func updateAccount(fullName: String, email: String) {
        guard var current = account else { return }
        current.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        current.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        account = current
        persist { try repository.saveAccount(current) }
    }

    /// Signs out but keeps the child's protections and profile on the device.
    func signOut() {
        account = nil
    }

    // MARK: Child

    func saveChildProfile(_ profile: ChildProfile) {
        childProfile = profile
        authorization.memberKind = profile.relationship.memberKind
        persist { try repository.saveChildProfile(profile) }
    }

    // MARK: Settings

    func chooseProfile(_ profile: ProtectionProfile) {
        let age = childProfile?.age ?? 12
        updateSettings(recommendSetup.recommend(profile: profile, childAge: age))
    }

    func updateSettings(_ newSettings: ProtectionSettings) {
        guard newSettings != settings else { return }
        // A changed value must be configured again, so its previous state is cleared.
        for feature in ProtectionFeature.allCases where settings.summary(for: feature) != newSettings.summary(for: feature) {
            progress.set(.notConfigured, for: feature)
        }
        settings = newSettings
        persist { try repository.saveSettings(newSettings) }
        persist { try repository.saveProgress(progress) }
    }

    func updateSelection(_ snapshot: ActivitySelectionSnapshot, for purpose: SelectionPurpose) {
        selections[purpose] = snapshot
        for feature in ProtectionFeature.allCases where feature.selectionPurpose == purpose {
            progress.set(.notConfigured, for: feature)
        }
        persist { try repository.saveSelections(selections) }
        persist { try repository.saveProgress(progress) }
    }

    func capability(for feature: ProtectionFeature) -> ProtectionCapability {
        capabilityResolver.capability(for: feature, settings: settings)
    }

    // MARK: Configuration

    /// Applies an automatic feature and records the true outcome.
    @discardableResult
    func configure(_ feature: ProtectionFeature) -> FeatureConfigurationState {
        let state = applyProtection.apply(feature, settings: settings, selections: selections)
        setFeatureState(state, for: feature)
        refreshAuthorization()
        return state
    }

    func markGuidedStepOpened(_ feature: ProtectionFeature) {
        setFeatureState(.awaitingReturn(.now), for: feature)
    }

    func confirmGuidedStep(_ feature: ProtectionFeature) {
        setFeatureState(.confirmedByParent(.now), for: feature)
    }

    func skip(_ feature: ProtectionFeature) {
        setFeatureState(.skipped, for: feature)
    }

    func setFeatureState(_ state: FeatureConfigurationState, for feature: ProtectionFeature) {
        progress.set(state, for: feature)
        persist { try repository.saveProgress(progress) }
    }

    // MARK: Health

    @discardableResult
    func performHealthCheck() -> ConfigurationHealthReport {
        let report = runHealthCheck.run(settings: settings, progress: progress, selections: selections)
        lastHealthReport = report
        authorizationStatus = authorization.authorizationStatus
        persist { try repository.saveHealthReport(report) }
        if isSetupComplete {
            recordAlerts(from: report)
        }
        return report
    }

    func completeSetup() {
        progress.isSetupComplete = true
        progress.completedAt = .now
        persist { try repository.saveProgress(progress) }
        addAlert(ProtectionAlert(
            category: .protection,
            title: "Setup complete",
            detail: "\(childProfile?.deviceName ?? "The device") is protected with the \(settings.profile.title) profile.",
            isRead: true
        ))
    }

    /// Removes every protection and forgets all local data, including the account.
    func resetEverything() {
        applyProtection.removeAllProtections()
        account = nil
        childProfile = nil
        settings = .off
        selections = ProtectionSelections()
        progress = SetupProgress()
        lastHealthReport = nil
        alerts = []
        preferences = AppPreferences()
        persist { try repository.eraseAll() }
    }

    // MARK: Alerts

    func addAlert(_ alert: ProtectionAlert) {
        alerts = AlertGenerator.merge([alert], into: alerts)
        persist { try repository.saveAlerts(alerts) }
    }

    private func recordAlerts(from report: ConfigurationHealthReport) {
        let generated = AlertGenerator.alerts(from: report, deviceName: childProfile?.deviceName ?? "this device")
        let merged = AlertGenerator.merge(generated, into: alerts)
        guard merged != alerts else { return }
        alerts = merged
        persist { try repository.saveAlerts(alerts) }
    }

    func markAllAlertsRead() {
        guard alerts.contains(where: { !$0.isRead }) else { return }
        alerts = alerts.map { alert in
            var copy = alert
            copy.isRead = true
            return copy
        }
        persist { try repository.saveAlerts(alerts) }
    }

    func clearAlerts() {
        alerts = []
        persist { try repository.saveAlerts(alerts) }
    }

    // MARK: Preferences

    func updatePreferences(_ change: (inout AppPreferences) -> Void) {
        var copy = preferences
        change(&copy)
        guard copy != preferences else { return }
        preferences = copy
        persist { try repository.savePreferences(copy) }
    }

    func setLocationSharing(_ enabled: Bool) {
        let wasEnabled = preferences.isLocationSharingEnabled
        updatePreferences { $0.isLocationSharingEnabled = enabled }
        guard wasEnabled != enabled else { return }
        addAlert(ProtectionAlert(
            category: .location,
            title: enabled ? "Location sharing turned on" : "Location sharing turned off",
            detail: childProfile?.deviceName ?? "This device"
        ))
    }

    func recordVisit(_ visit: LocationVisit) {
        updatePreferences { $0.recordVisit(visit) }
    }

    // MARK: Authorization

    func refreshAuthorization() {
        authorization.refreshAuthorizationStatus()
        authorizationStatus = authorization.authorizationStatus
    }

    func requestAuthorization() async throws {
        if let childProfile {
            authorization.memberKind = childProfile.relationship.memberKind
        }
        defer { authorizationStatus = authorization.authorizationStatus }
        try await authorization.requestAuthorization()
    }

    // MARK: Helpers

    private func persist(_ work: () throws -> Void) {
        do {
            try work()
            persistenceError = nil
        } catch {
            persistenceError = "eGuard couldn't save your changes on this device."
            EGuardLog.app.error("Persistence failed.")
        }
    }

    /// Seeds a signed-in parent with a finished Balanced setup so UI tests and previews open the dashboard directly.
    private func seedCompletedSetup() {
        createAccount(UserAccount(fullName: "Randy Cruz", email: "randy@example.com"))
        saveChildProfile(ChildProfile(name: "Mia", age: 12, device: .iPhone, relationship: .childInFamilySharing))
        chooseProfile(.balanced)
        for feature in settings.enabledFeatures {
            switch capability(for: feature).mode {
            case .automatic: configure(feature)
            case .guided: confirmGuidedStep(feature)
            default: break
            }
        }
        completeSetup()
        performHealthCheck()
        addAlert(ProtectionAlert(
            category: .apps,
            title: "New app installed",
            detail: "Ask to Buy request on \(childProfile?.deviceName ?? "the device")",
            date: Date.now.addingTimeInterval(-3 * 3600)
        ))
    }
}
