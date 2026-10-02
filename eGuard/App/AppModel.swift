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

    /// What a sign-in call led to: a session, or a two-step verification challenge to answer first.
    enum SignInOutcome: Equatable {
        case signedIn(isNew: Bool)
        case twoFactorRequired(TwoFactorChallenge)
    }

    // MARK: Dependencies

    let api: EGuardAPIService
    let sessionStore: SessionStore
    let modeStore: ModeStore
    /// The child-device side of the app. Active only in child device mode.
    let childDevice: ChildDeviceModel
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
    /// A link from an eGuard email waiting to be handled once the UI is ready.
    var pendingDeepLink: DeepLink?
    /// An alert push the parent tapped, waiting for the UI to open it.
    var pendingPushAlert: PushAlert?

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
    var mode: AppMode { modeStore.mode }
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
        modeStore: ModeStore,
        childDevice: ChildDeviceModel,
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
        self.modeStore = modeStore
        self.childDevice = childDevice
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
                // UI tests start on the parent side unless they ask for the mode chooser.
                mode: arguments.contains("-modeUnset") ? .unset : .parent,
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
        let authorization = FamilyControlsAuthorizationService()
        let restrictions = ManagedSettingsRestrictionService()
        let schedules = DeviceActivityScheduleService()
        let network = NetworkMonitor()
        let deviceTokenStore = DeviceTokenStore.live()
        let deviceClient = DeviceAPIClient(tokenStore: deviceTokenStore)
        let locationReporter = CoreLocationReporter()
        let childDevice = ChildDeviceModel(
            api: LiveDeviceAPI(client: deviceClient),
            tokenStore: deviceTokenStore,
            enforcer: ScreenTimeEnforcer(restrictions: restrictions, schedules: schedules, authorization: authorization, environment: environment, locationStatus: locationReporter),
            store: ChildDeviceStore.live(),
            locationReporter: locationReporter,
            usageSource: AppGroupUsageSource(),
            network: network
        )
        let model = AppModel(
            api: LiveEGuardAPI(client: client),
            sessionStore: sessionStore,
            modeStore: ModeStore.live(),
            childDevice: childDevice,
            authorization: authorization,
            restrictions: restrictions,
            schedules: schedules,
            systemSettings: SystemSettingsOpener(),
            repository: LocalStateRepository.live(),
            environment: environment,
            network: network
        )
        client.onUnauthorized = { [weak model] error in model?.handleUnauthorized(reason: error.localizedDescription) }
        deviceClient.onUnauthorized = { [weak childDevice] in childDevice?.handleRemoved() }
        model.reconcileModeAtLaunch()
        return model
    }

    static func mock(
        api mockAPI: MockEGuardAPI? = nil,
        signedIn: Bool = false,
        mode: AppMode = .parent,
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
        let authorization = MockAuthorizationService(status: authorizationStatus, behavior: authorizationBehavior)
        let restrictions = MockRestrictionService()
        let schedules = MockActivityScheduleService()
        let deviceTokenStore = DeviceTokenStore.inMemory()
        // Each mock model gets its own location reporter so parallel tests never share permission state.
        let locationReporter = MockLocationReporter()
        let childDevice = ChildDeviceModel(
            api: MockDeviceAPI(server: api),
            tokenStore: deviceTokenStore,
            enforcer: ScreenTimeEnforcer(restrictions: restrictions, schedules: schedules, authorization: authorization, environment: environment, locationStatus: locationReporter),
            store: ChildDeviceStore.inMemory(),
            locationReporter: locationReporter,
            usageSource: MockUsageSource(),
            network: nil
        )
        let model = AppModel(
            api: api,
            sessionStore: sessionStore,
            modeStore: ModeStore.inMemory(mode),
            childDevice: childDevice,
            authorization: authorization,
            restrictions: restrictions,
            schedules: schedules,
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

    // MARK: Mode

    /// Launch routing from the spec: a stored mode without its credential falls back to the chooser
    /// (child) or to sign-in (parent). A device token with no mode means a pairing finished mid-switch.
    func reconcileModeAtLaunch() {
        switch modeStore.mode {
        case .child where !childDevice.isPaired:
            childDevice.forget()
            modeStore.set(.unset)
        case .unset where childDevice.isPaired:
            modeStore.set(.child)
        case .parent where childDevice.isPaired:
            // Never hold both credentials. The parent session wins; the device token is dropped.
            childDevice.forget()
        default:
            break
        }
    }

    /// The person on the "Who's using this device?" screen picked a side. Nothing is stored until
    /// sign-in or pairing succeeds, so they can still go back.
    func chooseParentSide() {
        // Intentionally empty: `mode` becomes PARENT in `startSession`.
    }

    /// Pairing succeeded on this device: it is now the child's. Any parent session is ended first, and
    /// the push token is unregistered so this phone stops receiving the parent's alerts.
    func enterChildMode() async {
        if isSignedIn {
            try? await api.logout(pushToken: pushToken)
            handleUnauthorized()
        }
        PushService.shared.deleteToken()
        pushToken = nil
        modeStore.set(.child)
    }

    /// "Set up eGuard again" after a parent removed this device.
    func leaveChildMode() {
        childDevice.forget()
        modeStore.set(.unset)
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
    /// In child device mode the device syncs instead; `/app-info` is a parent-side call.
    func bootstrap() async {
        guard bootstrapState != .loading else { return }
        bootstrapState = .loading
        if mode == .child {
            await childDevice.syncNow()
            bootstrapState = .ready
            return
        }
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

    /// Stores a link from an eGuard email. Parent-side screens pick it up; child device mode shows a notice.
    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        pendingDeepLink = link
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

    @discardableResult
    func signIn(email: String, password: String) async throws -> SignInOutcome {
        try await finish(try await api.login(email: email, password: password))
    }

    /// Continue with Apple. Retries with the guardian confirmation only after the caller confirmed it,
    /// so a brand-new sign-up always sees the parent/guardian (18+) question. The nonce binds the
    /// identity token to this sign-in; a server that doesn't accept the field yet gets the call again without it.
    @discardableResult
    func signInWithApple(identityToken: String, fullName: String?, nonce: AppleNonce?, guardianConfirmed: Bool) async throws -> SignInOutcome {
        do {
            return try await finish(try await api.social(provider: .apple, idToken: identityToken, name: fullName, guardian: guardianConfirmed, nonce: nonce?.raw))
        } catch let error as APIError where nonce != nil && error.status == 400 && error.fieldName == "nonce" {
            return try await finish(try await api.social(provider: .apple, idToken: identityToken, name: fullName, guardian: guardianConfirmed, nonce: nil))
        }
    }

    /// The 6-digit authenticator code (or a recovery code) for a pending two-step challenge.
    func completeTwoFactor(challenge: TwoFactorChallenge, code: String) async throws -> AuthResponse {
        let response = try await api.twoFactor(challenge: challenge.challenge, code: code)
        try await startSession(response)
        return response
    }

    /// From a reset link: sets the password and signs in with the session the server returns.
    @discardableResult
    func resetPassword(token: String, password: String) async throws -> SignInOutcome {
        try await finish(try await api.resetPassword(token: token, password: password))
    }

    /// From an invitation link: the invited parent chooses a password and joins the family.
    func acceptInvitation(token: String, password: String) async throws {
        let response = try await api.acceptInvitation(token: token, password: password)
        try await startSession(response)
    }

    private func finish(_ result: LoginResult) async throws -> SignInOutcome {
        switch result {
        case .signedIn(let response):
            try await startSession(response)
            return .signedIn(isNew: response.isNew ?? false)
        case .twoFactorRequired(let challenge):
            return .twoFactorRequired(challenge)
        }
    }

    /// Stores the new session and loads the dashboard. Throws when the server rejects the token it
    /// just issued, so sign-in fails visibly instead of continuing into the app without a session.
    /// Other dashboard failures keep the session and surface through `refreshError`.
    private func startSession(_ response: AuthResponse) async throws {
        sessionStore.save(response.session)
        user = response.user
        sessionEndedMessage = nil
        modeStore.set(.parent)
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

    /// Ends this session on the server and forgets it locally. The install goes back to
    /// "Who's using this device?", as the spec's Parent → unset transition describes.
    func signOut() async {
        try? await api.logout(pushToken: pushToken)
        handleUnauthorized()
        modeStore.set(.unset)
    }

    /// `DELETE /me`: the admin's account takes the whole family with it. Signs out locally afterwards.
    func deleteAccount(confirmation: DeletionConfirmation) async throws -> AccountDeleted {
        let result = try await api.deleteAccount(confirmation: confirmation)
        handleUnauthorized()
        modeStore.set(.unset)
        return result
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

    /// A new or rotated FCM registration token. Registered now when signed in, otherwise at the next sign-in.
    func updatePushToken(_ token: String) {
        guard token != pushToken else { return }
        pushToken = token
        guard isSignedIn, mode == .parent else { return }
        Task { try? await api.registerPushToken(token) }
    }

    /// Opens the alert a push pointed at: marks it read and lets the caller show the Alerts tab.
    func consumePushAlert() async -> PushAlert? {
        guard let alert = pendingPushAlert else { return nil }
        pendingPushAlert = nil
        guard mode == .parent, isSignedIn else { return nil }
        if let unread = try? await api.markAlertRead(id: alert.alertId) {
            unreadAlerts = unread
        }
        return alert
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
