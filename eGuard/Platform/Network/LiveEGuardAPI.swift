import Foundation

/// Talks to the real eGuard Parent Mobile API through `APIClient`.
final class LiveEGuardAPI: EGuardAPIService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    private struct Empty: Encodable {}
    private struct TokenBody: Encodable { let token: String }
    private struct CodeBody: Encodable { let code: String }

    private func query(_ items: [(String, String?)]) -> [URLQueryItem] {
        items.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    }

    private func iso(_ date: Date?) -> String? {
        date.map { ISO8601DateFormatter.withFractional.string(from: $0) }
    }

    // MARK: Public

    func appInfo() async throws -> AppInfo {
        try await client.send(.get("app-info", requiresAuth: false), as: AppInfo.self)
    }

    func help(query q: String?, category: String?) async throws -> HelpIndex {
        try await client.send(.get("help", query: query([("q", q?.isEmpty == false ? q : nil), ("category", category)]), requiresAuth: false), as: HelpIndex.self)
    }

    func helpArticle(slug: String) async throws -> HelpArticle {
        try await client.send(.get("help/\(slug)", requiresAuth: false), as: HelpArticle.self)
    }

    // MARK: Auth

    func register(name: String, email: String, password: String, familyName: String?) async throws -> AuthResponse {
        struct Body: Encodable { let name: String; let email: String; let password: String; let familyName: String?; let guardian: Bool }
        return try await client.send(
            .json(.post, "auth/register", body: Body(name: name, email: email, password: password, familyName: familyName, guardian: true), requiresAuth: false),
            as: AuthResponse.self
        )
    }

    func login(email: String, password: String) async throws -> LoginResult {
        struct Body: Encodable { let email: String; let password: String }
        return try await client.send(.json(.post, "auth/login", body: Body(email: email, password: password), requiresAuth: false), as: LoginResult.self)
    }

    func social(provider: SocialProvider, idToken: String, name: String?, guardian: Bool, nonce: String?) async throws -> LoginResult {
        struct Body: Encodable { let provider: SocialProvider; let idToken: String; let name: String?; let guardian: Bool?; let nonce: String? }
        return try await client.send(
            .json(.post, "auth/social", body: Body(provider: provider, idToken: idToken, name: name, guardian: guardian ? true : nil, nonce: nonce), requiresAuth: false),
            as: LoginResult.self
        )
    }

    func twoFactor(challenge: String, code: String) async throws -> AuthResponse {
        struct Body: Encodable { let challenge: String; let code: String }
        return try await client.send(.json(.post, "auth/two-factor", body: Body(challenge: challenge, code: code), requiresAuth: false), as: AuthResponse.self)
    }

    func forgotPassword(email: String) async throws -> OKResponse {
        struct Body: Encodable { let email: String }
        return try await client.send(.json(.post, "auth/forgot-password", body: Body(email: email), requiresAuth: false), as: OKResponse.self)
    }

    func resetPassword(token: String, password: String) async throws -> LoginResult {
        struct Body: Encodable { let token: String; let password: String }
        return try await client.send(.json(.post, "auth/reset-password", body: Body(token: token, password: password), requiresAuth: false), as: LoginResult.self)
    }

    func verifyEmail(token: String) async throws {
        try await client.send(.json(.post, "auth/verify-email", body: TokenBody(token: token), requiresAuth: false))
    }

    func invitation(token: String) async throws -> InvitationPreview {
        try await client.send(.get("auth/invite", query: [URLQueryItem(name: "token", value: token)], requiresAuth: false), as: InvitationPreview.self)
    }

    func acceptInvitation(token: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let token: String; let password: String }
        return try await client.send(.json(.post, "auth/accept-invite", body: Body(token: token, password: password), requiresAuth: false), as: AuthResponse.self)
    }

    func declineInvitation(token: String) async throws -> InvitationDeclined {
        try await client.send(.json(.post, "auth/decline-invite", body: TokenBody(token: token), requiresAuth: false), as: InvitationDeclined.self)
    }

    func logout(pushToken: String?) async throws {
        try await client.send(.empty(.post, "auth/logout", query: query([("pushToken", pushToken)])))
    }

    // MARK: Me

    func me() async throws -> APIUser {
        try await client.send(.get("me"), as: APIUser.self)
    }

    func updateMe(name: String?, email: String?, password: String?, timezone: String?) async throws -> APIUser {
        struct Body: Encodable { let name: String?; let email: String?; let password: String?; let timezone: String? }
        return try await client.send(.json(.patch, "me", body: Body(name: name, email: email, password: password, timezone: timezone)), as: APIUser.self)
    }

    func deleteAccount(confirmation: DeletionConfirmation) async throws -> AccountDeleted {
        try await client.send(.json(.delete, "me", body: confirmation), as: AccountDeleted.self)
    }

    func exportData() async throws -> Data {
        try await client.sendData(APIRequest(method: .post, path: "me/export"))
    }

    func identities() async throws -> [LinkedIdentity] {
        struct Response: Decodable { let identities: [LinkedIdentity] }
        return try await client.send(.get("me/identities"), as: Response.self).identities
    }

    func deleteIdentity(id: String) async throws {
        try await client.send(.empty(.delete, "me/identities/\(id)"))
    }

    func changePassword(current: String, next: String) async throws -> OKResponse {
        struct Body: Encodable { let current: String; let next: String }
        return try await client.send(.json(.post, "me/password", body: Body(current: current, next: next)), as: OKResponse.self)
    }

    func resendVerification() async throws -> VerificationSend {
        try await client.send(.empty(.post, "me/verify-email"), as: VerificationSend.self)
    }

    func notificationPrefs() async throws -> NotificationPrefs {
        try await client.send(.get("me/notifications"), as: NotificationPrefs.self)
    }

    func updateNotificationPrefs(_ patch: NotificationPrefsPatch) async throws -> NotificationPrefs {
        try await client.send(.json(.patch, "me/notifications", body: patch), as: NotificationPrefs.self)
    }

    func registerPushToken(_ token: String) async throws {
        struct Body: Encodable { let token: String; let platform = "IOS" }
        try await client.send(.json(.post, "me/push-tokens", body: Body(token: token)))
    }

    func deletePushToken(_ token: String) async throws {
        try await client.send(.json(.delete, "me/push-tokens", body: TokenBody(token: token)))
    }

    func sessions() async throws -> [SessionInfo] {
        struct Response: Decodable { let sessions: [SessionInfo] }
        return try await client.send(.get("me/sessions"), as: Response.self).sessions
    }

    func signOutOtherSessions() async throws -> Int {
        struct Response: Decodable { let signedOut: Int }
        return try await client.send(.empty(.delete, "me/sessions"), as: Response.self).signedOut
    }

    func twoFactorStatus() async throws -> TwoFactorStatus {
        try await client.send(.get("me/two-factor"), as: TwoFactorStatus.self)
    }

    func setupTwoFactor() async throws -> TwoFactorSetup {
        try await client.send(.empty(.post, "me/two-factor/setup"), as: TwoFactorSetup.self)
    }

    func confirmTwoFactor(code: String) async throws -> [String] {
        try await client.send(.json(.post, "me/two-factor/confirm", body: CodeBody(code: code)), as: RecoveryCodes.self).recoveryCodes
    }

    func regenerateRecoveryCodes(code: String) async throws -> [String] {
        try await client.send(.json(.post, "me/two-factor/recovery-codes", body: CodeBody(code: code)), as: RecoveryCodes.self).recoveryCodes
    }

    func disableTwoFactor(code: String) async throws -> TwoFactorStatus {
        try await client.send(.json(.delete, "me/two-factor", body: CodeBody(code: code)), as: TwoFactorStatus.self)
    }

    // MARK: Dashboard and health

    func dashboard() async throws -> Dashboard {
        try await client.send(.get("dashboard"), as: Dashboard.self)
    }

    func health(childId: String?) async throws -> HealthReport {
        try await client.send(.get("health", query: query([("childId", childId)])), as: HealthReport.self)
    }

    // MARK: Onboarding

    func profiles(age: Int) async throws -> [ProfileOption] {
        try await client.send(.get("profiles", query: [URLQueryItem(name: "age", value: String(age))]), as: ProfilesResponse.self).profiles
    }

    func recommendations(childId: String, profile: String?) async throws -> Recommendations {
        try await client.send(.get("children/\(childId)/recommendations", query: query([("profile", profile)])), as: Recommendations.self)
    }

    func setup(childId: String, profile: String, overrides: [JSONValue]) async throws -> SetupResponse {
        try await client.send(.json(.post, "children/\(childId)/setup", body: SetupRequest(profile: profile, overrides: overrides)), as: SetupResponse.self)
    }

    func pairingCode(childId: String) async throws -> PairingCode {
        try await client.send(.empty(.post, "children/\(childId)/pairing-code"), as: PairingCode.self)
    }

    func browserPairingCode(childId: String, deviceLabel: String) async throws -> PairingCode {
        struct Body: Encodable { let kind = "BROWSER"; let deviceLabel: String }
        return try await client.send(.json(.post, "children/\(childId)/pairing-code", body: Body(deviceLabel: deviceLabel)), as: PairingCode.self)
    }

    // MARK: Children

    func children() async throws -> [ChildSummary] {
        struct Response: Decodable { let children: [ChildSummary] }
        return try await client.send(.get("children"), as: Response.self).children
    }

    func createChild(name: String, age: Int, profile: String?) async throws -> ChildSummary {
        struct Body: Encodable { let name: String; let age: Int; let profile: String? }
        return try await client.send(.json(.post, "children", body: Body(name: name, age: age, profile: profile)), as: ChildSummary.self)
    }

    func child(id: String) async throws -> ChildDetail {
        try await client.send(.get("children/\(id)"), as: ChildDetail.self)
    }

    func updateChild(id: String, name: String?, age: Int?) async throws -> ChildDetail {
        struct Body: Encodable { let name: String?; let age: Int? }
        return try await client.send(.json(.patch, "children/\(id)", body: Body(name: name, age: age)), as: ChildDetail.self)
    }

    func deleteChild(id: String, confirmation: DeletionConfirmation) async throws {
        try await client.send(.json(.delete, "children/\(id)", body: confirmation))
    }

    func uploadPhoto(childId: String, data: Data, contentType: String) async throws -> String {
        let request = APIRequest(method: .put, path: "children/\(childId)/photo", body: data, contentType: contentType)
        return try await client.send(request, as: PhotoUploadResponse.self).photoUrl
    }

    func photo(childId: String, url: String) async throws -> Data {
        // photoUrl is relative to the host, so strip the base path if present.
        let base = client.baseURL.path
        var path = url
        if let range = path.range(of: base) { path.removeSubrange(path.startIndex..<range.upperBound) }
        let components = URLComponents(string: path)
        return try await client.sendData(APIRequest(method: .get, path: components?.path ?? "children/\(childId)/photo", query: components?.queryItems ?? []))
    }

    func deletePhoto(childId: String) async throws {
        try await client.send(.empty(.delete, "children/\(childId)/photo"))
    }

    func history(childId: String, before: Date?) async throws -> HistoryPage {
        try await client.send(.get("children/\(childId)/history", query: query([("limit", "30"), ("before", iso(before))])), as: HistoryPage.self)
    }

    // MARK: Protections and batches

    func protections(childId: String) async throws -> [Protection] {
        try await client.send(.get("children/\(childId)/protections"), as: ProtectionsResponse.self).protections
    }

    func updateProtection(childId: String, key: String, config: JSONValue) async throws -> Batch {
        try await client.send(.json(.put, "children/\(childId)/protections/\(key)", body: config.removing("key")), as: Batch.self)
    }

    func batch(id: String) async throws -> Batch {
        try await client.send(.get("batches/\(id)"), as: Batch.self)
    }

    func confirmBatch(id: String) async throws -> Batch {
        try await client.send(.empty(.post, "batches/\(id)/confirm"), as: Batch.self)
    }

    func cancelBatch(id: String) async throws -> Int {
        try await client.send(.empty(.delete, "batches/\(id)"), as: CancelResponse.self).cancelled
    }

    // MARK: Activity

    func screenTime(childId: String, period: ScreenTimePeriod) async throws -> ScreenTimeReport {
        try await client.send(.get("children/\(childId)/screen-time", query: [URLQueryItem(name: "period", value: period.rawValue)]), as: ScreenTimeReport.self)
    }

    func apps(childId: String, filter: AppsFilter?) async throws -> AppsResponse {
        try await client.send(.get("children/\(childId)/apps", query: query([("filter", filter?.rawValue)])), as: AppsResponse.self)
    }

    func updateApp(id: String, patch: AppPatch) async throws -> AppRuleUpdate {
        try await client.send(.json(.patch, "apps/\(id)", body: patch), as: AppRuleUpdate.self)
    }

    func addApp(childId: String, name: String, approval: AppApproval, dailyLimitMinutes: Int?) async throws -> ChildApp {
        try await client.send(.json(.post, "children/\(childId)/apps", body: NewAppRequest(name: name, approval: approval, dailyLimitMinutes: dailyLimitMinutes)), as: ChildApp.self)
    }

    func location(childId: String) async throws -> LocationResponse {
        try await client.send(.get("children/\(childId)/location"), as: LocationResponse.self)
    }

    func visits(childId: String, before: Date?) async throws -> VisitsPage {
        try await client.send(.get("children/\(childId)/location/visits", query: query([("limit", "50"), ("before", iso(before))])), as: VisitsPage.self)
    }

    func familyLocations() async throws -> FamilyLocations {
        try await client.send(.get("locations"), as: FamilyLocations.self)
    }

    // MARK: Alerts

    func alerts(filter: AlertsFilter, childId: String?, includeResolved: Bool, before: Date?) async throws -> AlertsPage {
        try await client.send(.get("alerts", query: query([
            ("filter", filter.rawValue), ("childId", childId),
            ("includeResolved", includeResolved ? "true" : nil), ("before", iso(before)),
        ])), as: AlertsPage.self)
    }

    func unreadCount() async throws -> Int {
        try await client.send(.get("alerts/unread-count"), as: UnreadCount.self).unread
    }

    func markAlertRead(id: String) async throws -> Int {
        try await client.send(.empty(.post, "alerts/\(id)/read"), as: ReadResponse.self).unread
    }

    func markAllAlertsRead() async throws -> Int {
        try await client.send(.empty(.post, "alerts/read-all"), as: ReadResponse.self).marked ?? 0
    }

    func dismissAlert(id: String) async throws {
        try await client.send(.empty(.post, "alerts/\(id)/dismiss"))
    }

    // MARK: Devices, browsers and checks

    func devices() async throws -> DevicesResponse {
        try await client.send(.get("devices"), as: DevicesResponse.self)
    }

    func device(id: String) async throws -> DeviceDetail {
        try await client.send(.get("devices/\(id)"), as: DeviceDetail.self)
    }

    func renameDevice(id: String, name: String) async throws -> DeviceDetail {
        struct Body: Encodable { let name: String }
        return try await client.send(.json(.patch, "devices/\(id)", body: Body(name: name)), as: DeviceDetail.self)
    }

    func unpairDevice(id: String, confirmation: DeletionConfirmation) async throws {
        try await client.send(.json(.delete, "devices/\(id)", body: confirmation))
    }

    func browsers() async throws -> [ConnectedBrowser] {
        try await client.send(.get("browsers"), as: BrowsersResponse.self).browsers
    }

    func removeBrowser(id: String, confirmation: DeletionConfirmation) async throws {
        try await client.send(.json(.delete, "browsers/\(id)", body: confirmation))
    }

    func browserPolicy(childId: String) async throws -> BrowserPolicy {
        try await client.send(.get("children/\(childId)/browser-policy"), as: BrowserPolicy.self)
    }

    func updateBrowserPolicy(childId: String, policy: BrowserPolicyUpdate) async throws -> BrowserPolicy {
        try await client.send(.json(.put, "children/\(childId)/browser-policy", body: policy), as: BrowserPolicy.self)
    }

    func browserAccessRequests(childId: String) async throws -> BrowserAccessRequests {
        try await client.send(.get("children/\(childId)/browser-access-requests"), as: BrowserAccessRequests.self)
    }

    func decideBrowserAccessRequest(id: String, decision: BrowserAccessDecision) async throws -> BrowserAccessRequest {
        try await client.send(.json(.post, "browser-access-requests/\(id)", body: decision), as: BrowserAccessDecided.self).request
    }

    func startCheck(deviceId: String?) async throws -> String {
        struct Body: Encodable { let deviceId: String? }
        return try await client.send(.json(.post, "checks", body: Body(deviceId: deviceId)), as: CheckStarted.self).runId
    }

    func check(runId: String) async throws -> CheckRun {
        try await client.send(.get("checks/\(runId)"), as: CheckRun.self)
    }

    // MARK: Family, organizations and privacy

    func family() async throws -> Family {
        try await client.send(.get("family"), as: Family.self)
    }

    func inviteMember(name: String, email: String) async throws -> InvitationSent {
        try await client.send(.json(.post, "family/members", body: NewMember(name: name, email: email)), as: InvitationSent.self)
    }

    func resendInvitation(memberId: String) async throws {
        try await client.send(.empty(.post, "family/members/\(memberId)/invite"))
    }

    func removeMember(id: String) async throws {
        try await client.send(.empty(.delete, "family/members/\(id)"))
    }

    func privacy() async throws -> PrivacySettings {
        try await client.send(.get("family/privacy"), as: PrivacySettings.self)
    }

    func updatePrivacy(_ patch: PrivacyPatch) async throws -> PrivacySettings {
        try await client.send(.json(.patch, "family/privacy", body: patch), as: PrivacySettings.self)
    }

    func organizations() async throws -> OrganizationsResponse {
        try await client.send(.get("organizations"), as: OrganizationsResponse.self)
    }

    func previewOrganization(code: String) async throws -> OrganizationPreview {
        try await client.send(.json(.post, "organizations/preview", body: CodeBody(code: code)), as: OrganizationPreview.self)
    }

    func joinOrganization(code: String) async throws -> OrganizationJoined {
        try await client.send(.json(.post, "organizations", body: CodeBody(code: code)), as: OrganizationJoined.self)
    }

    func leaveOrganization(id: String) async throws -> OrganizationLeft {
        try await client.send(.empty(.delete, "organizations/\(id)"), as: OrganizationLeft.self)
    }

    // MARK: Subscription and support

    func subscription() async throws -> SubscriptionInfo {
        try await client.send(.get("subscription"), as: SubscriptionInfo.self)
    }

    func createTicket(category: String?, subject: String, message: String) async throws -> SupportTicket {
        try await client.send(.json(.post, "support/tickets", body: NewTicket(category: category, subject: subject, message: message)), as: SupportTicket.self)
    }

    func tickets() async throws -> [SupportTicket] {
        try await client.send(.get("support/tickets"), as: TicketsResponse.self).tickets
    }
}
