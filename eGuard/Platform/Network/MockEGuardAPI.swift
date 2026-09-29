import Foundation

/// An in-memory eGuard API with the spec's example data. Used by previews, UI tests, and unit tests.
/// It keeps enough state that flows behave like the real server: sign-in, adding a child, batches that
/// verify after a couple of polls, alerts that resolve, and app rules that change.
final class MockEGuardAPI: EGuardAPIService {
    private struct Account {
        var user: APIUser
        var password: String
    }

    // MARK: State

    private var accounts: [String: Account] = [:]
    private(set) var currentUser: APIUser?
    private var summaries: [ChildSummary] = []
    private var devicesByChild: [String: [APIDevice]] = [:]
    private var protectionsByChild: [String: [Protection]] = [:]
    private var appsByChild: [String: [ChildApp]] = [:]
    private var photos: [String: Data] = [:]
    private var alertsList: [APIAlert] = []
    private var batches: [String: Batch] = [:]
    private var batchPolls: [String: Int] = [:]
    private var members: [FamilyMember] = []
    private var privacySettings = PrivacySettings(keepLocationHistory: true, shareAnalytics: false, retentionDays: 90)
    private var ticketsList: [SupportTicket] = []
    private var pushTokens: Set<String> = []
    private var sequence = 0

    /// Overrides for tests.
    var appInfoValue = AppInfo(
        name: "eGuard",
        apiVersion: "1",
        minimumAppVersion: "1.0.0",
        signIn: AppInfo.SignInOptions(password: true, apple: true, google: false),
        supportEmail: "support@devcomdigital.com"
    )
    /// Thrown by the next call, then cleared. Lets tests exercise error paths.
    var nextError: APIError?
    /// Thrown by the next `dashboard()` call only, then cleared. Lets tests fail the post-sign-in load.
    var nextDashboardError: APIError?
    /// How many polls a batch needs before automatic items verify.
    var pollsUntilVerified = 2

    private let family = FamilyRef(id: "fam_cruz", name: "Cruz Family", timezone: "Asia/Manila")

    // MARK: Factories

    /// A server with one registered parent (randy@example.com / ChangeMe123!) and no children.
    static func empty() -> MockEGuardAPI {
        let api = MockEGuardAPI()
        api.seedParent()
        return api
    }

    /// A server where Randy is signed in with two children, devices, alerts, and history.
    static func seeded() -> MockEGuardAPI {
        let api = MockEGuardAPI()
        api.seedParent()
        api.currentUser = api.accounts["randy@example.com"]?.user
        api.seedFamily()
        return api
    }

    /// The session a seeded mock accepts. `AppModel.make` stores it for `-setupComplete`.
    static let seededSession = APISession(token: "mock-token", expiresAt: Date.now.addingTimeInterval(30 * 86400))

    private init() {}

    // MARK: Seeding

    private func nextID(_ prefix: String) -> String {
        sequence += 1
        return "\(prefix)_\(sequence)"
    }

    private func seedParent() {
        let user = APIUser(
            id: "usr_randy", name: "Randy Cruz", firstName: "Randy", email: "randy@example.com",
            role: .familyAdmin, family: family,
            notifications: NotificationPrefs(notifyPush: true, notifyEmail: true, notifyApproval: true, weeklySummary: true),
            twoFactor: false, emailVerified: true, createdAt: Date.now.addingTimeInterval(-40 * 86400)
        )
        accounts[user.email] = Account(user: user, password: "ChangeMe123!")
        members = [
            FamilyMember(id: user.id, name: user.name, email: user.email, role: .familyAdmin, createdAt: user.createdAt, you: true),
            FamilyMember(id: "usr_ana", name: "Ana Cruz", email: "ana@example.com", role: .parent, createdAt: Date.now.addingTimeInterval(-30 * 86400), you: false),
        ]
    }

    private func seedFamily() {
        let mia = addChild(name: "Mia", age: 12, profile: "PROTECTED", hue: 205)
        let lucas = addChild(name: "Lucas", age: 9, profile: "PROTECTED", hue: 28)
        let sophie = addChild(name: "Sophie", age: 14, profile: "BALANCED", hue: 330)

        let miaPhone = addDevice(childId: mia.id, childName: "Mia", name: "Mia's iPhone", model: "iPhone 13", platform: .ios, kind: "PHONE", osVersion: "iOS 26.0", lastSeen: -600)
        _ = addDevice(childId: lucas.id, childName: "Lucas", name: "Galaxy A54", model: "SM-A546E", platform: .android, kind: "PHONE", osVersion: "Android 14", lastSeen: -3600)
        let sophiePhone = addDevice(childId: sophie.id, childName: "Sophie", name: "Sophie's iPhone", model: "iPhone 13", platform: .ios, kind: "PHONE", osVersion: "iOS 26.0", lastSeen: -30 * 3600)

        // Verified configurations, with a few gaps so the health score is not perfect.
        markAllVerified(childId: mia.id)
        markAllVerified(childId: lucas.id)
        markAllVerified(childId: sophie.id)
        setStatus(childId: mia.id, key: "LOCATION", status: .warning, message: "Sharing turned off on Mia's iPhone")
        setStatus(childId: sophie.id, key: "BEDTIME", status: .notConfigured, message: "Not configured on Sophie's iPhone")

        appsByChild[mia.id] = [
            app("YouTube", .allowed, limit: nil, today: 54),
            app("Roblox", .allowed, limit: 60, today: 42),
            app("Minecraft", .allowed, limit: 60, today: 18),
            app("Chrome", .allowed, limit: nil, today: 28),
            app("TikTok", .blocked, limit: nil, today: 0),
            app("Instagram", .pending, limit: nil, today: 0),
            app("Snapchat", .blocked, limit: nil, today: 0),
            app("Discord", .blocked, limit: nil, today: 0),
        ]
        appsByChild[lucas.id] = [app("Roblox", .allowed, limit: 60, today: 35), app("YouTube Kids", .alwaysAllowed, limit: nil, today: 20)]
        appsByChild[sophie.id] = [app("Instagram", .allowed, limit: 90, today: 61), app("Spotify", .alwaysAllowed, limit: nil, today: 40)]

        alertsList = [
            makeAlert(childId: sophie.id, deviceId: sophiePhone.id, severity: .attention, category: .protection, icon: "moon",
                      title: "Bedtime not configured", body: "No bedtime schedule is set on this device. Other protections are working.",
                      subject: "Sophie's iPhone", age: -2 * 3600,
                      action: AlertAction(type: "FIX_SETTING", label: "Set bedtime", childId: sophie.id, key: "BEDTIME", deviceId: nil)),
            makeAlert(childId: mia.id, deviceId: miaPhone.id, severity: .info, category: .apps, icon: "app-window",
                      title: "New app installed", body: "Roblox was installed on Mia's iPhone.", subject: "Mia's iPhone", age: -5 * 3600, dismissible: true,
                      action: AlertAction(type: "REVIEW_APPS", label: "Review apps", childId: mia.id, key: nil, deviceId: nil)),
            makeAlert(childId: mia.id, deviceId: miaPhone.id, severity: .attention, category: .location, icon: "map-pin",
                      title: "Location sharing turned off", body: "Mia's iPhone stopped sharing its location.", subject: "Mia's iPhone", age: -9 * 3600,
                      action: AlertAction(type: "FIX_SETTING", label: "Turn on sharing", childId: mia.id, key: "LOCATION", deviceId: nil)),
            makeAlert(childId: mia.id, deviceId: miaPhone.id, severity: .info, category: .screenTime, icon: "hourglass",
                      title: "Screen time limit reached", body: "Mia used today's 3 hours of screen time.", subject: "Mia's iPhone", age: -26 * 3600, dismissible: true, read: true,
                      action: AlertAction(type: "VIEW_SCREEN_TIME", label: "View screen time", childId: mia.id, key: nil, deviceId: nil)),
            makeAlert(childId: mia.id, deviceId: miaPhone.id, severity: .info, category: .apps, icon: "app-window",
                      title: "App blocked", body: "TikTok was blocked on Mia's iPhone.", subject: "Mia's iPhone", age: -29 * 3600, dismissible: true, read: true, action: nil),
        ]
    }

    @discardableResult
    private func addChild(name: String, age: Int, profile: String, hue: Int) -> ChildSummary {
        let id = nextID("child")
        let summary = ChildSummary(
            id: id, name: name, age: age, birthYear: Calendar.current.component(.year, from: .now) - age, hue: hue, photoUrl: nil,
            status: .notconfigured, health: HealthScore(score: 0, total: 10, label: nil),
            dailyLimitMinutes: nil, weekendLimitMinutes: nil, todayLimitMinutes: nil, todayMinutes: 0,
            deviceCount: 0, primaryDevice: nil
        )
        summaries.append(summary)
        protectionsByChild[id] = ProtectionKey.all.map { key in
            let config = ProtectionDefaults.config(key: key, age: age, profile: profile).setting("key", to: .string(key))
            return Protection(
                key: key, name: ProtectionKey.name(key), checkName: ProtectionKey.name(key), icon: ProtectionKey.icon(key),
                policy: config, policyLabel: ProtectionConfigFormatter.label(key: key, config: config),
                status: .notConfigured, openBatchId: nil, devices: []
            )
        }
        appsByChild[id] = []
        refreshSummary(id)
        return summary
    }

    private func addDevice(childId: String, childName: String, name: String, model: String, platform: DevicePlatformKind, kind: String, osVersion: String, lastSeen: TimeInterval) -> APIDevice {
        let seen = Date.now.addingTimeInterval(lastSeen)
        let device = APIDevice(
            id: nextID("dev"), childId: childId, childName: childName, name: name, model: model, kind: kind, platform: platform,
            osVersion: osVersion, appVersion: "1.0.0", battery: 72, isPrimary: (devicesByChild[childId] ?? []).isEmpty,
            lastSeenAt: seen, lastSeenLabel: seen.verifiedDescription(), state: lastSeen < -86400 ? .offline : .healthy, issues: 0
        )
        devicesByChild[childId, default: []].append(device)
        // Every protection now has a device entry with the platform's capability.
        protectionsByChild[childId] = (protectionsByChild[childId] ?? []).map { protection in
            var copy = protection
            copy.devices.append(ProtectionDevice(
                deviceId: device.id, deviceName: device.name, platform: platform,
                capability: Self.capability(key: protection.key, platform: platform),
                status: .notConfigured, reported: nil, reportedLabel: "Not configured",
                message: "Not configured on \(device.name)", lastVerifiedAt: nil, guide: nil
            ))
            // A protection no paired device can apply never counts against health.
            if copy.isUnsupportedEverywhere {
                copy.status = .unsupported
                copy.devices = copy.devices.map { entry in
                    var unsupported = entry
                    unsupported.status = .unsupported
                    unsupported.reportedLabel = "Not supported"
                    unsupported.message = "Not supported on \(entry.deviceName)"
                    return unsupported
                }
            }
            return copy
        }
        refreshSummary(childId)
        return device
    }

    static func capability(key: String, platform: DevicePlatformKind) -> Capability {
        guard platform == .ios else { return .available }
        switch key {
        case "WEB", "LOCATION": return .guided
        case "DOWNLOADS": return .verifyOnly
        case "NOTIFICATIONS": return .unsupported
        default: return .available
        }
    }

    private func markAllVerified(childId: String) {
        for key in ProtectionKey.all {
            setStatus(childId: childId, key: key, status: .pass, message: "Verified with the device")
        }
    }

    private func setStatus(childId: String, key: String, status: CheckStatus, message: String) {
        guard var list = protectionsByChild[childId], let index = list.firstIndex(where: { $0.key == key }) else { return }
        list[index].status = list[index].isUnsupportedEverywhere ? .unsupported : status
        list[index].devices = list[index].devices.map { device in
            var copy = device
            let unsupported = device.capability == .unsupported
            copy.status = unsupported ? .unsupported : status
            copy.reported = status == .pass ? list[index].policy : nil
            copy.reportedLabel = unsupported ? "Not supported" : (status == .pass ? list[index].policyLabel : status.title)
            copy.message = unsupported ? "Not supported on \(device.deviceName)" : message
            copy.lastVerifiedAt = status == .pass ? .now : nil
            return copy
        }
        protectionsByChild[childId] = list
        refreshSummary(childId)
    }

    private func app(_ name: String, _ approval: AppApproval, limit: Int?, today: Int) -> ChildApp {
        ChildApp(
            id: nextID("app"), name: name, approval: approval, approvalLabel: approval.title,
            allowed: approval != .blocked && approval != .pending, dailyLimitMinutes: limit,
            todayMinutes: today, installedAt: Date.now.addingTimeInterval(-3 * 86400)
        )
    }

    private func makeAlert(childId: String?, deviceId: String?, severity: AlertSeverity, category: APIAlertCategory, icon: String, title: String, body: String, subject: String?, age: TimeInterval, dismissible: Bool = false, read: Bool = false, action: AlertAction?) -> APIAlert {
        let date = Date.now.addingTimeInterval(age)
        return APIAlert(
            id: nextID("alert"), childId: childId, deviceId: deviceId, severity: severity, category: category, icon: icon,
            title: title, body: body, subject: subject, fromValue: nil, toValue: nil, read: read, resolved: false,
            dismissible: dismissible, createdAt: date, timeLabel: date.verifiedDescription(), day: Self.dayGroup(date), action: action
        )
    }

    static func dayGroup(_ date: Date) -> DayGroup {
        DayGroup(key: date.formatted(.iso8601.year().month().day()), label: date.dayGroupTitle())
    }

    // MARK: Derived state

    private func refreshSummary(_ childId: String) {
        guard let index = summaries.firstIndex(where: { $0.id == childId }) else { return }
        let devices = devicesByChild[childId] ?? []
        let health = healthScore(childId: childId)
        let screenTime = protectionsByChild[childId]?.first { $0.key == "SCREEN_TIME" }?.policy
        var summary = summaries[index]
        summary.deviceCount = devices.count
        summary.primaryDevice = devices.first.map { PrimaryDevice(id: $0.id, name: $0.name, platform: $0.platform) }
        summary.health = health
        summary.status = devices.isEmpty ? .notconfigured : (health.score == health.total ? .protected : .attention)
        summary.dailyLimitMinutes = screenTime?["dailyMinutes"]?.intValue
        summary.weekendLimitMinutes = screenTime?["weekendMinutes"]?.intValue
        summary.todayLimitMinutes = Calendar.current.isDateInWeekend(.now) ? summary.weekendLimitMinutes : summary.dailyLimitMinutes
        summary.todayMinutes = devices.isEmpty ? 0 : 134
        summaries[index] = summary
        devicesByChild[childId] = devices.map { device in
            var copy = device
            copy.issues = (protectionsByChild[childId] ?? []).filter { $0.status.needsAttention }.count
            copy.state = copy.lastSeenAt.map { $0 < Date.now.addingTimeInterval(-86400) } == true ? .offline : (copy.issues > 0 ? .issues : .healthy)
            return copy
        }
    }

    private func healthScore(childId: String) -> HealthScore {
        let protections = protectionsByChild[childId] ?? []
        let evaluated = protections.filter { $0.status != .unsupported }
        let passed = evaluated.filter { $0.status == .pass }.count
        var score = HealthScore(score: passed, total: evaluated.count, label: nil)
        score.label = score.grade
        return score
    }

    private func checks(childId: String) -> [HealthCheck] {
        (protectionsByChild[childId] ?? []).map { protection in
            let device = protection.devices.first { $0.status.needsAttention }
            return HealthCheck(
                key: protection.key, name: protection.name, icon: protection.icon, status: protection.status,
                detail: device?.message ?? (protection.status == .pass ? "Verified on \(protection.devices.count) of \(protection.devices.count) devices" : "No device paired yet"),
                fixDeviceId: device?.deviceId, fixChildId: protection.status.needsAttention ? childId : nil
            )
        }
    }

    private func requireUser() throws -> APIUser {
        guard let currentUser else { throw APIError.server(status: 401, code: "unauthorized", message: "Your session has ended. Please sign in again.") }
        return currentUser
    }

    private func requireChild(_ id: String) throws -> Int {
        guard let index = summaries.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(status: 404, code: "not_found", message: "That child couldn't be found.")
        }
        return index
    }

    private func gate() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    // MARK: Public

    func appInfo() async throws -> AppInfo {
        try gate()
        return appInfoValue
    }

    func help(query: String?, category: String?) async throws -> HelpIndex {
        try gate()
        let all = Self.helpArticles
        let filtered = all.filter { article in
            (category == nil || article.category == category)
                && (query?.isEmpty != false || query!.lowercased().split(separator: " ").allSatisfy { word in
                    article.title.lowercased().contains(word) || article.summary.lowercased().contains(word)
                        || article.body.joined(separator: " ").lowercased().contains(word)
                })
        }
        return HelpIndex(
            categories: [
                HelpCategory(id: "SETUP", name: "Setup Guides", description: "Step-by-step instructions", icon: "book-open"),
                HelpCategory(id: "TROUBLESHOOTING", name: "Troubleshooting", description: "Common solutions", icon: "wrench"),
                HelpCategory(id: "PRIVACY", name: "Privacy & Security", description: "How we protect your data", icon: "lock"),
                HelpCategory(id: "FAQ", name: "FAQs", description: "Frequently asked questions", icon: "help-circle"),
            ],
            articles: filtered.map { HelpArticleSummary(slug: $0.slug, category: $0.category, title: $0.title, summary: $0.summary) },
            contact: HelpContact(email: "support@devcomdigital.com", replyTime: "Replies within 1 business day")
        )
    }

    func helpArticle(slug: String) async throws -> HelpArticle {
        try gate()
        guard let article = Self.helpArticles.first(where: { $0.slug == slug }) else {
            throw APIError.server(status: 404, code: "not_found", message: "That article couldn't be found.")
        }
        return article
    }

    private static let helpArticles: [HelpArticle] = [
        HelpArticle(slug: "ios-family-sharing", category: "SETUP", title: "Set up supervision on iPhone", summary: "Pair your child's iPhone with a code and finish Screen Time in Settings.",
                    body: ["Open eGuard on your child's iPhone and enter the 8-character pairing code shown in your app.", "Some protections, like web filtering and location sharing, are finished in Settings. eGuard shows the exact steps and verifies them afterwards."]),
        HelpArticle(slug: "android-family-link", category: "SETUP", title: "Set up supervision on Android", summary: "Pair an Android phone so eGuard can apply protections directly.",
                    body: ["Install eGuard on the Android device, enter the pairing code, and grant the permissions it requests.", "eGuard applies every protection automatically and reports back within a few minutes."]),
        HelpArticle(slug: "device-offline", category: "TROUBLESHOOTING", title: "A device shows as offline", summary: "Settings stay active, but eGuard can't verify them until the device reconnects.",
                    body: ["A device is offline when it hasn't synced for more than a day. Check that it's charged, connected to the internet, and that eGuard isn't restricted by battery saver.", "Once the device reconnects, eGuard verifies every protection again automatically."]),
        HelpArticle(slug: "guided-setup", category: "TROUBLESHOOTING", title: "A setting says \"Finish on the device\"", summary: "Apple requires some settings to be changed in Settings on the child's iPhone.",
                    body: ["Follow the steps shown in eGuard on the child's iPhone, then tap \"I've done this, verify now\".", "eGuard asks the device for a fresh report and marks the setting verified when it matches."]),
        HelpArticle(slug: "data-privacy", category: "PRIVACY", title: "What eGuard stores", summary: "Configuration, verification results, and optional location history.",
                    body: ["eGuard stores the protections you chose and what each device reports about them.", "Location history is off unless the family admin turns it on, and it is deleted when turned off."]),
        HelpArticle(slug: "faq-multiple-children", category: "FAQ", title: "Can I protect more than one child?", summary: "Yes. Add each child and pair their devices.",
                    body: ["Every child gets their own profile, protections, and devices.", "Your plan's device limit is shown on the Your plan screen in Settings."]),
    ]

    // MARK: Auth

    func register(name: String, email: String, password: String, familyName: String?) async throws -> AuthResponse {
        try gate()
        let normalized = AccountValidator.normalizedEmail(email)
        if accounts[normalized] != nil {
            throw APIError.server(status: 409, code: "conflict", message: "That email already has an eGuard account. Sign in instead.")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        let user = APIUser(
            id: nextID("usr"), name: trimmed, firstName: first, email: normalized, role: .familyAdmin,
            family: FamilyRef(id: nextID("fam"), name: familyName ?? "\(first)'s Family", timezone: TimeZone.current.identifier),
            notifications: NotificationPrefs(notifyPush: true, notifyEmail: true, notifyApproval: true, weeklySummary: false),
            twoFactor: false, emailVerified: false, createdAt: .now
        )
        accounts[normalized] = Account(user: user, password: password)
        currentUser = user
        members = [FamilyMember(id: user.id, name: user.name, email: user.email, role: .familyAdmin, createdAt: .now, you: true)]
        summaries = []
        alertsList = []
        return AuthResponse(token: "mock-token-\(user.id)", expiresAt: Date.now.addingTimeInterval(30 * 86400), user: user, isNew: true)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try gate()
        guard let account = accounts[AccountValidator.normalizedEmail(email)], account.password == password else {
            throw APIError.server(status: 401, code: "invalid_credentials", message: "That email and password don't match an eGuard account.")
        }
        currentUser = account.user
        return AuthResponse(token: "mock-token-\(account.user.id)", expiresAt: Date.now.addingTimeInterval(30 * 86400), user: account.user, isNew: false)
    }

    func social(provider: SocialProvider, idToken: String, name: String?, guardian: Bool) async throws -> AuthResponse {
        try gate()
        guard appInfoValue.signIn.apple || provider != .apple else {
            throw APIError.server(status: 501, code: "provider_not_configured", message: "Apple sign-in isn't enabled on this server.")
        }
        let email = "\(provider.rawValue)-\(idToken.prefix(6).lowercased())@privaterelay.example"
        if let account = accounts[email] {
            currentUser = account.user
            return AuthResponse(token: "mock-token-\(account.user.id)", expiresAt: Date.now.addingTimeInterval(30 * 86400), user: account.user, isNew: false)
        }
        guard guardian else { throw APIError.server(status: 400, code: "guardian_required", message: "Confirm you're a parent or legal guardian, 18 or older.") }
        var response = try await register(name: name?.isEmpty == false ? name! : "Parent", email: email, password: UUID().uuidString, familyName: nil)
        response.user.emailVerified = true
        accounts[email]?.user.emailVerified = true
        currentUser = response.user
        return response
    }

    func logout(pushToken: String?) async throws {
        try gate()
        if let pushToken { pushTokens.remove(pushToken) }
        currentUser = nil
    }

    // MARK: Me

    func me() async throws -> APIUser {
        try gate()
        return try requireUser()
    }

    func updateMe(name: String?, email: String?, timezone: String?) async throws -> APIUser {
        try gate()
        var user = try requireUser()
        if let name { user.name = name; user.firstName = name.split(separator: " ").first.map(String.init) ?? name }
        if let email {
            let normalized = AccountValidator.normalizedEmail(email)
            if normalized != user.email, accounts[normalized] != nil {
                throw APIError.server(status: 409, code: "conflict", message: "That email is already in use.")
            }
            let account = accounts.removeValue(forKey: user.email)
            user.email = normalized
            user.emailVerified = false
            accounts[normalized] = Account(user: user, password: account?.password ?? "")
        } else {
            accounts[user.email]?.user = user
        }
        if let timezone, user.isAdmin { user.family.timezone = timezone }
        accounts[user.email]?.user = user
        currentUser = user
        return user
    }

    func changePassword(current: String, next: String) async throws -> OKResponse {
        try gate()
        let user = try requireUser()
        guard accounts[user.email]?.password == current else {
            throw APIError.server(status: 403, code: "wrong_password", message: "That password doesn't match your current password.")
        }
        guard next.count >= 10 else { throw APIError.server(status: 400, code: "invalid", message: "next: Use at least 10 characters.") }
        accounts[user.email]?.password = next
        return OKResponse(ok: true, message: "Your password was changed. Other devices were signed out.")
    }

    func resendVerification() async throws -> VerificationSend {
        try gate()
        let user = try requireUser()
        return VerificationSend(sent: !user.isEmailVerified, email: user.email)
    }

    func notificationPrefs() async throws -> NotificationPrefs {
        try gate()
        return try requireUser().notifications
    }

    func updateNotificationPrefs(_ patch: NotificationPrefsPatch) async throws -> NotificationPrefs {
        try gate()
        var user = try requireUser()
        if let value = patch.notifyPush { user.notifications.notifyPush = value }
        if let value = patch.notifyEmail { user.notifications.notifyEmail = value }
        if let value = patch.notifyApproval { user.notifications.notifyApproval = value }
        if let value = patch.weeklySummary { user.notifications.weeklySummary = value }
        currentUser = user
        accounts[user.email]?.user = user
        return user.notifications
    }

    func registerPushToken(_ token: String) async throws {
        try gate()
        _ = try requireUser()
        pushTokens.insert(token)
    }

    func deletePushToken(_ token: String) async throws {
        try gate()
        pushTokens.remove(token)
    }

    func sessions() async throws -> [SessionInfo] {
        try gate()
        _ = try requireUser()
        return [
            SessionInfo(id: "sess_1", userAgent: APIClient.userAgent, createdAt: Date.now.addingTimeInterval(-3600), lastSeenAt: .now, current: true),
            SessionInfo(id: "sess_2", userAgent: "Safari on macOS", createdAt: Date.now.addingTimeInterval(-5 * 86400), lastSeenAt: Date.now.addingTimeInterval(-86400), current: false),
        ]
    }

    func signOutOtherSessions() async throws -> Int {
        try gate()
        _ = try requireUser()
        return 1
    }

    // MARK: Dashboard and health

    func dashboard() async throws -> Dashboard {
        try gate()
        if let error = nextDashboardError {
            nextDashboardError = nil
            throw error
        }
        let user = try requireUser()
        let attention = summaries.filter { $0.status == .attention }.count
        let summary: String
        if summaries.isEmpty {
            summary = "Add your first child to get started."
        } else if attention == 0 {
            summary = "Your family's digital safety looks good today."
        } else {
            summary = attention == 1 ? "1 child needs attention." : "\(attention) children need attention."
        }
        let health = familyHealth()
        return Dashboard(
            user: user, greeting: "\(Date.now.greeting()),", summary: summary, health: health,
            children: summaries, deviceCount: devicesByChild.values.reduce(0) { $0 + $1.count },
            recentAlerts: Array(alertsList.filter { !$0.resolved }.prefix(3)), unreadAlerts: unread()
        )
    }

    private func familyHealth() -> HealthScore {
        let scores = summaries.map(\.health)
        guard !scores.isEmpty else { return HealthScore(score: 0, total: 10, label: "Not configured") }
        // Family score: the average per protection across children, rounded down.
        let score = scores.map(\.score).reduce(0, +) / scores.count
        var health = HealthScore(score: score, total: 10, label: nil)
        health.label = health.grade
        return health
    }

    func health(childId: String?) async throws -> HealthReport {
        try gate()
        _ = try requireUser()
        let ids = childId.map { [$0] } ?? summaries.map(\.id)
        for id in ids { _ = try requireChild(id) }
        // Each check shows the least healthy child's status.
        let combinedChecks = ProtectionKey.all.map { key -> HealthCheck in
            let all = ids.flatMap { id in self.checks(childId: id).filter { $0.key == key } }
            return all.min { rank($0.status) < rank($1.status) } ?? HealthCheck(key: key, name: ProtectionKey.name(key), icon: ProtectionKey.icon(key), status: .notConfigured, detail: "No device paired yet", fixDeviceId: nil, fixChildId: nil)
        }
        let toFix = ids.flatMap { id in
            self.checks(childId: id).filter { $0.status.needsAttention }.map { check in
                FixItem(key: check.key, name: check.name, status: check.status, detail: check.detail, childId: id, deviceId: check.fixDeviceId)
            }
        }
        let health = childId.map { healthScore(childId: $0) } ?? familyHealth()
        return HealthReport(
            score: health.score, total: health.total, label: health.grade, checks: combinedChecks, toFix: toFix,
            children: childId == nil ? summaries.map { ChildHealth(id: $0.id, name: $0.name, score: $0.health.score, total: $0.health.total, status: $0.status) } : nil
        )
    }

    private func rank(_ status: CheckStatus) -> Int {
        switch status {
        case .actionRequired: 0
        case .notConfigured: 1
        case .warning: 2
        case .pass: 3
        case .unsupported: 4
        }
    }

    // MARK: Onboarding

    func profiles(age: Int) async throws -> [ProfileOption] {
        try gate()
        return [
            ProfileOption(id: "BALANCED", name: "Balanced", description: "Moderate limits for independent kids", icon: "scale", recommended: age >= 13),
            ProfileOption(id: "PROTECTED", name: "Protected", description: "Stronger controls for younger children", icon: "shield-check", recommended: age < 13),
            ProfileOption(id: "CUSTOM", name: "Custom", description: "Choose settings yourself", icon: "sliders-horizontal", recommended: false),
        ]
    }

    func recommendations(childId: String, profile: String?) async throws -> Recommendations {
        try gate()
        let child = summaries[try requireChild(childId)]
        let chosen = profile ?? (child.age < 13 ? "PROTECTED" : "BALANCED")
        let devices = devicesByChild[childId] ?? []
        return Recommendations(childId: childId, age: child.age, profile: chosen, settings: ProtectionKey.all.map { key in
            let config = ProtectionDefaults.config(key: key, age: child.age, profile: chosen).setting("key", to: .string(key))
            return RecommendedSetting(
                key: key, name: ProtectionKey.name(key), icon: ProtectionKey.icon(key), config: config,
                label: ProtectionConfigFormatter.label(key: key, config: config),
                devices: devices.map { RecommendedDevice(deviceId: $0.id, deviceName: $0.name, capability: Self.capability(key: key, platform: $0.platform), capabilityLabel: Self.capability(key: key, platform: $0.platform).title) }
            )
        })
    }

    func setup(childId: String, profile: String, overrides: [JSONValue]) async throws -> SetupResponse {
        try gate()
        let child = summaries[try requireChild(childId)]
        var requested: [String] = []
        var saved: [String] = []
        var configs: [(String, JSONValue)] = []
        for key in ProtectionKey.all {
            let override = overrides.first { $0["key"]?.stringValue == key }
            let config = (override ?? ProtectionDefaults.config(key: key, age: child.age, profile: profile)).setting("key", to: .string(key))
            configs.append((key, config))
            storePolicy(childId: childId, key: key, config: config)
            let supported = (devicesByChild[childId] ?? []).contains { Self.capability(key: key, platform: $0.platform) != .unsupported }
            if supported { requested.append(key) } else { saved.append(key) }
        }
        guard !requested.isEmpty else {
            return SetupResponse(batchId: nil, requested: [], saved: saved, progress: nil)
        }
        let batch = makeBatch(childId: childId, configs: configs.filter { requested.contains($0.0) })
        return SetupResponse(batchId: batch.batchId, requested: requested, saved: saved, progress: batch)
    }

    func pairingCode(childId: String) async throws -> PairingCode {
        try gate()
        let user = try requireUser()
        let child = summaries[try requireChild(childId)]
        guard user.isEmailVerified else {
            throw APIError.server(status: 403, code: "email_unverified", message: "Verify your email before pairing a device. We sent you a link.")
        }
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<8).map { _ in letters.randomElement()! })
        return PairingCode(code: code, expiresAt: Date.now.addingTimeInterval(15 * 60), childName: child.name)
    }

    /// Lets previews and tests simulate the child's device pairing.
    func simulatePairing(childId: String, platform: DevicePlatformKind = .ios) {
        guard let child = summaries.first(where: { $0.id == childId }) else { return }
        _ = addDevice(childId: childId, childName: child.name, name: "\(child.name)'s \(platform == .ios ? "iPhone" : "Android")", model: platform == .ios ? "iPhone 13" : "SM-A546E", platform: platform, kind: "PHONE", osVersion: platform == .ios ? "iOS 26.0" : "Android 14", lastSeen: -30)
    }

    private func storePolicy(childId: String, key: String, config: JSONValue) {
        guard var list = protectionsByChild[childId], let index = list.firstIndex(where: { $0.key == key }) else { return }
        list[index].policy = config
        list[index].policyLabel = ProtectionConfigFormatter.label(key: key, config: config)
        protectionsByChild[childId] = list
    }

    // MARK: Children

    func children() async throws -> [ChildSummary] {
        try gate()
        _ = try requireUser()
        return summaries
    }

    func createChild(name: String, age: Int, profile: String?) async throws -> ChildSummary {
        try gate()
        _ = try requireUser()
        guard (1...40).contains(name.trimmingCharacters(in: .whitespaces).count) else {
            throw APIError.server(status: 400, code: "invalid", message: "name: Enter a name between 1 and 40 characters.")
        }
        guard (0...17).contains(age) else { throw APIError.server(status: 400, code: "invalid", message: "age: Enter an age from 0 to 17.") }
        return addChild(name: name.trimmingCharacters(in: .whitespaces), age: age, profile: profile ?? "PROTECTED", hue: [205, 28, 330, 140][summaries.count % 4])
    }

    func child(id: String) async throws -> ChildDetail {
        try gate()
        _ = try requireUser()
        let summary = summaries[try requireChild(id)]
        let protections = protectionsByChild[id] ?? []
        let bedtime = protections.first { $0.key == "BEDTIME" }
        let location = protections.first { $0.key == "LOCATION" }
        let sharing = location?.policy["sharing"]?.boolValue == true && location?.status == .pass
        let devices = devicesByChild[id] ?? []
        let health = healthScore(id: id)
        let apps = appsByChild[id] ?? []
        return ChildDetail(
            child: summary,
            health: HealthReport(score: health.score, total: health.total, label: health.grade, checks: checks(childId: id), toFix: nil, children: nil),
            today: TodaySummary(minutes: summary.todayMinutes ?? 0, limitMinutes: summary.todayLimitMinutes, appsUsed: apps.filter { ($0.todayMinutes ?? 0) > 0 }.count,
                                topApps: apps.filter { ($0.todayMinutes ?? 0) > 0 }.sorted { ($0.todayMinutes ?? 0) > ($1.todayMinutes ?? 0) }.prefix(3).map { TopApp(name: $0.name, minutes: $0.todayMinutes ?? 0) }),
            bedtime: bedtime.map { BedtimeInfo(enabled: $0.policy["enabled"]?.boolValue ?? false, start: $0.policy["start"]?.stringValue ?? "21:30", end: $0.policy["end"]?.stringValue ?? "06:00", days: $0.policy["days"]?.stringValue ?? "EVERY_DAY", label: $0.policyLabel) },
            location: LocationInfo(sharing: sharing, placeLabel: sharing ? "Home" : nil, updatedAt: sharing ? Date.now.addingTimeInterval(-120) : nil, label: devices.isEmpty ? "Waiting for location" : (sharing ? "Sharing enabled" : "Sharing off")),
            deviceProtection: DeviceProtectionInfo(state: devices.isEmpty ? "no_devices" : (devices.first?.state.rawValue ?? "healthy"), label: devices.isEmpty ? "No devices" : (devices.first?.state.title ?? "Healthy")),
            pendingApprovals: apps.filter { $0.approval == .pending }.count,
            devices: devices,
            recentChanges: devices.isEmpty ? [] : [
                ChangeRecord(id: nextID("chg"), key: "BEDTIME", title: "Bedtime changed", actor: "Randy Cruz on iOS app", fromValue: "9:30 PM – 6:00 AM", toValue: bedtime?.policyLabel, createdAt: Date.now.addingTimeInterval(-2 * 86400), timeLabel: Date.now.addingTimeInterval(-2 * 86400).verifiedDescription()),
            ]
        )
    }

    private func healthScore(id: String) -> HealthScore { healthScore(childId: id) }

    func updateChild(id: String, name: String?, age: Int?) async throws -> ChildDetail {
        try gate()
        let index = try requireChild(id)
        if let name { summaries[index].name = name }
        if let age { summaries[index].age = age }
        return try await child(id: id)
    }

    func deleteChild(id: String, password: String) async throws {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can delete a child.") }
        guard accounts[user.email]?.password == password else { throw APIError.server(status: 403, code: "wrong_password", message: "That password doesn't match your current password.") }
        let index = try requireChild(id)
        summaries.remove(at: index)
        devicesByChild[id] = nil
        protectionsByChild[id] = nil
        appsByChild[id] = nil
        alertsList.removeAll { $0.childId == id }
    }

    func uploadPhoto(childId: String, data: Data, contentType: String) async throws -> String {
        try gate()
        let index = try requireChild(childId)
        guard data.count <= 2_000_000 else { throw APIError.server(status: 413, code: "too_large", message: "Choose a photo under 2 MB.") }
        photos[childId] = data
        let url = "/api/mobile/v1/children/\(childId)/photo?v=\(Int(Date.now.timeIntervalSince1970))"
        summaries[index].photoUrl = url
        return url
    }

    func photo(childId: String, url: String) async throws -> Data {
        try gate()
        guard let data = photos[childId] else { throw APIError.server(status: 404, code: "not_found", message: "No photo.") }
        return data
    }

    func deletePhoto(childId: String) async throws {
        try gate()
        let index = try requireChild(childId)
        photos[childId] = nil
        summaries[index].photoUrl = nil
    }

    func history(childId: String, before: Date?) async throws -> HistoryPage {
        try gate()
        let detail = try await child(id: childId)
        return HistoryPage(changes: before == nil ? detail.recentChanges : [], nextBefore: nil)
    }

    // MARK: Protections and batches

    func protections(childId: String) async throws -> [Protection] {
        try gate()
        _ = try requireChild(childId)
        return protectionsByChild[childId] ?? []
    }

    func updateProtection(childId: String, key: String, config: JSONValue) async throws -> Batch {
        try gate()
        _ = try requireChild(childId)
        let upper = key.uppercased()
        guard let protection = protectionsByChild[childId]?.first(where: { $0.key == upper }) else {
            throw APIError.server(status: 404, code: "not_found", message: "Unknown protection.")
        }
        guard !protection.isUnsupportedEverywhere, !protection.devices.isEmpty else {
            throw APIError.server(status: 409, code: "unsupported", message: "None of \(summaries.first { $0.id == childId }?.name ?? "the child")'s devices support this protection.")
        }
        let full = config.setting("key", to: .string(upper))
        storePolicy(childId: childId, key: upper, config: full)
        return makeBatch(childId: childId, configs: [(upper, full)])
    }

    private func makeBatch(childId: String, configs: [(String, JSONValue)]) -> Batch {
        let id = UUID().uuidString.lowercased()
        let devices = devicesByChild[childId] ?? []
        let items = configs.map { key, config -> BatchItem in
            let deviceEntries = devices.compactMap { device -> BatchDevice? in
                let capability = Self.capability(key: key, platform: device.platform)
                guard capability != .unsupported else { return nil }
                let guided = capability != .available
                return BatchDevice(
                    requestId: nextID("req"), deviceId: device.id, deviceName: device.name, platform: device.platform,
                    mode: guided ? "GUIDED" : "APPLY", status: guided ? .awaitingParent : .pending, failureReason: nil,
                    offline: device.state == .offline, from: protectionsByChild[childId]?.first { $0.key == key }?.devices.first { $0.deviceId == device.id }?.reportedLabel,
                    guide: guided ? Self.guide(for: key) : nil
                )
            }
            return BatchItem(key: key, name: ProtectionKey.name(key), icon: ProtectionKey.icon(key), status: deviceEntries.contains { $0.status == .awaitingParent } ? .awaitingParent : .pending,
                             to: ProtectionConfigFormatter.label(key: key, config: config), devices: deviceEntries)
        }
        var batch = Batch(batchId: id, childId: childId, done: false, summary: Self.summary(items), items: items, health: healthScore(childId: childId), confirmed: nil)
        for index in batch.items.indices { markOpen(childId: childId, key: batch.items[index].key, batchId: id) }
        batch.summary = Self.summary(items)
        batches[id] = batch
        batchPolls[id] = 0
        return batch
    }

    private func markOpen(childId: String, key: String, batchId: String?) {
        guard var list = protectionsByChild[childId], let index = list.firstIndex(where: { $0.key == key }) else { return }
        list[index].openBatchId = batchId
        protectionsByChild[childId] = list
    }

    static func guide(for key: String) -> [String] {
        switch key {
        case "WEB": ["Open Settings, tap Screen Time, then Content & Privacy Restrictions.", "Tap App Store, Media, Web & Games, then Web Content.", "Choose Limit Adult Websites."]
        case "LOCATION": ["Open Settings, tap Privacy & Security, then Location Services.", "Tap eGuard and choose Always.", "Turn on Precise Location."]
        case "DOWNLOADS": ["Open Settings, tap Family, then your child's name.", "Tap Ask to Buy and turn on Require Purchase Approval."]
        default: ["Open Settings on the child's device and follow the on-screen steps."]
        }
    }

    private static func summary(_ items: [BatchItem]) -> BatchSummary {
        let requests = items.flatMap(\.devices)
        return BatchSummary(
            total: requests.count,
            verified: requests.filter { $0.status == .verified }.count,
            failed: requests.filter { $0.status == .failed }.count,
            awaitingParent: requests.filter { $0.status == .awaitingParent }.count,
            inProgress: requests.filter { $0.status == .pending || $0.status == .delivered }.count,
            cancelled: requests.filter { $0.status == .cancelled }.count
        )
    }

    func batch(id: String) async throws -> Batch {
        try gate()
        guard var batch = batches[id] else { throw APIError.server(status: 404, code: "not_found", message: "That change couldn't be found.") }
        let polls = (batchPolls[id] ?? 0) + 1
        batchPolls[id] = polls
        // Automatic requests advance one step per poll; offline devices never do.
        for itemIndex in batch.items.indices {
            for deviceIndex in batch.items[itemIndex].devices.indices {
                var device = batch.items[itemIndex].devices[deviceIndex]
                guard !device.offline else { continue }
                switch device.status {
                case .pending: device.status = .delivered
                case .delivered where polls >= pollsUntilVerified: device.status = .verified
                default: break
                }
                batch.items[itemIndex].devices[deviceIndex] = device
            }
            batch.items[itemIndex].status = Self.leastFinished(batch.items[itemIndex].devices)
            if batch.items[itemIndex].status == .verified {
                setStatus(childId: batch.childId, key: batch.items[itemIndex].key, status: .pass, message: "Verified with the device")
                markOpen(childId: batch.childId, key: batch.items[itemIndex].key, batchId: nil)
            }
        }
        batch.summary = Self.summary(batch.items)
        batch.done = batch.items.allSatisfy { $0.status.isFinished }
        batch.health = healthScore(childId: batch.childId)
        batches[id] = batch
        if batch.done { alertsList = alertsList.map { alert in
            var copy = alert
            if let key = alert.action?.key, alert.childId == batch.childId, batch.items.contains(where: { $0.key == key && $0.status == .verified }) { copy.resolved = true }
            return copy
        } }
        return batch
    }

    private static func leastFinished(_ devices: [BatchDevice]) -> RequestStatus {
        let order: [RequestStatus] = [.failed, .awaitingParent, .pending, .delivered, .cancelled, .verified]
        return order.first { status in devices.contains { $0.status == status } } ?? .verified
    }

    func confirmBatch(id: String) async throws -> Batch {
        try gate()
        guard var batch = batches[id] else { throw APIError.server(status: 404, code: "not_found", message: "That change couldn't be found.") }
        var confirmed = 0
        for itemIndex in batch.items.indices {
            for deviceIndex in batch.items[itemIndex].devices.indices where batch.items[itemIndex].devices[deviceIndex].status == .awaitingParent {
                batch.items[itemIndex].devices[deviceIndex].status = .delivered
                confirmed += 1
            }
            batch.items[itemIndex].status = Self.leastFinished(batch.items[itemIndex].devices)
        }
        batch.summary = Self.summary(batch.items)
        batch.confirmed = confirmed
        batches[id] = batch
        batchPolls[id] = max(batchPolls[id] ?? 0, pollsUntilVerified - 1)
        return batch
    }

    func cancelBatch(id: String) async throws -> Int {
        try gate()
        guard var batch = batches[id] else { throw APIError.server(status: 404, code: "not_found", message: "That change couldn't be found.") }
        var cancelled = 0
        for itemIndex in batch.items.indices {
            for deviceIndex in batch.items[itemIndex].devices.indices where !batch.items[itemIndex].devices[deviceIndex].status.isFinished {
                batch.items[itemIndex].devices[deviceIndex].status = .cancelled
                cancelled += 1
            }
            batch.items[itemIndex].status = Self.leastFinished(batch.items[itemIndex].devices)
            markOpen(childId: batch.childId, key: batch.items[itemIndex].key, batchId: nil)
        }
        batch.done = true
        batch.summary = Self.summary(batch.items)
        batches[id] = batch
        return cancelled
    }

    // MARK: Activity

    func screenTime(childId: String, period: ScreenTimePeriod) async throws -> ScreenTimeReport {
        try gate()
        let summary = summaries[try requireChild(childId)]
        let hasDevice = summary.deviceCount > 0
        let limit = summary.todayLimitMinutes
        let apps = (appsByChild[childId] ?? []).filter { ($0.todayMinutes ?? 0) > 0 }.sorted { ($0.todayMinutes ?? 0) > ($1.todayMinutes ?? 0) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int, minutes: Int) -> DayMinutes {
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return DayMinutes(date: date.formatted(.iso8601.year().month().day()), minutes: hasDevice ? minutes : 0, limitMinutes: calendar.isDateInWeekend(date) ? summary.weekendLimitMinutes : summary.dailyLimitMinutes)
        }
        switch period {
        case .today:
            let hourly = [0, 0, 0, 0, 0, 0, 0, 7, 7, 7, 7, 7, 3, 3, 3, 3, 12, 12, 12, 27, 12, 12, 0, 0]
            return ScreenTimeReport(period: "today", from: day(0, minutes: 0).date, to: day(0, minutes: 0).date, totalMinutes: hasDevice ? 134 : 0, averageMinutes: hasDevice ? 134 : 0,
                                    previousAverageMinutes: hasDevice ? 152 : nil, limitMinutes: limit, days: [day(0, minutes: 134)], hourly: hasDevice ? hourly : nil,
                                    apps: apps.map { AppUsage(name: $0.name, minutes: $0.todayMinutes ?? 0, appId: $0.id, approval: $0.approval, dailyLimitMinutes: $0.dailyLimitMinutes) })
        case .week, .month:
            let count = period == .week ? 7 : 30
            let pattern = [134, 168, 95, 201, 143, 176, 122, 158, 110, 189]
            let days = (0..<count).reversed().map { day($0, minutes: pattern[$0 % pattern.count]) }
            let total = days.reduce(0) { $0 + $1.minutes }
            return ScreenTimeReport(period: period.rawValue, from: days.first?.date ?? "", to: days.last?.date ?? "", totalMinutes: total, averageMinutes: total / count,
                                    previousAverageMinutes: hasDevice ? 172 : nil, limitMinutes: summary.dailyLimitMinutes, days: days, hourly: nil,
                                    apps: apps.map { AppUsage(name: $0.name, minutes: ($0.todayMinutes ?? 0) * count / 2, appId: $0.id, approval: $0.approval, dailyLimitMinutes: $0.dailyLimitMinutes) })
        }
    }

    func apps(childId: String, filter: AppsFilter?) async throws -> AppsResponse {
        try gate()
        _ = try requireChild(childId)
        let all = appsByChild[childId] ?? []
        let counts = AppCounts(all: all.count, blocked: all.filter { $0.approval == .blocked }.count, pending: all.filter { $0.approval == .pending }.count, installed: all.filter { $0.approval != .blocked }.count)
        let filtered: [ChildApp]
        switch filter {
        case .installed: filtered = all.filter { $0.approval != .blocked }
        case .blocked: filtered = all.filter { $0.approval == .blocked }
        case .pending: filtered = all.filter { $0.approval == .pending }
        case nil: filtered = all
        }
        return AppsResponse(counts: counts, apps: filtered)
    }

    func updateApp(id: String, patch: AppPatch) async throws -> AppRuleUpdate {
        try gate()
        for (childId, apps) in appsByChild {
            guard let index = apps.firstIndex(where: { $0.id == id }) else { continue }
            var app = apps[index]
            if let approval = patch.approval {
                app.approval = approval
                app.approvalLabel = approval.title
                app.allowed = approval != .blocked && approval != .pending
                alertsList = alertsList.map { alert in
                    var copy = alert
                    if alert.action?.type == "REVIEW_APPS", alert.childId == childId { copy.resolved = true }
                    return copy
                }
            }
            if patch.removeLimit { app.dailyLimitMinutes = nil } else if let limit = patch.dailyLimitMinutes { app.dailyLimitMinutes = limit }
            appsByChild[childId]?[index] = app
            return AppRuleUpdate(id: app.id, name: app.name, approval: app.approval, approvalLabel: app.approvalLabel, dailyLimitMinutes: app.dailyLimitMinutes)
        }
        throw APIError.server(status: 404, code: "not_found", message: "That app couldn't be found.")
    }

    func addApp(childId: String, name: String, approval: AppApproval, dailyLimitMinutes: Int?) async throws -> ChildApp {
        try gate()
        _ = try requireChild(childId)
        if appsByChild[childId]?.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) == true {
            throw APIError.server(status: 409, code: "conflict", message: "\(name) is already on this child's list.")
        }
        var new = app(name, approval, limit: dailyLimitMinutes, today: 0)
        new.installedAt = nil
        appsByChild[childId, default: []].append(new)
        return new
    }

    func location(childId: String) async throws -> LocationResponse {
        try gate()
        _ = try requireChild(childId)
        let devices = devicesByChild[childId] ?? []
        let protection = protectionsByChild[childId]?.first { $0.key == "LOCATION" }
        let sharing = protection?.policy["sharing"]?.boolValue == true && protection?.status == .pass && !devices.isEmpty
        let current = sharing ? CurrentLocation(deviceId: devices[0].id, deviceName: devices[0].name, lat: 10.6785, lng: 124.8006, accuracyM: 25, placeLabel: "Baybay City, Leyte", locatedAt: Date.now.addingTimeInterval(-120), updatedLabel: "Last updated 2 minutes ago") : nil
        let visits = sharing && privacySettings.keepLocationHistory ? Self.sampleVisits(deviceName: devices[0].name) : []
        return LocationResponse(childId: childId, sharing: sharing, current: current,
                                devices: devices.map { LocationDevice(id: $0.id, name: $0.name, sharing: sharing, hasLocation: sharing) },
                                history: LocationHistory(enabled: privacySettings.keepLocationHistory, visits: visits))
    }

    private static func sampleVisits(deviceName: String) -> [Visit] {
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int, daysAgo: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let entries: [(String, Double, Double, Date)] = [
            ("At Home", 10.6785, 124.8006, at(20, 14)),
            ("Baybay Central School", 10.6801, 124.7960, at(14, 32)),
            ("Robinsons Baybay", 10.6740, 124.8050, at(11, 8)),
            ("At Home", 10.6785, 124.8006, at(19, 40, daysAgo: 1)),
        ]
        return entries.enumerated().map { index, entry in
            Visit(id: "visit_\(index)", deviceName: deviceName, lat: entry.1, lng: entry.2, placeLabel: entry.0, arrivedAt: entry.3, lastSeenAt: entry.3.addingTimeInterval(1800),
                  timeLabel: entry.3.formatted(date: .omitted, time: .shortened), day: dayGroup(entry.3))
        }
    }

    func visits(childId: String, before: Date?) async throws -> VisitsPage {
        try gate()
        let response = try await location(childId: childId)
        return VisitsPage(enabled: privacySettings.keepLocationHistory, retentionDays: privacySettings.retentionDays, visits: before == nil ? response.history.visits : [], nextBefore: nil)
    }

    func familyLocations() async throws -> FamilyLocations {
        try gate()
        var children: [FamilyLocation] = []
        for summary in summaries {
            let response = try await location(childId: summary.id)
            children.append(FamilyLocation(childId: summary.id, name: summary.name, hue: summary.hue, photoUrl: summary.photoUrl, sharing: response.sharing,
                                           state: summary.deviceCount == 0 ? "no_devices" : (response.current != nil ? "located" : (response.sharing ? "waiting" : "sharing_off")), location: response.current))
        }
        return FamilyLocations(children: children)
    }

    // MARK: Alerts

    private func unread() -> Int {
        alertsList.filter { !$0.read && !$0.resolved && $0.severity != .info }.count
    }

    func alerts(filter: AlertsFilter, childId: String?, includeResolved: Bool, before: Date?) async throws -> AlertsPage {
        try gate()
        _ = try requireUser()
        let categories: [APIAlertCategory]? = switch filter {
        case .all: nil
        case .protection: [.protection, .location]
        case .apps: [.apps]
        case .devices: [.devices]
        }
        let filtered = alertsList.filter { alert in
            (categories == nil || categories!.contains(alert.category))
                && (childId == nil || alert.childId == childId)
                && (includeResolved || !alert.resolved)
                && before == nil
        }
        return AlertsPage(alerts: filtered.sorted { $0.createdAt > $1.createdAt }, unread: unread(), nextBefore: nil)
    }

    func unreadCount() async throws -> Int {
        try gate()
        _ = try requireUser()
        return unread()
    }

    func markAlertRead(id: String) async throws -> Int {
        try gate()
        if let index = alertsList.firstIndex(where: { $0.id == id }) { alertsList[index].read = true }
        return unread()
    }

    func markAllAlertsRead() async throws -> Int {
        try gate()
        let count = alertsList.filter { !$0.read }.count
        alertsList = alertsList.map { var copy = $0; copy.read = true; return copy }
        return count
    }

    func dismissAlert(id: String) async throws {
        try gate()
        guard let index = alertsList.firstIndex(where: { $0.id == id }) else { throw APIError.server(status: 404, code: "not_found", message: "That alert couldn't be found.") }
        guard alertsList[index].dismissible else { throw APIError.server(status: 409, code: "not_dismissible", message: "This alert clears itself once the problem is fixed.") }
        alertsList.remove(at: index)
    }

    // MARK: Devices and checks

    func devices() async throws -> DevicesResponse {
        try gate()
        _ = try requireUser()
        return DevicesResponse(devices: summaries.flatMap { devicesByChild[$0.id] ?? [] }, limit: 8)
    }

    func device(id: String) async throws -> DeviceDetail {
        try gate()
        for (childId, devices) in devicesByChild {
            guard let device = devices.first(where: { $0.id == id }) else { continue }
            let protections = (protectionsByChild[childId] ?? []).map { protection -> DeviceProtectionStatus in
                let entry = protection.devices.first { $0.deviceId == id }
                return DeviceProtectionStatus(key: protection.key, name: protection.name, icon: protection.icon, capability: entry?.capability ?? .available, capabilityLabel: entry?.capability.title,
                                              status: entry?.status ?? .notConfigured, reportedLabel: entry?.reportedLabel, message: entry?.message, lastVerifiedAt: entry?.lastVerifiedAt)
            }
            return DeviceDetail(id: device.id, childId: device.childId, childName: device.childName, name: device.name, model: device.model, kind: device.kind, platform: device.platform, osVersion: device.osVersion, appVersion: device.appVersion, battery: device.battery, isPrimary: device.isPrimary, lastSeenAt: device.lastSeenAt, lastSeenLabel: device.lastSeenLabel, state: device.state, issues: device.issues, protections: protections)
        }
        throw APIError.server(status: 404, code: "not_found", message: "That device couldn't be found.")
    }

    func renameDevice(id: String, name: String) async throws -> DeviceDetail {
        try gate()
        for (childId, devices) in devicesByChild {
            guard let index = devices.firstIndex(where: { $0.id == id }) else { continue }
            devicesByChild[childId]?[index].name = name
            refreshSummary(childId)
            return try await device(id: id)
        }
        throw APIError.server(status: 404, code: "not_found", message: "That device couldn't be found.")
    }

    func unpairDevice(id: String) async throws {
        try gate()
        for (childId, devices) in devicesByChild where devices.contains(where: { $0.id == id }) {
            devicesByChild[childId] = devices.filter { $0.id != id }
            protectionsByChild[childId] = (protectionsByChild[childId] ?? []).map { var copy = $0; copy.devices.removeAll { $0.deviceId == id }; return copy }
            refreshSummary(childId)
        }
    }

    private var checkRuns: [String: Int] = [:]

    func startCheck(deviceId: String?) async throws -> String {
        try gate()
        _ = try requireUser()
        let runId = nextID("run")
        checkRuns[runId] = 0
        return runId
    }

    func check(runId: String) async throws -> CheckRun {
        try gate()
        guard let polls = checkRuns[runId] else { throw APIError.server(status: 404, code: "not_found", message: "That check couldn't be found.") }
        checkRuns[runId] = polls + 1
        let done = polls >= 1
        let results = summaries.flatMap { summary in (devicesByChild[summary.id] ?? []).map { device in
            CheckRun.Result(deviceId: device.id, deviceName: device.name, childName: summary.name, reachable: done ? device.state != .offline : nil, issues: done ? device.issues : nil, reported: done && device.state != .offline)
        } }
        return CheckRun(status: done ? "DONE" : "RUNNING", done: done, health: familyHealth(), results: results)
    }

    // MARK: Family and privacy

    func family() async throws -> Family {
        try gate()
        let user = try requireUser()
        return Family(id: user.family.id, name: user.family.name, timezone: user.family.timezone, members: members, children: summaries,
                      deviceCount: devicesByChild.values.reduce(0) { $0 + $1.count }, deviceLimit: 8, canManage: user.isAdmin)
    }

    func addMember(name: String, email: String, password: String) async throws -> FamilyMember {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can add parents.") }
        let normalized = AccountValidator.normalizedEmail(email)
        guard accounts[normalized] == nil else { throw APIError.server(status: 409, code: "conflict", message: "That email already has an eGuard account.") }
        let member = FamilyMember(id: nextID("usr"), name: name, email: normalized, role: .parent, createdAt: .now, you: false)
        let parent = APIUser(id: member.id, name: name, firstName: name.split(separator: " ").first.map(String.init) ?? name, email: normalized, role: .parent, family: user.family,
                             notifications: user.notifications, twoFactor: false, emailVerified: false, createdAt: .now)
        accounts[normalized] = Account(user: parent, password: password)
        members.append(member)
        return member
    }

    func removeMember(id: String) async throws {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can remove parents.") }
        guard id != user.id else { throw APIError.server(status: 400, code: "invalid", message: "You can't remove yourself.") }
        members.removeAll { $0.id == id }
    }

    func privacy() async throws -> PrivacySettings {
        try gate()
        _ = try requireUser()
        return privacySettings
    }

    func updatePrivacy(_ patch: PrivacyPatch) async throws -> PrivacySettings {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can change privacy settings.") }
        if let value = patch.keepLocationHistory { privacySettings.keepLocationHistory = value }
        if let value = patch.shareAnalytics { privacySettings.shareAnalytics = value }
        return privacySettings
    }

    // MARK: Subscription and support

    func subscription() async throws -> SubscriptionInfo {
        try gate()
        _ = try requireUser()
        let renews = Calendar.current.date(byAdding: .day, value: 15, to: .now) ?? .now
        return SubscriptionInfo(
            plan: "eGuard Plus", status: "ACTIVE", renewsAt: renews, renewsLabel: "Renews on \(renews.formatted(date: .abbreviated, time: .omitted))",
            features: [
                PlanFeature(key: "children", included: true, label: "Unlimited children"),
                PlanFeature(key: "devices", included: true, label: "Up to 8 devices"),
                PlanFeature(key: "health_checks", included: true, label: "Configuration health checks"),
                PlanFeature(key: "alerts", included: true, label: "Protection alerts"),
                PlanFeature(key: "reports", included: true, label: "Advanced reports"),
                PlanFeature(key: "priority_support", included: false, label: "Priority support"),
            ],
            usage: PlanUsage(devicesUsed: devicesByChild.values.reduce(0) { $0 + $1.count }, deviceLimit: 8, children: summaries.count),
            canManage: currentUser?.isAdmin ?? false, billingAvailable: false, store: nil,
            // The iOS client never shows an upgrade path, so the mock omits it like the server does for X-eGuard-Client: ios.
            upgrade: nil
        )
    }

    func createTicket(category: String?, subject: String, message: String) async throws -> SupportTicket {
        try gate()
        _ = try requireUser()
        guard (3...120).contains(subject.count) else { throw APIError.server(status: 400, code: "invalid", message: "subject: Use 3 to 120 characters.") }
        guard (10...5000).contains(message.count) else { throw APIError.server(status: 400, code: "invalid", message: "message: Use at least 10 characters.") }
        let ticket = SupportTicket(id: nextID("ticket"), category: category ?? "OTHER", subject: subject, message: "Thanks! We received your message and will reply within 1 business day.", status: "OPEN", createdAt: .now)
        ticketsList.insert(SupportTicket(id: ticket.id, category: ticket.category, subject: subject, message: message, status: "OPEN", createdAt: .now), at: 0)
        return ticket
    }

    func tickets() async throws -> [SupportTicket] {
        try gate()
        _ = try requireUser()
        return ticketsList
    }
}
