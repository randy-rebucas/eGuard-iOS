import Foundation
import OSLog
import Observation

/// The composition root and shared application state.
/// The parent's family lives on the eGuard server; this model owns the session and the
/// data every tab shares. The local Screen Time services remain for the device-side role.
@Observable
final class AppModel {
    enum BootstrapState: Equatable {
        case idle
        case loading
        case ready
        case updateRequired(minimum: String)
    }

    // MARK: Dependencies

    let api: EGuardAPIService
    let sessionStore: SessionStore
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

    // MARK: Server state

    private(set) var user: APIUser?
    private(set) var appInfo: AppInfo?
    private(set) var dashboard: Dashboard?
    private(set) var unreadAlerts = 0
    private(set) var bootstrapState: BootstrapState = .idle
    private(set) var pushToken: String?
    /// The most recent server error while refreshing shared data, for a banner.
    private(set) var refreshError: String?
    /// Why the last session ended when the server rejected it, shown on Welcome so the parent knows to sign in again.
    private(set) var sessionEndedMessage: String?
    /// Child photos by versioned URL.
    var photoCache: [String: Data] = [:]

    // MARK: Local state (device-side role and offline cache)

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
    var isSignedIn: Bool { sessionStore.session != nil }
    var children: [ChildSummary] { dashboard?.children ?? [] }
    var hasChildren: Bool { !children.isEmpty }
    /// The main tabs show once the parent is signed in and has added a child.
    var isSetupComplete: Bool { isSignedIn && hasChildren }
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    /// Support and privacy contact: the server's `/app-info` value when available, else the publisher default.
    var supportEmail: String {
        let fromServer = appInfo?.supportEmail?.trimmingCharacters(in: .whitespaces) ?? ""
        return fromServer.isEmpty ? EGuardPublisher.supportEmail : fromServer
    }

    // MARK: Init

    init(
        api: EGuardAPIService,
        sessionStore: SessionStore,
        authorization: ParentalControlAuthorizationService,
        restrictions: RestrictionService,
        schedules: ActivityScheduleService,
        systemSettings: SystemSettingsService,
        repository: EGuardStateRepository,
        environment: PlatformEnvironment,
        network: NetworkMonitor? = nil,
        skipsSplash: Bool = false
    ) {
        self.api = api
        self.sessionStore = sessionStore
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
            let seeded = arguments.contains("-setupComplete")
            let model = mock(
                api: seeded ? .seeded() : .empty(),
                signedIn: seeded,
                authorizationStatus: seeded ? .approved : .notDetermined,
                authorizationBehavior: arguments.contains("-denyAuthorization") ? .deny : .approve,
                skipsSplash: true
            )
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
        let sessionStore = SessionStore.live()
        let client = APIClient(sessionStore: sessionStore)
        let model = AppModel(
            api: LiveEGuardAPI(client: client),
            sessionStore: sessionStore,
            authorization: FamilyControlsAuthorizationService(),
            restrictions: ManagedSettingsRestrictionService(),
            schedules: DeviceActivityScheduleService(),
            systemSettings: SystemSettingsOpener(),
            repository: LocalStateRepository.live(),
            environment: environment,
            network: NetworkMonitor()
        )
        client.onUnauthorized = { [weak model] error in model?.handleUnauthorized(reason: error.localizedDescription) }
        return model
    }

    static func mock(
        api mockAPI: MockEGuardAPI? = nil,
        signedIn: Bool = false,
        authorizationStatus: ParentalControlAuthorizationStatus = .notDetermined,
        authorizationBehavior: MockAuthorizationService.Behavior = .approve,
        environment: PlatformEnvironment = .iPhone,
        skipsSplash: Bool = true
    ) -> AppModel {
        let api = mockAPI ?? .empty()
        let sessionStore = SessionStore.inMemory()
        if signedIn {
            sessionStore.save(MockEGuardAPI.seededSession)
        }
        let model = AppModel(
            api: api,
            sessionStore: sessionStore,
            authorization: MockAuthorizationService(status: authorizationStatus, behavior: authorizationBehavior),
            restrictions: MockRestrictionService(),
            schedules: MockActivityScheduleService(),
            systemSettings: SystemSettingsOpener(),
            repository: LocalStateRepository.inMemory(),
            environment: environment,
            skipsSplash: skipsSplash
        )
        if signedIn {
            model.user = api.currentUser
        }
        return model
    }

    /// A signed-in parent with a seeded family, for previews of the main app.
    static func preview() -> AppModel {
        let model = make(arguments: ["-uiTesting", "-setupComplete"])
        // Previews render synchronously, so fetch the dashboard eagerly.
        Task { await model.bootstrap() }
        return model
    }

    // MARK: Launch

    /// Runs the launch flow: app-info gate, then the dashboard when a session exists.
    func bootstrap() async {
        guard bootstrapState != .loading else { return }
        bootstrapState = .loading
        if let info = try? await api.appInfo() {
            appInfo = info
            if info.requiresUpdate(currentVersion: currentVersion) {
                bootstrapState = .updateRequired(minimum: info.minimumAppVersion)
                return
            }
        }
        if isSignedIn {
            await refreshDashboard()
        }
        bootstrapState = .ready
    }

    /// Reloads the Home tab data and the unread badge. A 401 signs the parent out.
    func refreshDashboard() async {
        do {
            try await loadDashboard()
        } catch let error as APIError where error.isUnauthorized {
            handleUnauthorized(reason: error.localizedDescription)
        } catch {
            refreshError = error.localizedDescription
        }
    }

    /// Fetches the dashboard and stores it, or throws the API error for the caller to handle.
    private func loadDashboard() async throws {
        let dashboard = try await api.dashboard()
        self.dashboard = dashboard
        user = dashboard.user
        unreadAlerts = dashboard.unreadAlerts
        refreshError = nil
    }

    func refreshUnreadCount() async {
        if let count = try? await api.unreadCount() {
            unreadAlerts = count
        }
    }

    func setUnreadAlerts(_ count: Int) {
        unreadAlerts = count
    }

    func refreshUser() async {
        if let user = try? await api.me() {
            self.user = user
        }
    }

    // MARK: Account

    func register(name: String, email: String, password: String) async throws {
        let response = try await api.register(name: name, email: email, password: password, familyName: nil)
        try await startSession(response)
    }

    func signIn(email: String, password: String) async throws {
        let response = try await api.login(email: email, password: password)
        try await startSession(response)
    }

    /// Continue with Apple. Retries with the guardian confirmation when the server asks for it.
    @discardableResult
    func signInWithApple(identityToken: String, fullName: String?) async throws -> Bool {
        let response: AuthResponse
        do {
            response = try await api.social(provider: .apple, idToken: identityToken, name: fullName, guardian: false)
        } catch let error as APIError where error.code == "guardian_required" {
            response = try await api.social(provider: .apple, idToken: identityToken, name: fullName, guardian: true)
        }
        try await startSession(response)
        return response.isNew ?? false
    }

    /// Stores the new session and loads the dashboard. Throws when the server rejects the token it
    /// just issued, so sign-in fails visibly instead of continuing into the app without a session.
    /// Other dashboard failures keep the session and surface through `refreshError`.
    private func startSession(_ response: AuthResponse) async throws {
        sessionStore.save(response.session)
        user = response.user
        sessionEndedMessage = nil
        do {
            try await loadDashboard()
        } catch let error as APIError where error.isUnauthorized {
            handleUnauthorized(reason: error.localizedDescription)
            throw error
        } catch {
            refreshError = error.localizedDescription
        }
        if let pushToken {
            try? await api.registerPushToken(pushToken)
        }
    }

    /// Ends this session on the server and forgets it locally.
    func signOut() async {
        try? await api.logout(pushToken: pushToken)
        handleUnauthorized()
    }

    /// Clears the session without a server call, e.g. after a 401.
    /// `reason` is the server's message when the session was rejected; nil for a deliberate sign-out.
    func handleUnauthorized(reason: String? = nil) {
        sessionStore.clear()
        user = nil
        dashboard = nil
        unreadAlerts = 0
        refreshError = nil
        sessionEndedMessage = reason
    }

    func updatePushToken(_ token: String) {
        pushToken = token
        guard isSignedIn else { return }
        Task { try? await api.registerPushToken(token) }
    }

    // MARK: Child (local cache for the device-side role)

    func saveChildProfile(_ profile: ChildProfile) {
        childProfile = profile
        authorization.memberKind = profile.relationship.memberKind
        persist { try repository.saveChildProfile(profile) }
    }

    // MARK: Local settings

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

    // MARK: Local configuration

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

    // MARK: Local health

    @discardableResult
    func performHealthCheck() -> ConfigurationHealthReport {
        let report = runHealthCheck.run(settings: settings, progress: progress, selections: selections)
        lastHealthReport = report
        authorizationStatus = authorization.authorizationStatus
        persist { try repository.saveHealthReport(report) }
        if progress.isSetupComplete {
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

    /// Removes every local protection, forgets all local data, and ends the server session.
    func resetEverything() {
        applyProtection.removeAllProtections()
        childProfile = nil
        settings = .off
        selections = ProtectionSelections()
        progress = SetupProgress()
        lastHealthReport = nil
        alerts = []
        preferences = AppPreferences()
        persist { try repository.eraseAll() }
        Task { await signOut() }
    }

    // MARK: Local alerts

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

    var unreadAlertCount: Int { unreadAlerts }

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

    // MARK: Authorization (device-side role)

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
}
