import Foundation

/// An in-memory eGuard API with the spec's example data. Used by previews, UI tests, and unit tests.
/// It keeps enough state that flows behave like the real server: sign-in, adding a child, batches that
/// verify after a couple of polls, alerts that resolve, and app rules that change.
final class MockEGuardAPI: EGuardAPIService {
    private struct Account {
        var user: APIUser
        /// Nil for Apple/Google accounts that never set a password.
        var password: String?
        var twoFactorSecret: String?
        var twoFactorEnabled = false
        var recoveryCodes: [String] = []
        var identities: [LinkedIdentity] = []
    }

    /// The code the mock's authenticator "shows". Tests use it to pass two-step verification.
    static let authenticatorCode = "123456"
    /// One-time tokens the mock "emails": password resets, email verification, invitations.
    private enum LinkKind { case reset(email: String), verify(email: String), invite(memberId: String) }

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
    private var challenges: [String: String] = [:]
    private var links: [String: LinkKind] = [:]
    private var browsersList: [ConnectedBrowser] = []
    private var browserRequests: [BrowserAccessRequest] = []
    private var browserPolicies: [String: BrowserPolicy] = [:]
    private var organizationsList: [Organization] = []
    private var browserRequestChild: [String: String] = [:]
    private var sequence = 0

    /// The plan the mock family is on. Tests flip entitlements to exercise plan gating.
    var entitlements = PlanEntitlements(childLimit: 5, deviceLimit: 10, locationSharing: true, appMonitoringLimit: nil, realtimeAlerts: true, advancedReports: false, apiAccess: false)
    /// The last one-time link the mock "emailed", so tests can open it.
    private(set) var lastLinkToken: String?

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

    /// Signs Randy back in on the server side, for tests that look at the parent's view after a child-device action.
    func loginForTests() {
        currentUser = accounts["randy@example.com"]?.user
    }

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
            twoFactor: false, hasPassword: true, emailVerified: true, createdAt: Date.now.addingTimeInterval(-40 * 86400)
        )
        accounts[user.email] = Account(user: user, password: "ChangeMe123!")
        members = [
            FamilyMember(id: user.id, name: user.name, email: user.email, role: .familyAdmin, createdAt: user.createdAt, you: true, pending: false),
            FamilyMember(id: "usr_ana", name: "Ana Cruz", email: "ana@example.com", role: .parent, createdAt: Date.now.addingTimeInterval(-30 * 86400), you: false, pending: false),
        ]
        organizationsList = [Organization(id: "org_1", name: "Baybay Central School", kind: "SCHOOL", kindLabel: "School", joinedAt: Date.now.addingTimeInterval(-20 * 86400))]
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
        // Snapchat is blocked, and Mia asked for it again: it stays blocked with `requested: true`.
        if let index = appsByChild[mia.id]?.firstIndex(where: { $0.name == "Snapchat" }) { appsByChild[mia.id]?[index].requested = true }

        browsersList = [
            ConnectedBrowser(id: nextID("browser"), childId: sophie.id, childName: "Sophie", deviceLabel: "Sophie's MacBook", browser: "Chrome", browserVersion: "130", extensionVersion: "1.2.0", platform: "macOS", lastSeenAt: Date.now.addingTimeInterval(-1800), connected: true, createdAt: Date.now.addingTimeInterval(-10 * 86400)),
        ]
        browserRequests = [
            BrowserAccessRequest(id: nextID("webreq"), domain: "discord.com", reason: "For my school group chat", status: "PENDING", duration: nil, expiresAt: nil, createdAt: Date.now.addingTimeInterval(-3600), decidedAt: nil, decidedBy: nil),
        ]
        browserRequestChild[browserRequests[0].id] = sophie.id

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
            let capability = Self.capability(key: protection.key, platform: platform)
            // A device that can't apply a protection is "Not supported" there, whatever the siblings do.
            copy.devices.append(ProtectionDevice(
                deviceId: device.id, deviceName: device.name, platform: platform,
                capability: capability,
                status: capability == .unsupported ? .unsupported : .notConfigured, reported: nil,
                reportedLabel: capability == .unsupported ? "Not supported" : "Not configured",
                message: capability == .unsupported ? "Not supported on \(device.name)" : "Not configured on \(device.name)", lastVerifiedAt: nil, guide: nil
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
        // A device that reported usage wins over the seeded sample.
        summary.todayMinutes = reportedUsage[childId] ?? (devices.isEmpty ? 0 : 134)
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
        let offline = (devicesByChild[childId] ?? []).filter { $0.state == .offline }.count
        let total = (devicesByChild[childId] ?? []).isEmpty ? 0 : evaluated.count
        var score = HealthScore(score: passed, total: total, label: nil, offline: offline, verified: total > 0 && passed == total && offline == 0)
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

    private func session(for user: APIUser, isNew: Bool) -> AuthResponse {
        AuthResponse(token: "mock-token-\(user.id)", expiresAt: Date.now.addingTimeInterval(30 * 86400), user: user, isNew: isNew)
    }

    /// Signs the account in, or hands back a two-step challenge when the account has it on.
    private func finishSignIn(_ account: Account, isNew: Bool) -> LoginResult {
        if account.twoFactorEnabled {
            let challenge = nextID("challenge")
            challenges[challenge] = account.user.email
            return .twoFactorRequired(TwoFactorChallenge(challenge: challenge, expiresAt: Date.now.addingTimeInterval(600), isNew: isNew))
        }
        currentUser = account.user
        return .signedIn(session(for: account.user, isNew: isNew))
    }

    private func issueLink(_ kind: LinkKind) -> String {
        let token = nextID("link")
        links[token] = kind
        lastLinkToken = token
        return token
    }

    private func saveAccount(_ account: Account) {
        accounts[account.user.email] = account
        if currentUser?.id == account.user.id { currentUser = account.user }
    }

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
            twoFactor: false, hasPassword: true, emailVerified: false, createdAt: .now
        )
        accounts[normalized] = Account(user: user, password: password)
        _ = issueLink(.verify(email: normalized))
        currentUser = user
        members = [FamilyMember(id: user.id, name: user.name, email: user.email, role: .familyAdmin, createdAt: .now, you: true, pending: false)]
        summaries = []
        alertsList = []
        organizationsList = []
        browsersList = []
        return session(for: user, isNew: true)
    }

    func login(email: String, password: String) async throws -> LoginResult {
        try gate()
        guard let account = accounts[AccountValidator.normalizedEmail(email)], let stored = account.password, stored == password else {
            throw APIError.server(status: 401, code: "invalid_credentials", message: "That email and password don't match an eGuard account.")
        }
        return finishSignIn(account, isNew: false)
    }

    /// Set to true to behave like a server that doesn't know the `nonce` field yet.
    var rejectsNonce = false
    private(set) var lastSocialNonce: String?

    func social(provider: SocialProvider, idToken: String, name: String?, guardian: Bool, nonce: String?) async throws -> LoginResult {
        try gate()
        guard appInfoValue.signIn.apple || provider != .apple else {
            throw APIError.server(status: 501, code: "provider_not_configured", message: "Apple sign-in isn't enabled on this server.")
        }
        if rejectsNonce, nonce != nil {
            throw APIError.server(status: 400, code: "invalid", message: "nonce: Unknown field.")
        }
        lastSocialNonce = nonce
        let email = "\(provider.rawValue)-\(idToken.prefix(6).lowercased())@privaterelay.example"
        if let account = accounts[email] {
            return finishSignIn(account, isNew: false)
        }
        guard guardian else { throw APIError.server(status: 400, code: "guardian_required", message: "Confirm you're a parent or legal guardian, 18 or older.") }
        let response = try await register(name: name?.isEmpty == false ? name! : "Parent", email: email, password: UUID().uuidString, familyName: nil)
        // Social accounts have no password and count as verified.
        guard var account = accounts[email] else { throw APIError.notSignedIn }
        account.password = nil
        account.user.hasPassword = false
        account.user.emailVerified = true
        account.identities = [LinkedIdentity(id: nextID("identity"), provider: provider.rawValue, email: email, createdAt: .now)]
        saveAccount(account)
        return .signedIn(AuthResponse(token: response.token, expiresAt: response.expiresAt, user: account.user, isNew: true))
    }

    func twoFactor(challenge: String, code: String) async throws -> AuthResponse {
        try gate()
        guard let email = challenges[challenge], var account = accounts[email] else {
            throw APIError.server(status: 401, code: "challenge_expired", message: "That sign-in expired. Start again.")
        }
        var response = session(for: account.user, isNew: false)
        if code == Self.authenticatorCode {
            // Fine.
        } else if let index = account.recoveryCodes.firstIndex(of: code) {
            account.recoveryCodes.remove(at: index)
            saveAccount(account)
            response.usedRecoveryCode = true
            response.recoveryCodesLeft = account.recoveryCodes.count
        } else {
            throw APIError.server(status: 400, code: "wrong_code", message: "That code isn't right. Try again.")
        }
        challenges[challenge] = nil
        currentUser = account.user
        return response
    }

    func forgotPassword(email: String) async throws -> OKResponse {
        try gate()
        let normalized = AccountValidator.normalizedEmail(email)
        if accounts[normalized] != nil { _ = issueLink(.reset(email: normalized)) }
        return OKResponse(ok: true, message: "If an eGuard account uses \(normalized), we've emailed a link to set a new password.")
    }

    func resetPassword(token: String, password: String) async throws -> LoginResult {
        try gate()
        guard password.count >= 10 else { throw APIError.server(status: 400, code: "invalid", message: "password: Use at least 10 characters.") }
        guard case .reset(let email)? = links.removeValue(forKey: token), var account = accounts[email] else {
            throw APIError.server(status: 400, code: "link_invalid", message: "This link was already used or isn't valid. Ask for a new one.")
        }
        account.password = password
        account.user.hasPassword = true
        saveAccount(account)
        return finishSignIn(account, isNew: false)
    }

    func verifyEmail(token: String) async throws {
        try gate()
        guard case .verify(let email)? = links.removeValue(forKey: token), var account = accounts[email] else {
            throw APIError.server(status: 400, code: "link_invalid", message: "This link was already used or isn't valid. Ask for a new one.")
        }
        account.user.emailVerified = true
        saveAccount(account)
    }

    func invitation(token: String) async throws -> InvitationPreview {
        try gate()
        guard case .invite(let memberId)? = links[token], let member = members.first(where: { $0.id == memberId }) else {
            throw APIError.server(status: 400, code: "link_invalid", message: "This invitation was already used or isn't valid.")
        }
        return InvitationPreview(name: member.name, email: member.email, familyName: family.name, invitedBy: members.first { $0.role == .familyAdmin }?.name)
    }

    func acceptInvitation(token: String, password: String) async throws -> AuthResponse {
        try gate()
        guard password.count >= 10 else { throw APIError.server(status: 400, code: "invalid", message: "password: Use at least 10 characters.") }
        guard case .invite(let memberId)? = links.removeValue(forKey: token), let index = members.firstIndex(where: { $0.id == memberId }) else {
            throw APIError.server(status: 400, code: "link_invalid", message: "This invitation was already used or isn't valid.")
        }
        members[index].pending = false
        let member = members[index]
        let user = APIUser(id: member.id, name: member.name, firstName: member.name.split(separator: " ").first.map(String.init) ?? member.name, email: member.email, role: .parent, family: family,
                           notifications: NotificationPrefs(notifyPush: true, notifyEmail: true, notifyApproval: true, weeklySummary: false), twoFactor: false, hasPassword: true, emailVerified: true, createdAt: .now)
        accounts[member.email] = Account(user: user, password: password)
        currentUser = user
        return session(for: user, isNew: false)
    }

    func declineInvitation(token: String) async throws -> InvitationDeclined {
        try gate()
        guard case .invite(let memberId)? = links.removeValue(forKey: token) else {
            throw APIError.server(status: 400, code: "link_invalid", message: "This invitation was already used or isn't valid.")
        }
        members.removeAll { $0.id == memberId }
        return InvitationDeclined(ok: true, familyName: family.name)
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

    func updateMe(name: String?, email: String?, password: String?, timezone: String?) async throws -> APIUser {
        try gate()
        var user = try requireUser()
        guard var account = accounts[user.email] else { throw APIError.notSignedIn }
        if let name { user.name = name; user.firstName = name.split(separator: " ").first.map(String.init) ?? name }
        if let email {
            let normalized = AccountValidator.normalizedEmail(email)
            if normalized != user.email {
                guard let stored = account.password else {
                    throw APIError.server(status: 403, code: "password_not_set", message: "Set a password with Forgot password? before changing your email.")
                }
                guard password == stored else {
                    throw APIError.server(status: 403, code: "wrong_password", message: "Enter your current password to change your email.")
                }
                if accounts[normalized] != nil {
                    throw APIError.server(status: 409, code: "conflict", message: "That email is already in use.")
                }
                accounts.removeValue(forKey: user.email)
                user.email = normalized
                user.emailVerified = false
                account.identities = []
                _ = issueLink(.verify(email: normalized))
            }
        }
        if let timezone {
            guard user.isAdmin || timezone == user.family.timezone else {
                throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can change the family's time zone.")
            }
            user.family.timezone = timezone
        }
        account.user = user
        accounts[user.email] = account
        currentUser = user
        return user
    }

    private func checkConfirmation(_ confirmation: DeletionConfirmation, for user: APIUser) throws {
        let account = accounts[user.email]
        switch confirmation {
        case .password(let password):
            guard account?.password == password else {
                throw APIError.server(status: 403, code: "wrong_password", message: "That password doesn't match your current password.")
            }
        case .typedDelete:
            guard account?.password == nil else {
                throw APIError.server(status: 400, code: "confirm_required", message: "Enter your password to confirm.")
            }
        }
    }

    func deleteAccount(confirmation: DeletionConfirmation) async throws -> AccountDeleted {
        try gate()
        let user = try requireUser()
        try checkConfirmation(confirmation, for: user)
        accounts[user.email] = nil
        currentUser = nil
        if user.isAdmin {
            summaries = []
            devicesByChild = [:]
            alertsList = []
            members = []
            return AccountDeleted(ok: true, deleted: "family")
        }
        members.removeAll { $0.id == user.id }
        return AccountDeleted(ok: true, deleted: "account")
    }

    func exportData() async throws -> Data {
        try gate()
        let user = try requireUser()
        let export: [String: JSONValue] = [
            "exportedAt": .string(ISO8601DateFormatter.withFractional.string(from: .now)),
            "family": .string(user.family.name),
            "parents": .array(members.map { .string($0.email) }),
            "children": .array(summaries.map { .string($0.name) }),
        ]
        return try JSONEncoder().encode(JSONValue.object(export))
    }

    func identities() async throws -> [LinkedIdentity] {
        try gate()
        let user = try requireUser()
        return accounts[user.email]?.identities ?? []
    }

    func deleteIdentity(id: String) async throws {
        try gate()
        let user = try requireUser()
        guard var account = accounts[user.email] else { return }
        guard account.password != nil || account.identities.count > 1 else {
            throw APIError.server(status: 409, code: "conflict", message: "This is your only way to sign in. Set a password first.")
        }
        account.identities.removeAll { $0.id == id }
        saveAccount(account)
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

    func twoFactorStatus() async throws -> TwoFactorStatus {
        try gate()
        let user = try requireUser()
        let account = accounts[user.email]
        return TwoFactorStatus(available: true, enabled: account?.twoFactorEnabled ?? false, recoveryCodesLeft: account?.recoveryCodes.count ?? 0)
    }

    func setupTwoFactor() async throws -> TwoFactorSetup {
        try gate()
        let user = try requireUser()
        guard var account = accounts[user.email] else { throw APIError.notSignedIn }
        guard !account.twoFactorEnabled else { throw APIError.server(status: 409, code: "conflict", message: "Two-step verification is already on.") }
        let secret = "JBSWY3DPEHPK3PXP"
        account.twoFactorSecret = secret
        saveAccount(account)
        return TwoFactorSetup(secret: secret, uri: "otpauth://totp/eGuard:\(user.email)?secret=\(secret)&issuer=eGuard")
    }

    private func requireTwoFactorCode(_ code: String, account: inout Account) throws {
        if code == Self.authenticatorCode { return }
        if let index = account.recoveryCodes.firstIndex(of: code) {
            account.recoveryCodes.remove(at: index)
            return
        }
        throw APIError.server(status: 400, code: "wrong_code", message: "That code isn't right. Try again.")
    }

    private func freshRecoveryCodes() -> [String] {
        (0..<10).map { _ in String((0..<8).map { _ in "abcdefghjkmnpqrstuvwxyz23456789".randomElement()! }) }
    }

    func confirmTwoFactor(code: String) async throws -> [String] {
        try gate()
        let user = try requireUser()
        guard var account = accounts[user.email] else { throw APIError.notSignedIn }
        guard account.twoFactorSecret != nil else { throw APIError.server(status: 400, code: "setup_missing", message: "Start the setup again.") }
        guard code == Self.authenticatorCode else { throw APIError.server(status: 400, code: "wrong_code", message: "That code isn't right. Try again.") }
        account.twoFactorEnabled = true
        account.recoveryCodes = freshRecoveryCodes()
        account.user.twoFactor = true
        saveAccount(account)
        return account.recoveryCodes
    }

    func regenerateRecoveryCodes(code: String) async throws -> [String] {
        try gate()
        let user = try requireUser()
        guard var account = accounts[user.email] else { throw APIError.notSignedIn }
        try requireTwoFactorCode(code, account: &account)
        account.recoveryCodes = freshRecoveryCodes()
        saveAccount(account)
        return account.recoveryCodes
    }

    func disableTwoFactor(code: String) async throws -> TwoFactorStatus {
        try gate()
        let user = try requireUser()
        guard var account = accounts[user.email] else { throw APIError.notSignedIn }
        try requireTwoFactorCode(code, account: &account)
        account.twoFactorEnabled = false
        account.twoFactorSecret = nil
        account.recoveryCodes = []
        account.user.twoFactor = false
        saveAccount(account)
        return TwoFactorStatus(available: true, enabled: false, recoveryCodesLeft: 0)
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
        let scores = summaries.map(\.health).filter { $0.total > 0 }
        guard !scores.isEmpty else { return HealthScore(score: 0, total: 0, label: "No devices yet", offline: 0, verified: false) }
        // Family score: the average per protection across children with devices, rounded down.
        let score = scores.map(\.score).reduce(0, +) / scores.count
        let offline = devicesByChild.values.flatMap { $0 }.filter { $0.state == .offline }.count
        var health = HealthScore(score: score, total: 10, label: nil, offline: offline, verified: score == 10 && offline == 0)
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
            score: health.score, total: health.total, label: health.grade, offline: health.offline, verified: health.verified, checks: combinedChecks, toFix: toFix,
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
        let slotsUsed = devicesByChild.values.reduce(0) { $0 + $1.count } + browsersList.count
        if let limit = entitlements.deviceLimit, slotsUsed >= limit {
            throw APIError.server(status: 409, code: "plan_limit", message: APIClient.planLimitMessage)
        }
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<8).map { _ in letters.randomElement()! })
        lastPairingCode = (code, childId)
        return PairingCode(code: code, expiresAt: Date.now.addingTimeInterval(15 * 60), childName: child.name, kind: "DEVICE")
    }

    /// The newest phone-app code, so a `MockDeviceAPI` sharing this server can redeem it.
    private(set) var lastPairingCode: (code: String, childId: String)?

    func browserPairingCode(childId: String, deviceLabel: String) async throws -> PairingCode {
        try gate()
        let user = try requireUser()
        let child = summaries[try requireChild(childId)]
        guard user.isEmailVerified else {
            throw APIError.server(status: 403, code: "email_unverified", message: "Verify your email before adding a browser. We sent you a link.")
        }
        guard (1...60).contains(deviceLabel.trimmingCharacters(in: .whitespaces).count) else {
            throw APIError.server(status: 400, code: "invalid", message: "deviceLabel: Enter a name between 1 and 60 characters.")
        }
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<8).map { _ in letters.randomElement()! })
        return PairingCode(code: code, expiresAt: Date.now.addingTimeInterval(15 * 60), childName: child.name, kind: "BROWSER")
    }

    /// Redeems a phone-app code the way `POST /api/device/v1/pair` would. Used by the mock device API.
    func redeemPairingCode(_ code: String, name: String, platform: DevicePlatformKind, model: String, kind: String, osVersion: String) throws -> (deviceId: String, childName: String) {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let pending = lastPairingCode, pending.code == normalized, let child = summaries.first(where: { $0.id == pending.childId }) else {
            throw APIError.server(status: 400, code: "invalid", message: "Pairing code is invalid or expired")
        }
        lastPairingCode = nil
        let device = addDevice(childId: child.id, childName: child.name, name: name, model: model, platform: platform, kind: kind, osVersion: osVersion, lastSeen: 0)
        fullReportRequested.insert(device.id)
        alertsList.insert(makeAlert(childId: child.id, deviceId: device.id, severity: .info, category: .devices, icon: "smartphone", title: "New device synchronized", body: "\(name) is now paired with \(child.name).", subject: name, age: 0, dismissible: true, action: AlertAction(type: "VIEW_DEVICE", label: "View device", childId: child.id, key: nil, deviceId: device.id)), at: 0)
        return (device.id, child.name)
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
            location: {
                let state: LocationState = !entitlements.hasLocationSharing ? .planRequired : (devices.isEmpty ? .noDevices : (sharing ? .located : .sharingOff))
                return LocationInfo(sharing: sharing && state == .located, state: state.rawValue, placeLabel: state == .located ? "Home" : nil, updatedAt: state == .located ? Date.now.addingTimeInterval(-120) : nil, label: state.title)
            }(),
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

    func deleteChild(id: String, confirmation: DeletionConfirmation) async throws {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can delete a child.") }
        try checkConfirmation(confirmation, for: user)
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
                fullReportRequested.insert(batch.items[itemIndex].devices[deviceIndex].deviceId)
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
        if period == .month, !entitlements.hasAdvancedReports {
            throw APIError.server(status: 403, code: "plan_required", message: "30-day reports aren't included in your plan.")
        }
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
        var filtered: [ChildApp]
        switch filter {
        case .installed: filtered = all.filter { $0.approval != .blocked }
        case .blocked: filtered = all.filter { $0.approval == .blocked }
        case .pending: filtered = all.filter { $0.isRequested }
        case nil: filtered = all
        }
        var limited: AppsLimited?
        if let limit = entitlements.appMonitoringLimit, filtered.count > limit {
            // Requests first, then the most used.
            filtered.sort { ($0.isRequested ? 1 : 0, $0.todayMinutes ?? 0) > ($1.isRequested ? 1 : 0, $1.todayMinutes ?? 0) }
            limited = AppsLimited(hidden: filtered.count - limit, message: "Your plan lists \(limit) apps. \(filtered.count - limit) more aren't shown.")
            filtered = Array(filtered.prefix(limit))
        }
        return AppsResponse(counts: counts, apps: filtered, limited: limited)
    }

    func updateApp(id: String, patch: AppPatch) async throws -> AppRuleUpdate {
        try gate()
        for (childId, apps) in appsByChild {
            guard let index = apps.firstIndex(where: { $0.id == id }) else { continue }
            var app = apps[index]
            if let approval = patch.approval {
                app.approval = approval
                app.approvalLabel = approval.title
                app.requested = false
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
        guard entitlements.hasLocationSharing else {
            throw APIError.server(status: 403, code: "plan_required", message: "Location sharing isn't included in your plan.")
        }
        let devices = devicesByChild[childId] ?? []
        let protection = protectionsByChild[childId]?.first { $0.key == "LOCATION" }
        let sharing = protection?.policy["sharing"]?.boolValue == true && protection?.status == .pass && !devices.isEmpty
        let located = Date.now.addingTimeInterval(-120)
        let current = sharing ? CurrentLocation(deviceId: devices[0].id, deviceName: devices[0].name, lat: 10.6785, lng: 124.8006, accuracyM: 25, placeLabel: "Baybay City, Leyte", locatedAt: located, updatedLabel: located.verifiedDescription(), fresh: devices[0].state != .offline, approximate: false) : nil
        let visits = sharing && privacySettings.keepLocationHistory ? Self.sampleVisits(deviceName: devices[0].name) : []
        let state: LocationState = devices.isEmpty ? .noDevices : (!sharing ? .sharingOff : (current == nil ? .waiting : .located))
        return LocationResponse(childId: childId, sharing: sharing, state: state.rawValue, current: current,
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

    func unpairDevice(id: String, confirmation: DeletionConfirmation) async throws {
        try gate()
        let user = try requireUser()
        try checkConfirmation(confirmation, for: user)
        var found = false
        for (childId, devices) in devicesByChild where devices.contains(where: { $0.id == id }) {
            found = true
            let removed = devices.first { $0.id == id }
            devicesByChild[childId] = devices.filter { $0.id != id }
            protectionsByChild[childId] = (protectionsByChild[childId] ?? []).map { var copy = $0; copy.devices.removeAll { $0.deviceId == id }; return copy }
            refreshSummary(childId)
            alertsList.insert(makeAlert(childId: childId, deviceId: nil, severity: .info, category: .devices, icon: "smartphone", title: "Device removed", body: "\(removed?.name ?? "A device") was removed from eGuard, so its protections are no longer verified.", subject: removed?.name, age: 0, dismissible: true, action: nil), at: 0)
        }
        removedDeviceIds.insert(id)
        guard found else { throw APIError.server(status: 404, code: "not_found", message: "That device couldn't be found.") }
    }

    /// Devices a parent removed. The mock device API answers 401 for them, like the real server.
    private(set) var removedDeviceIds: Set<String> = []

    func browsers() async throws -> [ConnectedBrowser] {
        try gate()
        _ = try requireUser()
        return browsersList
    }

    func removeBrowser(id: String, confirmation: DeletionConfirmation) async throws {
        try gate()
        let user = try requireUser()
        try checkConfirmation(confirmation, for: user)
        guard let browser = browsersList.first(where: { $0.id == id }) else {
            throw APIError.server(status: 404, code: "not_found", message: "That browser couldn't be found.")
        }
        browsersList.removeAll { $0.id == id }
        alertsList.insert(makeAlert(childId: browser.childId, deviceId: nil, severity: .info, category: .devices, icon: "globe", title: "Browser removed", body: "\(browser.deviceLabel) was disconnected from eGuard.", subject: browser.deviceLabel, age: 0, dismissible: true, action: nil), at: 0)
    }

    func browserPolicy(childId: String) async throws -> BrowserPolicy {
        try gate()
        let child = summaries[try requireChild(childId)]
        if let policy = browserPolicies[childId] { return policy }
        let policy = BrowserPolicy(
            version: 1, safeBrowsing: true, safeSearch: true,
            blockedCategories: child.age < 13 ? ["ADULT", "GAMBLING", "VIOLENCE", "SOCIAL"] : ["ADULT", "GAMBLING"],
            blockedDomains: [], allowedDomains: [], unknownSitesPolicy: child.age < 13 ? "WARN" : "ALLOW",
            schedule: nil, updatedBy: "eGuard defaults", updatedAt: .now,
            categories: [
                BrowserCategory(key: "ADULT", label: "Adult content", hint: "Pornography and explicit material"),
                BrowserCategory(key: "GAMBLING", label: "Gambling", hint: "Betting and casino sites"),
                BrowserCategory(key: "VIOLENCE", label: "Violence", hint: "Graphic or violent content"),
                BrowserCategory(key: "SOCIAL", label: "Social networks", hint: "Social media and chat"),
            ]
        )
        browserPolicies[childId] = policy
        return policy
    }

    func updateBrowserPolicy(childId: String, policy update: BrowserPolicyUpdate) async throws -> BrowserPolicy {
        try gate()
        var policy = try await browserPolicy(childId: childId)
        if let base = update.baseVersion, base != policy.version {
            throw APIError.server(status: 409, code: "stale_version", message: "Someone else changed these settings. Reload and try again.")
        }
        let overlap = Set(update.blockedDomains).intersection(update.allowedDomains)
        guard overlap.isEmpty else {
            throw APIError.server(status: 400, code: "invalid", message: "\(overlap.first!) can't be on both lists.")
        }
        let changed = policy.update != BrowserPolicyUpdate(safeBrowsing: update.safeBrowsing, safeSearch: update.safeSearch, blockedCategories: update.blockedCategories, blockedDomains: update.blockedDomains, allowedDomains: update.allowedDomains, unknownSitesPolicy: update.unknownSitesPolicy, schedule: update.schedule, baseVersion: policy.version)
        policy.safeBrowsing = update.safeBrowsing
        policy.safeSearch = update.safeSearch
        policy.blockedCategories = update.blockedCategories
        policy.blockedDomains = Array(Set(update.blockedDomains)).sorted()
        policy.allowedDomains = Array(Set(update.allowedDomains)).sorted()
        policy.unknownSitesPolicy = update.unknownSitesPolicy
        policy.schedule = update.schedule
        if changed {
            policy.version += 1
            policy.updatedBy = "\(currentUser?.name ?? "Parent") on iOS app"
            policy.updatedAt = .now
        }
        browserPolicies[childId] = policy
        return policy
    }

    func browserAccessRequests(childId: String) async throws -> BrowserAccessRequests {
        try gate()
        _ = try requireChild(childId)
        let mine = browserRequests.filter { browserRequestChild[$0.id] == childId }
        return BrowserAccessRequests(pending: mine.filter(\.isPending), recent: mine.filter { !$0.isPending })
    }

    func decideBrowserAccessRequest(id: String, decision: BrowserAccessDecision) async throws -> BrowserAccessRequest {
        try gate()
        let user = try requireUser()
        guard let index = browserRequests.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(status: 404, code: "not_found", message: "That request couldn't be found.")
        }
        guard browserRequests[index].isPending else {
            throw APIError.server(status: 409, code: "already_decided", message: "Another parent already answered this request.")
        }
        var request = browserRequests[index]
        request.decidedAt = .now
        request.decidedBy = user.name
        switch decision {
        case .approve(let duration):
            request.status = "APPROVED"
            request.duration = duration.rawValue
            if duration == .always, let childId = browserRequestChild[id] {
                var policy = try await browserPolicy(childId: childId)
                policy.allowedDomains = Array(Set(policy.allowedDomains + [request.domain])).sorted()
                policy.version += 1
                browserPolicies[childId] = policy
            }
        case .deny:
            request.status = "DENIED"
        }
        browserRequests[index] = request
        return request
    }

    private var checkRuns: [String: Int] = [:]

    func startCheck(deviceId: String?) async throws -> String {
        try gate()
        _ = try requireUser()
        guard devicesByChild.values.contains(where: { !$0.isEmpty }) else {
            throw APIError.server(status: 409, code: "no_devices", message: "Pair a device before running a check.")
        }
        let runId = nextID("run")
        checkRuns[runId] = 0
        for device in devicesByChild.values.flatMap({ $0 }) where deviceId == nil || device.id == deviceId {
            fullReportRequested.insert(device.id)
        }
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

    private var planName: String {
        switch entitlements.childLimit {
        case 1: "Free"
        case 5: "eGuard Plus"
        default: "Family Pro"
        }
    }

    func family() async throws -> Family {
        try gate()
        let user = try requireUser()
        let deviceCount = devicesByChild.values.reduce(0) { $0 + $1.count }
        return Family(id: user.family.id, name: user.family.name, timezone: user.family.timezone, members: members, children: summaries,
                      deviceCount: deviceCount, devicesUsed: deviceCount + browsersList.count, deviceLimit: entitlements.deviceLimit ?? 10,
                      childCount: summaries.count, childLimit: entitlements.childLimit, plan: planName, entitlements: entitlements, canManage: user.isAdmin)
    }

    func inviteMember(name: String, email: String) async throws -> InvitationSent {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can add parents.") }
        let normalized = AccountValidator.normalizedEmail(email)
        guard accounts[normalized] == nil, !members.contains(where: { $0.email == normalized }) else {
            throw APIError.server(status: 409, code: "conflict", message: "That email already has an eGuard account.")
        }
        let member = FamilyMember(id: nextID("usr"), name: name, email: normalized, role: .parent, createdAt: .now, you: false, pending: true)
        members.append(member)
        _ = issueLink(.invite(memberId: member.id))
        return InvitationSent(id: member.id, name: member.name, email: member.email, role: .parent, pending: true, emailSent: true, expiresInDays: 7)
    }

    func resendInvitation(memberId: String) async throws {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can resend invitations.") }
        guard let member = members.first(where: { $0.id == memberId }) else {
            throw APIError.server(status: 404, code: "not_found", message: "That parent couldn't be found.")
        }
        guard member.isPending else { throw APIError.server(status: 409, code: "conflict", message: "\(member.name) already accepted the invitation.") }
        _ = issueLink(.invite(memberId: memberId))
    }

    func removeMember(id: String) async throws {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can remove parents.") }
        guard id != user.id else { throw APIError.server(status: 400, code: "invalid", message: "You can't remove yourself.") }
        members.removeAll { $0.id == id }
    }

    func organizations() async throws -> OrganizationsResponse {
        try gate()
        let user = try requireUser()
        return OrganizationsResponse(organizations: organizationsList, canManage: user.isAdmin,
                                     privacy: "Organizations only see how many families joined. They never see your children, devices or activity.")
    }

    private static let knownOrganizations: [String: Organization] = [
        "SCHL2026": Organization(id: "org_1", name: "Baybay Central School", kind: "SCHOOL", kindLabel: "School", joinedAt: nil),
        "CMTY4KID": Organization(id: "org_2", name: "Leyte Parents Circle", kind: "COMMUNITY", kindLabel: "Community group", joinedAt: nil),
    ]

    private func normalizedJoinCode(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    func previewOrganization(code: String) async throws -> OrganizationPreview {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can join an organization.") }
        guard let organization = Self.knownOrganizations[normalizedJoinCode(code)] else {
            throw APIError.server(status: 400, code: "invalid", message: "That code doesn't match an organization. Check it and try again.")
        }
        return OrganizationPreview(name: organization.name, kind: organization.kind, kindLabel: organization.kindLabel, alreadyJoined: organizationsList.contains { $0.id == organization.id },
                                   message: "\(organization.name) will see that your family joined and how many families have joined in total. It won't see your children, devices, locations or activity.")
    }

    func joinOrganization(code: String) async throws -> OrganizationJoined {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can join an organization.") }
        guard var organization = Self.knownOrganizations[normalizedJoinCode(code)] else {
            throw APIError.server(status: 400, code: "invalid", message: "That code doesn't match an organization. Check it and try again.")
        }
        if !organizationsList.contains(where: { $0.id == organization.id }) {
            guard organizationsList.count < 5 else { throw APIError.server(status: 409, code: "conflict", message: "Your family is already in the maximum number of organizations.") }
            organization.joinedAt = .now
            organizationsList.append(organization)
        }
        return OrganizationJoined(ok: true, name: organization.name, organizations: organizationsList)
    }

    func leaveOrganization(id: String) async throws -> OrganizationLeft {
        try gate()
        let user = try requireUser()
        guard user.isAdmin else { throw APIError.server(status: 403, code: "forbidden", message: "Only the family admin can leave an organization.") }
        guard let organization = organizationsList.first(where: { $0.id == id }) else {
            throw APIError.server(status: 404, code: "not_found", message: "That organization couldn't be found.")
        }
        organizationsList.removeAll { $0.id == id }
        return OrganizationLeft(ok: true, name: organization.name)
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
        let childLimit = entitlements.childLimit ?? 5
        let deviceLimit = entitlements.deviceLimit ?? 10
        return SubscriptionInfo(
            plan: planName, planId: planName == "Free" ? "FREE" : (planName == "eGuard Plus" ? "PLUS" : "PRO"), status: "ACTIVE", renewsAt: renews,
            renewsLabel: "Renews on \(renews.formatted(date: .abbreviated, time: .omitted))",
            features: [
                PlanFeature(key: "children", included: true, label: "Up to \(childLimit) child\(childLimit == 1 ? "" : "ren")"),
                PlanFeature(key: "protection", included: true, label: "Full protection features"),
                PlanFeature(key: "verification", included: true, label: "Configuration verification"),
                PlanFeature(key: "alerts", included: entitlements.hasRealtimeAlerts, label: "Real-time alerts"),
                PlanFeature(key: "location", included: entitlements.hasLocationSharing, label: "Location sharing"),
                PlanFeature(key: "reports", included: entitlements.hasAdvancedReports, label: "30-day reports"),
                PlanFeature(key: "support", included: planName != "Free", label: "Priority support"),
            ],
            entitlements: entitlements,
            usage: PlanUsage(devicesUsed: devicesByChild.values.reduce(0) { $0 + $1.count } + browsersList.count, deviceLimit: deviceLimit, children: summaries.count, childLimit: childLimit),
            canManage: currentUser?.isAdmin ?? false, billingAvailable: false, store: StoreInfo(name: "PAYMONGO", productId: nil, autoRenewing: true, expiresAt: renews),
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

    // MARK: Child device side (used by MockDeviceAPI)

    /// Devices whose next `/sync` should answer with a full report: just paired, a parent tapped
    /// "Verify now", or a check is running.
    private var fullReportRequested: Set<String> = []
    private var lastFixes: [String: LocationFix] = [:]

    func isDeviceRemoved(_ deviceId: String) -> Bool {
        removedDeviceIds.contains(deviceId) || !devicesByChild.values.contains { $0.contains { $0.id == deviceId } }
    }

    private func childId(ofDevice deviceId: String) -> String? {
        devicesByChild.first { $0.value.contains { $0.id == deviceId } }?.key
    }

    /// `POST /sync` for a device: the child's policy, the open APPLY requests for this device, and app rules.
    func deviceSync(deviceId: String) throws -> SyncResponse {
        guard let childId = childId(ofDevice: deviceId), !removedDeviceIds.contains(deviceId) else {
            throw DeviceAPIError.server(status: 401, message: "Invalid or missing device token")
        }
        touchDevice(deviceId)
        let protections = protectionsByChild[childId] ?? []
        let policy = protections.map { PolicyEntry(key: $0.key, config: $0.policy) }
        var requests: [DeviceRequest] = []
        for (batchId, var batch) in batches where batch.childId == childId {
            for itemIndex in batch.items.indices {
                for deviceIndex in batch.items[itemIndex].devices.indices {
                    var device = batch.items[itemIndex].devices[deviceIndex]
                    guard device.deviceId == deviceId, !device.isGuided, device.status == .pending || device.status == .delivered else { continue }
                    device.status = .delivered
                    batch.items[itemIndex].devices[deviceIndex] = device
                    let config = protections.first { $0.key == batch.items[itemIndex].key }?.policy ?? .object([:])
                    requests.append(DeviceRequest(id: device.requestId, key: batch.items[itemIndex].key, config: config))
                }
                batch.items[itemIndex].status = Self.leastFinished(batch.items[itemIndex].devices)
            }
            batch.summary = Self.summary(batch.items)
            batches[batchId] = batch
        }
        return SyncResponse(
            deviceId: deviceId, policy: policy, requests: requests,
            apps: (appsByChild[childId] ?? []).map { AppRule(name: $0.name, approval: $0.approval, dailyLimitMinutes: $0.dailyLimitMinutes) },
            fullReportRequested: fullReportRequested.contains(deviceId), nextSyncSeconds: 300, timezone: family.timezone,
            features: SyncFeatures(locationSharing: entitlements.hasLocationSharing), minAppVersion: nil
        )
    }

    private func touchDevice(_ deviceId: String) {
        guard let childId = childId(ofDevice: deviceId), let index = devicesByChild[childId]?.firstIndex(where: { $0.id == deviceId }) else { return }
        devicesByChild[childId]?[index].lastSeenAt = .now
        devicesByChild[childId]?[index].lastSeenLabel = Date.now.verifiedDescription()
        refreshSummary(childId)
    }

    /// `POST /report`: an entry equal to the policy verifies open requests and passes the check;
    /// a different one fails them with "Device reported …".
    func recordDeviceReport(deviceId: String, entries: [ReportEntry], full: Bool) -> [IgnoredEntry] {
        guard let childId = childId(ofDevice: deviceId), var list = protectionsByChild[childId] else { return [] }
        var ignored: [IgnoredEntry] = []
        for entry in entries {
            guard let index = list.firstIndex(where: { $0.key == entry.key }) else {
                ignored.append(IgnoredEntry(key: entry.key, error: "Unknown protection"))
                continue
            }
            let reported = entry.config.setting("key", to: .string(entry.key))
            let matches = reported == list[index].policy
            let label = ProtectionConfigFormatter.label(key: entry.key, config: reported)
            list[index].devices = list[index].devices.map { device in
                guard device.deviceId == deviceId, device.capability != .unsupported else { return device }
                var copy = device
                copy.reported = reported
                copy.reportedLabel = label
                copy.status = matches ? .pass : .warning
                copy.message = matches ? "Verified with the device" : "Device reported \(label)"
                copy.lastVerifiedAt = .now
                return copy
            }
            list[index].status = list[index].devices.filter { $0.capability != .unsupported }.map(\.status).min { rank($0) < rank($1) } ?? list[index].status
            for (batchId, var batch) in batches where batch.childId == childId {
                for itemIndex in batch.items.indices where batch.items[itemIndex].key == entry.key {
                    for deviceIndex in batch.items[itemIndex].devices.indices where batch.items[itemIndex].devices[deviceIndex].deviceId == deviceId && !batch.items[itemIndex].devices[deviceIndex].status.isFinished {
                        batch.items[itemIndex].devices[deviceIndex].status = matches ? .verified : .failed
                        batch.items[itemIndex].devices[deviceIndex].failureReason = matches ? nil : "Device reported \(label)"
                    }
                    batch.items[itemIndex].status = Self.leastFinished(batch.items[itemIndex].devices)
                    if batch.items[itemIndex].status.isFinished { markOpen(childId: childId, key: entry.key, batchId: nil) }
                }
                batch.summary = Self.summary(batch.items)
                batch.done = batch.items.allSatisfy { $0.status.isFinished }
                batches[batchId] = batch
            }
        }
        protectionsByChild[childId] = list
        if full {
            fullReportRequested.remove(deviceId)
            // A check waiting on this device is complete.
            for (runId, _) in checkRuns { checkRuns[runId] = max(checkRuns[runId] ?? 0, 1) }
        }
        touchDevice(deviceId)
        return ignored
    }

    private var reportedUsage: [String: Int] = [:]

    func recordDeviceUsage(deviceId: String, usage: UsageRequest) {
        guard let childId = childId(ofDevice: deviceId) else { return }
        // Only today's total shows on the parent's dashboard; older days just land in history.
        guard usage.date == UsageTicks.localDate() else { return }
        reportedUsage[childId] = usage.totalMinutes
        refreshSummary(childId)
    }

    func recordDeviceLocation(deviceId: String, fix: LocationFix) {
        lastFixes[deviceId] = fix
        touchDevice(deviceId)
    }

    func recordDeviceEvent(deviceId: String, event: DeviceEvent) -> EventResponse {
        guard let childId = childId(ofDevice: deviceId), let child = summaries.first(where: { $0.id == childId }) else {
            return EventResponse(ok: true, approval: nil, duplicate: nil)
        }
        let deviceName = devicesByChild[childId]?.first { $0.id == deviceId }?.name ?? "the device"
        switch event.type {
        case .appRequested:
            guard let name = event.app else { return EventResponse(ok: true, approval: nil, duplicate: nil) }
            if let existing = appsByChild[childId]?.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                if existing.approval == .blocked, let index = appsByChild[childId]?.firstIndex(where: { $0.id == existing.id }) {
                    appsByChild[childId]?[index].requested = true
                }
                if existing.approval != .pending { return EventResponse(ok: true, approval: existing.approval, duplicate: nil) }
            } else {
                appsByChild[childId, default: []].append(app(name, .pending, limit: nil, today: 0))
            }
            alertsList.insert(makeAlert(childId: childId, deviceId: deviceId, severity: .attention, category: .apps, icon: "app-window", title: "App approval requested", body: "\(child.name) asked to use \(name) on \(deviceName).", subject: deviceName, age: 0, action: AlertAction(type: "REVIEW_APPS", label: "Review request", childId: childId, key: nil, deviceId: nil)), at: 0)
            return EventResponse(ok: true, approval: nil, duplicate: nil)
        case .appInstalled:
            guard let name = event.app else { break }
            if appsByChild[childId]?.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) != true {
                appsByChild[childId, default: []].append(app(name, .allowed, limit: nil, today: 0))
                alertsList.insert(makeAlert(childId: childId, deviceId: deviceId, severity: .info, category: .apps, icon: "app-window", title: "New app installed", body: "\(name) was installed on \(deviceName).", subject: deviceName, age: 0, dismissible: true, action: AlertAction(type: "REVIEW_APPS", label: "Review apps", childId: childId, key: nil, deviceId: nil)), at: 0)
            }
        case .appBlocked:
            alertsList.insert(makeAlert(childId: childId, deviceId: deviceId, severity: .info, category: .apps, icon: "app-window", title: "App blocked", body: "\(event.app ?? "An app") was blocked on \(deviceName).", subject: deviceName, age: 0, dismissible: true, action: nil), at: 0)
        case .limitReached:
            alertsList.insert(makeAlert(childId: childId, deviceId: deviceId, severity: .info, category: .screenTime, icon: "hourglass", title: "Screen time limit reached", body: "\(child.name) used today's screen time on \(deviceName).", subject: deviceName, age: 0, dismissible: true, action: AlertAction(type: "VIEW_SCREEN_TIME", label: "View screen time", childId: childId, key: nil, deviceId: nil)), at: 0)
        }
        return EventResponse(ok: true, approval: nil, duplicate: nil)
    }
}
