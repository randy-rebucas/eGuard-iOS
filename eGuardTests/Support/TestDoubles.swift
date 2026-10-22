import Foundation
import Observation
@testable import eGuard

// Controllable stand-ins for the system services, plus an `AppModel` wired to the in-memory mock
// server. These exist only in the test target: the app itself always talks to the real API and
// the real Screen Time services.

/// A controllable Family Controls authorization.
@Observable
final class MockAuthorizationService: ParentalControlAuthorizationService {
    enum Behavior {
        case approve
        case deny
        case fail(ParentalControlAuthorizationError)
    }

    private(set) var authorizationStatus: ParentalControlAuthorizationStatus
    var memberKind: FamilyMemberKind = .child
    var behavior: Behavior
    private(set) var requestCount = 0

    init(status: ParentalControlAuthorizationStatus = .notDetermined, behavior: Behavior = .approve) {
        self.authorizationStatus = status
        self.behavior = behavior
    }

    func refreshAuthorizationStatus() {}

    func requestAuthorization() async throws {
        requestCount += 1
        switch behavior {
        case .approve:
            authorizationStatus = .approved
        case .deny:
            authorizationStatus = .denied
        case .fail(let error):
            throw error
        }
    }

    func revokeAuthorization() async throws {
        authorizationStatus = .notDetermined
    }
}

/// In-memory ManagedSettings.
final class MockRestrictionService: RestrictionService {
    private(set) var state = RestrictionSnapshot()
    var errorToThrow: ProtectionConfigurationError?

    init(state: RestrictionSnapshot = .empty) {
        self.state = state
    }

    func applyWebContent(_ level: WebContentLevel) throws {
        try failIfNeeded()
        state.webContentLimited = level == .limited ? true : nil
    }

    func applyAppInstallation(_ policy: AppInstallationPolicy) throws {
        try failIfNeeded()
        state.denyAppInstallation = policy == .blocked ? true : nil
    }

    func applyExplicitContent(block: Bool) throws {
        try failIfNeeded()
        state.denyExplicitContent = block ? true : nil
    }

    func applyPurchaseProtection(requirePassword: Bool) throws {
        try failIfNeeded()
        state.requirePasswordForPurchases = requirePassword ? true : nil
    }

    func applyAppRestrictions(_ selection: ActivitySelectionSnapshot) throws {
        try failIfNeeded()
        state.shieldedApplicationCount = selection.applicationCount
        state.isApplicationCategoryShieldActive = selection.categoryCount > 0
    }

    func applyWebsiteRestrictions(_ selection: ActivitySelectionSnapshot) throws {
        try failIfNeeded()
        state.shieldedWebDomainCount = selection.webDomainCount
        state.isWebDomainCategoryShieldActive = selection.categoryCount > 0
    }

    func applyMaximumAppRating(age: Int?) throws {
        try failIfNeeded()
        // Round-trip through Apple's rating values exactly like the live service.
        state.maximumAppRatingAge = age.flatMap { RatingTiers.age(forRating: RatingTiers.rating(forAge: $0, in: RatingTiers.appStore), in: RatingTiers.appStore) }
    }

    func applyContentRating(age: Int?) throws {
        try failIfNeeded()
        state.contentRatingAge = age.flatMap { RatingTiers.age(forRating: RatingTiers.rating(forAge: $0, in: RatingTiers.movies), in: RatingTiers.movies) }
        state.denyExplicitContent = age.map { $0 < 18 ? true : nil } ?? nil
    }

    func applyAppRemoval(deny: Bool) throws {
        try failIfNeeded()
        state.denyAppRemoval = deny ? true : nil
    }

    func clearAllRestrictions() {
        state = .empty
    }

    func snapshot() -> RestrictionSnapshot {
        state
    }

    /// Simulates the system dropping eGuard's settings, e.g. after authorization is revoked.
    func simulateDrift() {
        state = .empty
    }

    private func failIfNeeded() throws {
        if let errorToThrow { throw errorToThrow }
    }
}

/// In-memory DeviceActivity schedules.
final class MockActivityScheduleService: ActivityScheduleService {
    private(set) var state = ActivityScheduleSnapshot()
    var errorToThrow: ProtectionConfigurationError?

    init(state: ActivityScheduleSnapshot = .empty) {
        self.state = state
    }

    func scheduleDowntime(_ window: DowntimeWindow, days: BedtimeDays) throws {
        if let errorToThrow { throw errorToThrow }
        state.isDowntimeScheduled = true
        state.downtimeWindow = window
        state.downtimeDays = days
    }

    func stopDowntime() {
        state.isDowntimeScheduled = false
        state.downtimeWindow = nil
        state.downtimeDays = nil
    }

    func scheduleDailyLimits(gaming: DailyLimit?, socialApps: DailyLimit?) throws {
        if let errorToThrow { throw errorToThrow }
        state.isDailyLimitMonitoring = gaming != nil || socialApps != nil
        state.gamingLimitMinutes = gaming?.minutes
        state.socialAppsLimitMinutes = socialApps?.minutes
    }

    func stopDailyLimits() {
        state.isDailyLimitMonitoring = false
        state.gamingLimitMinutes = nil
        state.socialAppsLimitMinutes = nil
    }

    func scheduleScreenTimeLimit(minutes: Int, selection: ActivitySelectionSnapshot) throws {
        if let errorToThrow { throw errorToThrow }
        guard !selection.isEmpty else { throw ProtectionConfigurationError.selectionRequired }
        state.screenTimeLimitMinutes = minutes
    }

    func stopScreenTimeLimit() {
        state.screenTimeLimitMinutes = nil
    }

    func stopAll() {
        state = .empty
    }

    func snapshot() -> ActivityScheduleSnapshot {
        state
    }

    /// Simulates the system dropping eGuard's schedules.
    func simulateDrift() {
        state = .empty
    }
}

/// A controllable location source.
@Observable
final class MockLocationReporter: LocationReporting {
    var isAuthorized = false
    var isUndetermined = true
    var fix: LocationFix? = LocationFix(lat: 10.6785, lng: 124.8006, accuracyM: 25, placeLabel: nil)
    private(set) var fixesRequested = 0

    init() {}

    func requestPermission() async {
        isUndetermined = false
        isAuthorized = true
    }

    func currentFix() async -> LocationFix? {
        guard isAuthorized else { return nil }
        fixesRequested += 1
        return fix
    }
}

/// A controllable usage source.
final class MockUsageSource: UsageSource {
    var usage: UsageRequest?

    init(usage: UsageRequest? = nil) {
        self.usage = usage
    }

    func pendingUsage() -> UsageRequest? { usage }
}

extension AppModel {
    /// An app model against the in-memory mock server and mock system services.
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
        if signedIn, let user = api.currentUser {
            model.adoptUser(user)
        }
        return model
    }
}
