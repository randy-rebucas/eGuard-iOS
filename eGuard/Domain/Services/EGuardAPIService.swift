import Foundation

/// Every eGuard Parent Mobile API call the app makes. Implemented by the live client and a mock.
@MainActor
protocol EGuardAPIService: AnyObject {
    // Public
    func appInfo() async throws -> AppInfo
    func help(query: String?, category: String?) async throws -> HelpIndex
    func helpArticle(slug: String) async throws -> HelpArticle

    // Auth
    func register(name: String, email: String, password: String, familyName: String?) async throws -> AuthResponse
    func login(email: String, password: String) async throws -> AuthResponse
    func social(provider: SocialProvider, idToken: String, name: String?, guardian: Bool) async throws -> AuthResponse
    func logout(pushToken: String?) async throws

    // Me
    func me() async throws -> APIUser
    func updateMe(name: String?, email: String?, timezone: String?) async throws -> APIUser
    func changePassword(current: String, next: String) async throws -> OKResponse
    func resendVerification() async throws -> VerificationSend
    func notificationPrefs() async throws -> NotificationPrefs
    func updateNotificationPrefs(_ patch: NotificationPrefsPatch) async throws -> NotificationPrefs
    func registerPushToken(_ token: String) async throws
    func deletePushToken(_ token: String) async throws
    func sessions() async throws -> [SessionInfo]
    func signOutOtherSessions() async throws -> Int

    // Dashboard and health
    func dashboard() async throws -> Dashboard
    func health(childId: String?) async throws -> HealthReport

    // Onboarding
    func profiles(age: Int) async throws -> [ProfileOption]
    func recommendations(childId: String, profile: String?) async throws -> Recommendations
    func setup(childId: String, profile: String, overrides: [JSONValue]) async throws -> SetupResponse
    func pairingCode(childId: String) async throws -> PairingCode

    // Children
    func children() async throws -> [ChildSummary]
    func createChild(name: String, age: Int, profile: String?) async throws -> ChildSummary
    func child(id: String) async throws -> ChildDetail
    func updateChild(id: String, name: String?, age: Int?) async throws -> ChildDetail
    func deleteChild(id: String, password: String) async throws
    func uploadPhoto(childId: String, data: Data, contentType: String) async throws -> String
    func photo(childId: String, url: String) async throws -> Data
    func deletePhoto(childId: String) async throws
    func history(childId: String, before: Date?) async throws -> HistoryPage

    // Protections and batches
    func protections(childId: String) async throws -> [Protection]
    func updateProtection(childId: String, key: String, config: JSONValue) async throws -> Batch
    func batch(id: String) async throws -> Batch
    func confirmBatch(id: String) async throws -> Batch
    func cancelBatch(id: String) async throws -> Int

    // Activity
    func screenTime(childId: String, period: ScreenTimePeriod) async throws -> ScreenTimeReport
    func apps(childId: String, filter: AppsFilter?) async throws -> AppsResponse
    func updateApp(id: String, patch: AppPatch) async throws -> AppRuleUpdate
    func addApp(childId: String, name: String, approval: AppApproval, dailyLimitMinutes: Int?) async throws -> ChildApp
    func location(childId: String) async throws -> LocationResponse
    func visits(childId: String, before: Date?) async throws -> VisitsPage
    func familyLocations() async throws -> FamilyLocations

    // Alerts
    func alerts(filter: AlertsFilter, childId: String?, includeResolved: Bool, before: Date?) async throws -> AlertsPage
    func unreadCount() async throws -> Int
    func markAlertRead(id: String) async throws -> Int
    func markAllAlertsRead() async throws -> Int
    func dismissAlert(id: String) async throws

    // Devices and checks
    func devices() async throws -> DevicesResponse
    func device(id: String) async throws -> DeviceDetail
    func renameDevice(id: String, name: String) async throws -> DeviceDetail
    func unpairDevice(id: String) async throws
    func startCheck(deviceId: String?) async throws -> String
    func check(runId: String) async throws -> CheckRun

    // Family and privacy
    func family() async throws -> Family
    func addMember(name: String, email: String, password: String) async throws -> FamilyMember
    func removeMember(id: String) async throws
    func privacy() async throws -> PrivacySettings
    func updatePrivacy(_ patch: PrivacyPatch) async throws -> PrivacySettings

    // Subscription and support
    func subscription() async throws -> SubscriptionInfo
    func createTicket(category: String?, subject: String, message: String) async throws -> SupportTicket
    func tickets() async throws -> [SupportTicket]
}
