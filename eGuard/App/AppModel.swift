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

    private(set) var childProfile: ChildProfile?
    private(set) var settings: ProtectionSettings
    private(set) var selections: ProtectionSelections
    private(set) var progress: SetupProgress
    private(set) var lastHealthReport: ConfigurationHealthReport?
    private(set) var authorizationStatus: ParentalControlAuthorizationStatus
    private(set) var persistenceError: String?

    var isOnline: Bool { network?.isOnline ?? true }
    var isSetupComplete: Bool { progress.isSetupComplete }

    // MARK: Init

    init(
        authorization: ParentalControlAuthorizationService,
        restrictions: RestrictionService,
        schedules: ActivityScheduleService,
        systemSettings: SystemSettingsService,
        repository: EGuardStateRepository,
        environment: PlatformEnvironment,
        network: NetworkMonitor? = nil
    ) {
        self.authorization = authorization
        self.restrictions = restrictions
        self.schedules = schedules
        self.systemSettings = systemSettings
        self.repository = repository
        self.environment = environment
        self.network = network
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

        childProfile = try? repository.loadChildProfile()
        settings = (try? repository.loadSettings()) ?? .off
        selections = (try? repository.loadSelections()) ?? ProtectionSelections()
        progress = (try? repository.loadProgress()) ?? SetupProgress()
        lastHealthReport = try? repository.loadHealthReport()
        authorizationStatus = authorization.authorizationStatus
    }

    // MARK: Factories

    /// Builds the model for the current process. UI tests and previews get mocks.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        if arguments.contains("-uiTesting") {
            let model = mock(
                authorizationStatus: arguments.contains("-setupComplete") ? .approved : .notDetermined,
                authorizationBehavior: arguments.contains("-denyAuthorization") ? .deny : .approve
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
        environment: PlatformEnvironment = .iPhone
    ) -> AppModel {
        AppModel(
            authorization: MockAuthorizationService(status: authorizationStatus, behavior: authorizationBehavior),
            restrictions: MockRestrictionService(),
            schedules: MockActivityScheduleService(),
            systemSettings: SystemSettingsOpener(),
            repository: LocalStateRepository.inMemory(),
            environment: environment
        )
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
        return report
    }

    func completeSetup() {
        progress.isSetupComplete = true
        progress.completedAt = .now
        persist { try repository.saveProgress(progress) }
    }

    /// Removes every protection and forgets all local data.
    func resetEverything() {
        applyProtection.removeAllProtections()
        childProfile = nil
        settings = .off
        selections = ProtectionSelections()
        progress = SetupProgress()
        lastHealthReport = nil
        persist { try repository.eraseAll() }
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

    /// Seeds a finished Balanced setup so UI tests can open the dashboard directly.
    private func seedCompletedSetup() {
        saveChildProfile(ChildProfile(name: "Mia", age: 12, device: .iPhone, relationship: .childInFamilySharing))
        chooseProfile(.balanced)
        for feature in settings.enabledFeatures {
            switch capability(for: feature).mode {
            case .automatic: configure(feature)
            case .guided: confirmGuidedStep(feature)
            default: break
            }
        }
        performHealthCheck()
        completeSetup()
    }
}
