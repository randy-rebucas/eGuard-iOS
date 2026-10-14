import Foundation
import SwiftUI

// MARK: - Public

nonisolated struct AppInfo: Codable, Equatable, Sendable {
    struct SignInOptions: Codable, Equatable, Sendable {
        var password: Bool
        var apple: Bool
        var google: Bool
    }

    var name: String
    var apiVersion: String
    var minimumAppVersion: String
    var signIn: SignInOptions
    var supportEmail: String?

    /// True when the running app is older than the server's minimum.
    func requiresUpdate(currentVersion: String) -> Bool {
        Self.compare(currentVersion, minimumAppVersion) < 0
    }

    /// Numeric dotted-version comparison: "1.2" < "1.10".
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }
}

// MARK: - Lenient enums

/// Decodes a string enum, falling back to a safe case when the server adds a value this build doesn't know.
/// One new server value must never break decoding of a whole screen.
nonisolated func decodeLenient<T: RawRepresentable>(_ decoder: Decoder, fallback: T) throws -> T where T.RawValue == String {
    let raw = try decoder.singleValueContainer().decode(String.self)
    return T(rawValue: raw) ?? fallback
}

// MARK: - Auth and user

nonisolated enum UserRole: String, Codable, Sendable {
    case familyAdmin = "FAMILY_ADMIN"
    case parent = "PARENT"

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .parent) }

    var title: String {
        switch self {
        case .familyAdmin: "Family admin"
        case .parent: "Parent"
        }
    }
}

nonisolated struct FamilyRef: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var timezone: String
}

nonisolated struct NotificationPrefs: Codable, Equatable, Sendable {
    var notifyPush: Bool
    var notifyEmail: Bool
    var notifyApproval: Bool
    var weeklySummary: Bool
    /// Whether the plan sends push alerts at all. `notifyPush` is on by default, Free included, so without this the
    /// switch would read "on" for a plan that never pushes. nil from older servers.
    var pushIncluded: Bool?
}

/// Fields to change; `nil` means leave as is.
nonisolated struct NotificationPrefsPatch: Codable, Sendable {
    var notifyPush: Bool?
    var notifyEmail: Bool?
    var notifyApproval: Bool?
    var weeklySummary: Bool?
}

nonisolated struct APIUser: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var firstName: String
    var email: String
    var role: UserRole
    var family: FamilyRef
    var notifications: NotificationPrefs
    var twoFactor: Bool
    /// False for Apple/Google sign-ups that never set a password. Older servers omit it.
    var hasPassword: Bool?
    var emailVerified: Bool?
    var createdAt: Date

    var isAdmin: Bool { role == .familyAdmin }
    var isEmailVerified: Bool { emailVerified ?? true }
    /// Whether password-based confirmations apply. Without one, deletions use "Type DELETE".
    var canUsePassword: Bool { hasPassword ?? true }
}

nonisolated struct AuthResponse: Codable, Equatable, Sendable {
    var token: String
    var expiresAt: Date
    var user: APIUser
    var isNew: Bool?
    /// Set by `POST /auth/two-factor` when a recovery code was used instead of an authenticator code.
    var usedRecoveryCode: Bool?
    var recoveryCodesLeft: Int?

    var session: APISession { APISession(token: token, expiresAt: expiresAt) }
}

/// Returned instead of a session when two-step verification is on. No session exists yet.
nonisolated struct TwoFactorChallenge: Codable, Hashable, Sendable {
    var challenge: String
    var expiresAt: Date
    var isNew: Bool?
}

/// The two shapes a sign-in call can answer with.
nonisolated enum LoginResult: Decodable, Equatable, Sendable {
    case signedIn(AuthResponse)
    case twoFactorRequired(TwoFactorChallenge)

    private enum CodingKeys: String, CodingKey { case twoFactorRequired }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .twoFactorRequired) == true {
            self = .twoFactorRequired(try TwoFactorChallenge(from: decoder))
        } else {
            self = .signedIn(try AuthResponse(from: decoder))
        }
    }

    var auth: AuthResponse? {
        if case .signedIn(let response) = self { return response }
        return nil
    }
}

nonisolated enum SocialProvider: String, Codable, Sendable {
    case apple
    case google

    var title: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}

nonisolated struct OKResponse: Codable, Sendable {
    var ok: Bool?
    var message: String?
}

nonisolated struct VerificationSend: Codable, Sendable {
    var sent: Bool
    var email: String?
}

nonisolated struct SessionInfo: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// null on the server when the client sent none: one such session must not fail the whole list.
    var userAgent: String?
    var createdAt: Date
    var lastSeenAt: Date?
    var current: Bool
}

/// What a parent must send to delete the account, a child, a device, or a browser.
/// Parents with a password send it; Apple/Google parents without one type DELETE instead.
nonisolated enum DeletionConfirmation: Encodable, Equatable, Sendable {
    case password(String)
    case typedDelete

    private enum CodingKeys: String, CodingKey { case password, confirm }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .password(let password): try container.encode(password, forKey: .password)
        case .typedDelete: try container.encode("DELETE", forKey: .confirm)
        }
    }

    /// Whether the typed text satisfies the confirmation the account needs.
    static func make(user: APIUser?, input: String) -> DeletionConfirmation? {
        if user?.canUsePassword ?? true {
            return input.isEmpty ? nil : .password(input)
        }
        return input.trimmingCharacters(in: .whitespaces) == "DELETE" ? .typedDelete : nil
    }
}

nonisolated struct AccountDeleted: Codable, Sendable {
    var ok: Bool?
    /// `"family"` when the admin's account took the whole family with it, `"account"` otherwise.
    var deleted: String?
}

/// A linked Apple or Google sign-in, from `GET /me/identities`.
nonisolated struct LinkedIdentity: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var provider: String
    var email: String?
    var createdAt: Date?

    var providerTitle: String { SocialProvider(rawValue: provider)?.title ?? provider.capitalized }
}

nonisolated struct TwoFactorStatus: Codable, Equatable, Sendable {
    /// False when the server isn't set up for two-step verification; hide the option then.
    var available: Bool
    var enabled: Bool
    var recoveryCodesLeft: Int?
}

nonisolated struct TwoFactorSetup: Codable, Equatable, Sendable {
    var secret: String
    /// An `otpauth://` link for a QR code or for handing to an authenticator app on this phone.
    var uri: String
}

nonisolated struct RecoveryCodes: Codable, Sendable {
    var recoveryCodes: [String]
}

/// `GET /auth/invite?token=`: which family an invitation is for, shown before accepting.
nonisolated struct InvitationPreview: Codable, Equatable, Sendable {
    var name: String
    var email: String
    var familyName: String
    var invitedBy: String?
}

nonisolated struct InvitationDeclined: Codable, Sendable {
    var ok: Bool?
    var familyName: String?
}

// MARK: - Children and devices

nonisolated enum ChildStatus: String, Codable, Sendable {
    case protected
    case attention
    case notconfigured

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .attention) }

    var title: String {
        switch self {
        case .protected: "Protected"
        case .attention: "Attention"
        case .notconfigured: "Not set up"
        }
    }
}

nonisolated struct HealthScore: Codable, Equatable, Sendable {
    var score: Int
    var total: Int
    var label: String?
    /// Devices that haven't synced in over a day. They're scored by their last known state.
    var offline: Int?
    /// True only when every check passes and no device is offline. Only then say "verified".
    var verified: Bool?

    init(score: Int, total: Int, label: String? = nil, offline: Int? = nil, verified: Bool? = nil) {
        self.score = score
        self.total = total
        self.label = label
        self.offline = offline
        self.verified = verified
    }

    var text: String { total == 0 ? "–" : "\(score) / \(total)" }
    var fraction: Double { total == 0 ? 0 : Double(score) / Double(total) }
    var offlineCount: Int { offline ?? 0 }
    var isVerified: Bool { verified ?? (total > 0 && score >= total && offlineCount == 0) }

    /// The server's `healthLabel` thresholds, used when `label` is absent.
    var grade: String {
        if let label { return label }
        if total == 0 { return "No devices yet" }
        if score >= total { return offlineCount > 0 ? "Last known: all set" : "Fully protected" }
        if score >= total - 2 { return "Good protection" }
        if Double(score) >= Double(total) / 2 { return "Needs attention" }
        return "Action required"
    }

    /// A one-line note about offline devices, or nil when every device reported recently.
    var offlineNote: String? {
        guard offlineCount > 0 else { return nil }
        return offlineCount == 1
            ? "1 device is offline and shows its last known state."
            : "\(offlineCount) devices are offline and show their last known state."
    }
}

nonisolated enum DevicePlatformKind: String, Codable, Sendable {
    case android = "ANDROID"
    case ios = "IOS"

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .android) }

    var title: String {
        switch self {
        case .android: "Android"
        case .ios: "iOS"
        }
    }
}

nonisolated struct PrimaryDevice: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var platform: DevicePlatformKind
}

nonisolated struct ChildSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var age: Int
    var birthYear: Int?
    var hue: Int
    var photoUrl: String?
    var status: ChildStatus
    var health: HealthScore
    var dailyLimitMinutes: Int?
    var weekendLimitMinutes: Int?
    var todayLimitMinutes: Int?
    var todayMinutes: Int?
    /// Phones and tablets paired.
    var deviceCount: Int
    /// Connected browser extensions (absent on older servers).
    var browserCount: Int? = nil
    var primaryDevice: PrimaryDevice?

    /// No phone or tablet to verify, but a browser is connected: "Browser only", as on the web.
    var isBrowserOnly: Bool { deviceCount == 0 && (browserCount ?? 0) > 0 }
    var ageDescription: String { "\(age) years old" }
    var deviceName: String { primaryDevice?.name ?? "\(name)'s device" }
}

nonisolated enum DeviceState: String, Codable, Sendable {
    case healthy
    case issues
    case offline

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .issues) }

    var title: String {
        switch self {
        case .healthy: "Healthy"
        case .issues: "Issues"
        case .offline: "Offline"
        }
    }
}

nonisolated struct APIDevice: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var childId: String
    var childName: String
    var name: String
    var model: String?
    var kind: String
    var platform: DevicePlatformKind
    var osVersion: String?
    var appVersion: String?
    var battery: Int?
    var isPrimary: Bool
    var lastSeenAt: Date?
    var lastSeenLabel: String?
    var state: DeviceState
    var issues: Int
    /// Just paired or moved, nothing reported yet: `issues` counts every protection, so say "Waiting for first check".
    var firstCheck: Bool? = nil

    var symbolName: String { kind == "TABLET" ? "ipad" : "iphone" }
    /// The pill's words, as the web's device card: offline first, then waiting, then issues.
    var statusTitle: String {
        if state == .offline { return state.title }
        if firstCheck == true { return "Waiting for first check" }
        return issues > 0 ? "\(issues) issue\(issues == 1 ? "" : "s")" : state.title
    }
}

nonisolated struct DevicesResponse: Codable, Sendable {
    var devices: [APIDevice]
    var limit: Int?
    /// Slots the limit counts (these devices plus connected browsers), as pairing counts them. Nil from older servers.
    var used: Int? = nil
}

nonisolated struct DeviceProtectionStatus: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var name: String
    var icon: String?
    var capability: Capability
    var capabilityLabel: String?
    var status: CheckStatus
    var reportedLabel: String?
    var message: String?
    var lastVerifiedAt: Date?

    var id: String { key }
    /// The status as the parent reads it: "Set by you" or "Not set up yet" for a PARENT_SET protection.
    var statusTitle: String { capability.statusTitle(status) }
    var displayStatus: HealthStatus { capability.healthStatus(status) }
}

nonisolated struct DeviceDetail: Codable, Equatable, Sendable {
    var id: String
    var childId: String
    var childName: String
    var name: String
    var model: String?
    var kind: String
    var platform: DevicePlatformKind
    var osVersion: String?
    var appVersion: String?
    var battery: Int?
    var isPrimary: Bool
    var lastSeenAt: Date?
    var lastSeenLabel: String?
    var state: DeviceState
    var issues: Int
    var firstCheck: Bool? = nil
    var protections: [DeviceProtectionStatus]

    var device: APIDevice {
        APIDevice(id: id, childId: childId, childName: childName, name: name, model: model, kind: kind, platform: platform, osVersion: osVersion, appVersion: appVersion, battery: battery, isPrimary: isPrimary, lastSeenAt: lastSeenAt, lastSeenLabel: lastSeenLabel, state: state, issues: issues, firstCheck: firstCheck)
    }
}

nonisolated struct CheckRun: Codable, Equatable, Sendable {
    struct Result: Codable, Equatable, Identifiable, Sendable {
        var deviceId: String
        var deviceName: String
        var childName: String
        var reachable: Bool?
        var issues: Int?
        var reported: Bool

        var id: String { deviceId }
    }

    var status: String
    var done: Bool
    var health: HealthScore
    var results: [Result]
}

nonisolated struct CheckStarted: Codable, Sendable {
    var runId: String
}

nonisolated struct PairingCode: Codable, Equatable, Sendable {
    var code: String
    var expiresAt: Date
    var childName: String
    /// `"BROWSER"` for an eGuard browser extension code; nil or `"DEVICE"` for the phone app.
    var kind: String?
    /// How long the code lasts from when the response arrived. Count down from this, not `expiresAt`: the phone's
    /// clock may be off.
    var expiresInSeconds: Int? = nil

    var isBrowserCode: Bool { kind == "BROWSER" }
}

nonisolated struct PhotoUploadResponse: Codable, Sendable {
    var photoUrl: String
}

/// An eGuard browser extension install, from `GET /browsers`.
nonisolated struct ConnectedBrowser: Codable, Equatable, Identifiable, Sendable {
    /// The web card's words: disconnected and a day's silence already override what the extension last reported.
    struct Status: Codable, Equatable, Sendable {
        /// `ok`, `warn`, `crit`, `muted` or `accent`.
        var tone: String
        var label: String
        var note: String?
    }

    var id: String
    var childId: String
    var childName: String
    var deviceLabel: String
    var browser: String?
    var browserVersion: String?
    var extensionVersion: String?
    var platform: String?
    var lastSeenAt: Date?
    /// False when eGuard disconnected it for security; remove it and add it again.
    var connected: Bool
    var createdAt: Date?
    /// Nil from older servers.
    var status: Status? = nil

    var detail: String {
        // Major version only, as the web card shows it
        let name = [browser, browserVersion?.split(separator: ".").first.map(String.init)].compactMap { $0 }.joined(separator: " ")
        return [name.isEmpty ? nil : name, extensionVersion.map { "eGuard \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    var statusLabel: String { status?.label ?? (connected ? "Connected" : "Disconnected for security") }
}

nonisolated struct BrowsersResponse: Codable, Sendable {
    var browsers: [ConnectedBrowser]
}

/// A website the child asked to open from the browser's block page.
nonisolated struct BrowserAccessRequest: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var domain: String
    var reason: String?
    var status: String
    var duration: String?
    var expiresAt: Date?
    var createdAt: Date
    var decidedAt: Date?
    var decidedBy: String?

    var isPending: Bool { status == "PENDING" }
}

nonisolated struct BrowserAccessRequests: Codable, Equatable, Sendable {
    var pending: [BrowserAccessRequest]
    var recent: [BrowserAccessRequest]
}

/// How long an approved website stays open: `15M`, `1H`, `TODAY` or `ALWAYS`.
nonisolated enum BrowserAccessDuration: String, CaseIterable, Codable, Identifiable, Sendable {
    case fifteenMinutes = "15M"
    case oneHour = "1H"
    case today = "TODAY"
    case always = "ALWAYS"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .today: "Until midnight"
        case .always: "Always"
        }
    }
}

nonisolated enum BrowserAccessDecision: Encodable, Equatable, Sendable {
    case approve(BrowserAccessDuration)
    case deny

    private enum CodingKeys: String, CodingKey { case decision, duration }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .approve(let duration):
            try container.encode("APPROVE", forKey: .decision)
            try container.encode(duration, forKey: .duration)
        case .deny:
            try container.encode("DENY", forKey: .decision)
        }
    }
}

nonisolated struct BrowserAccessDecided: Codable, Sendable {
    var request: BrowserAccessRequest
}

nonisolated struct BrowserSchedule: Codable, Equatable, Sendable {
    var enabled: Bool
    var startTime: String
    var endTime: String
}

nonisolated struct BrowserCategory: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var label: String
    var hint: String?

    var id: String { key }
}

/// A YouTube Restricted Mode level with the web's label and description.
nonisolated struct BrowserYoutubeLevel: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var label: String
    var text: String?

    var id: String { key }
}

/// The policy every eGuard browser extension of a child follows, from `GET /children/{id}/browser-policy`.
nonisolated struct BrowserPolicy: Codable, Equatable, Sendable {
    var version: Int
    var safeBrowsing: Bool
    var safeSearch: Bool
    /// YouTube Restricted Mode: `OFF`, `MODERATE` or `STRICT`; nil from servers that don't have it.
    var youtubeRestrict: String? = nil
    var blockedCategories: [String]
    var blockedDomains: [String]
    var allowedDomains: [String]
    var unknownSitesPolicy: String
    var schedule: BrowserSchedule?
    var updatedBy: String?
    var updatedAt: Date?
    var categories: [BrowserCategory]?
    var youtubeLevels: [BrowserYoutubeLevel]? = nil

    /// The body for `PUT`, with `baseVersion` so a concurrent edit is refused instead of undone.
    var update: BrowserPolicyUpdate {
        BrowserPolicyUpdate(
            safeBrowsing: safeBrowsing, safeSearch: safeSearch, blockedCategories: blockedCategories,
            blockedDomains: blockedDomains, allowedDomains: allowedDomains, unknownSitesPolicy: unknownSitesPolicy,
            schedule: schedule, baseVersion: version, youtubeRestrict: youtubeRestrict
        )
    }
}

nonisolated struct BrowserPolicyUpdate: Encodable, Equatable, Sendable {
    var safeBrowsing: Bool
    var safeSearch: Bool
    var blockedCategories: [String]
    var blockedDomains: [String]
    var allowedDomains: [String]
    var unknownSitesPolicy: String
    var schedule: BrowserSchedule?
    var baseVersion: Int?
    /// Left out when nil: the server keeps the saved level.
    var youtubeRestrict: String? = nil

    private enum CodingKeys: String, CodingKey {
        case safeBrowsing, safeSearch, youtubeRestrict, blockedCategories, blockedDomains, allowedDomains, unknownSitesPolicy, schedule, baseVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(safeBrowsing, forKey: .safeBrowsing)
        try container.encode(safeSearch, forKey: .safeSearch)
        try container.encodeIfPresent(youtubeRestrict, forKey: .youtubeRestrict)
        try container.encode(blockedCategories, forKey: .blockedCategories)
        try container.encode(blockedDomains, forKey: .blockedDomains)
        try container.encode(allowedDomains, forKey: .allowedDomains)
        try container.encode(unknownSitesPolicy, forKey: .unknownSitesPolicy)
        // `schedule` is required and may be explicitly null.
        if let schedule { try container.encode(schedule, forKey: .schedule) } else { try container.encodeNil(forKey: .schedule) }
        try container.encodeIfPresent(baseVersion, forKey: .baseVersion)
    }
}

// MARK: - Health and checks

nonisolated enum CheckStatus: String, Codable, Sendable {
    case pass = "PASS"
    case warning = "WARNING"
    case actionRequired = "ACTION_REQUIRED"
    case notConfigured = "NOT_CONFIGURED"
    case unsupported = "UNSUPPORTED"

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .warning) }

    var title: String {
        switch self {
        case .pass: "Active"
        case .warning: "Needs review"
        case .actionRequired: "Action required"
        case .notConfigured: "Not configured"
        case .unsupported: "Not supported"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .warning, .actionRequired, .notConfigured: true
        case .pass, .unsupported: false
        }
    }

    /// The local `HealthStatus` used by the design system's colors and symbols.
    var healthStatus: HealthStatus {
        switch self {
        case .pass: .pass
        case .warning: .warning
        case .actionRequired: .actionRequired
        case .notConfigured: .notConfigured
        case .unsupported: .unsupported
        }
    }
}

nonisolated struct HealthCheck: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var name: String
    var icon: String?
    var status: CheckStatus
    var detail: String?
    var fixDeviceId: String?
    var fixChildId: String?
    /// True when the status is UNSUPPORTED only because the parent set it on the device (PARENT_SET): "Set by you".
    /// Absent on older servers.
    var parentSet: Bool? = nil

    var id: String { key }
    var isParentSet: Bool { parentSet == true }
    /// The status as the parent reads it, "Set by you" included.
    var displayStatus: HealthStatus { isParentSet ? .setByYou : status.healthStatus }
}

nonisolated struct FixItem: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var name: String
    var status: CheckStatus
    var detail: String?
    /// The server sends `null` for family-wide items that aren't tied to one child.
    var childId: String?
    var deviceId: String?

    var id: String { key + (childId ?? "") }
}

nonisolated struct ChildHealth: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var score: Int
    var total: Int
    var status: ChildStatus
}

nonisolated struct HealthReport: Codable, Equatable, Sendable {
    var score: Int
    var total: Int
    var label: String?
    var offline: Int?
    var verified: Bool?
    var checks: [HealthCheck]
    var toFix: [FixItem]?
    var children: [ChildHealth]?

    init(score: Int, total: Int, label: String? = nil, offline: Int? = nil, verified: Bool? = nil, checks: [HealthCheck], toFix: [FixItem]? = nil, children: [ChildHealth]? = nil) {
        self.score = score
        self.total = total
        self.label = label
        self.offline = offline
        self.verified = verified
        self.checks = checks
        self.toFix = toFix
        self.children = children
    }

    var healthScore: HealthScore { HealthScore(score: score, total: total, label: label, offline: offline, verified: verified) }
    var fixCount: Int { toFix?.count ?? checks.filter { $0.status.needsAttention }.count }
}

// MARK: - Dashboard

nonisolated struct Dashboard: Codable, Equatable, Sendable {
    var user: APIUser
    var greeting: String
    var summary: String
    var health: HealthScore
    var children: [ChildSummary]
    /// Phones and tablets.
    var deviceCount: Int
    /// Connected browser extensions (absent on older servers). Each takes a device slot, like a phone.
    var browserCount: Int? = nil
    var recentAlerts: [APIAlert]
    var unreadAlerts: Int

    /// What the web's Devices card counts: phones, tablets and browsers.
    var connectedDevices: Int { deviceCount + (browserCount ?? 0) }
}

// MARK: - Onboarding

nonisolated struct ProfileOption: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String
    var icon: String?
    var recommended: Bool
}

nonisolated struct ProfilesResponse: Codable, Sendable {
    var profiles: [ProfileOption]
}

nonisolated enum Capability: String, Codable, Sendable {
    case available = "AVAILABLE"
    case guided = "GUIDED"
    case verifyOnly = "VERIFY_ONLY"
    /// The parent sets it in another app on the device (Google Play's ratings on Android) and confirms. eGuard can't
    /// read it back: once confirmed the device's row is UNSUPPORTED, shown as "Set by you", not verified.
    case parentSet = "PARENT_SET"
    case unsupported = "UNSUPPORTED"

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .verifyOnly) }

    var title: String {
        switch self {
        case .available: "Available"
        case .guided: "Guided"
        case .verifyOnly: "Verify only"
        case .parentSet: "Set by you"
        case .unsupported: "Not supported"
        }
    }

    /// The local mode used by the design system's badge colors.
    var mode: ConfigurationMode {
        switch self {
        case .available: .automatic
        case .guided, .parentSet: .guided
        case .verifyOnly: .verificationOnly
        case .unsupported: .unsupported
        }
    }

    /// The parent follows steps on the device and confirms them ("I've done these steps").
    var isGuided: Bool { self == .guided || self == .verifyOnly || self == .parentSet }

    /// A device's status for a protection with this capability, as the parent reads it: a PARENT_SET protection is
    /// "Set by you" once confirmed (the server stores it as UNSUPPORTED) and "Not set up yet" before.
    func statusTitle(_ status: CheckStatus) -> String {
        guard self == .parentSet else { return status.title }
        return status == .unsupported ? HealthStatus.setByYou.title : "Not set up yet"
    }

    /// The design system's status for a device row with this capability.
    func healthStatus(_ status: CheckStatus) -> HealthStatus {
        self == .parentSet && status == .unsupported ? .setByYou : status.healthStatus
    }
}

nonisolated struct RecommendedDevice: Codable, Equatable, Identifiable, Sendable {
    var deviceId: String
    var deviceName: String
    var capability: Capability
    var capabilityLabel: String?

    var id: String { deviceId }
}

nonisolated struct RecommendedSetting: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var name: String
    var icon: String?
    var config: JSONValue
    var label: String
    var devices: [RecommendedDevice]

    var id: String { key }
}

nonisolated struct Recommendations: Codable, Equatable, Sendable {
    var childId: String
    var age: Int
    var profile: String
    var settings: [RecommendedSetting]
}

nonisolated struct SetupRequest: Codable, Sendable {
    var profile: String
    var overrides: [JSONValue]
}

nonisolated struct SetupResponse: Codable, Equatable, Sendable {
    var batchId: String?
    var requested: [String]
    var saved: [String]
    var progress: Batch?
}

// MARK: - Batches

nonisolated enum RequestStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case delivered = "DELIVERED"
    case awaitingParent = "AWAITING_PARENT"
    case verified = "VERIFIED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .pending) }

    var title: String {
        switch self {
        case .pending: "Sending to device"
        case .delivered: "Waiting for verification"
        case .awaitingParent: "Finish on the device"
        case .verified: "Verified"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var isFinished: Bool {
        switch self {
        case .verified, .failed, .cancelled: true
        default: false
        }
    }
}

nonisolated struct BatchDevice: Codable, Equatable, Identifiable, Sendable {
    var requestId: String
    var deviceId: String
    var deviceName: String
    var platform: DevicePlatformKind
    var mode: String
    var status: RequestStatus
    var failureReason: String?
    var offline: Bool
    var from: String?
    var guide: [String]?
    /// The protection is PARENT_SET on this device: VERIFIED means the parent said they set it, not that the device
    /// checked it. Absent on older servers.
    var parentSet: Bool? = nil

    var id: String { requestId }
    var isGuided: Bool { mode == "GUIDED" }
    var isParentSet: Bool { parentSet == true }
    /// The status in words: a confirmed PARENT_SET step is "Set by you, not verified", never "Verified".
    var statusTitle: String { isParentSet && status == .verified ? "Set by you, not verified" : status.title }
}

nonisolated struct BatchItem: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var name: String
    var icon: String?
    var status: RequestStatus
    var to: String?
    var devices: [BatchDevice]

    var id: String { key }
    var guide: [String]? { devices.first { $0.guide?.isEmpty == false }?.guide }
    var failureReason: String? { devices.compactMap(\.failureReason).first }
    var isOffline: Bool { devices.contains { $0.offline && !$0.status.isFinished } }
    /// Every device's step is PARENT_SET: confirming saves it as set by the parent, nothing is verified.
    var isParentSetOnly: Bool { !devices.isEmpty && devices.allSatisfy(\.isParentSet) }
    /// The status in words: "Set by you, not verified" rather than "Verified" for a PARENT_SET step.
    var statusTitle: String { isParentSetOnly && status == .verified ? "Set by you, not verified" : status.title }
}

nonisolated struct BatchSummary: Codable, Equatable, Sendable {
    var total: Int
    /// Done: checked by a device, or set by the parent (`setByYou` is part of it).
    var verified: Int
    /// Of `verified`, the PARENT_SET items the parent confirmed: done, but not checked by a device. Absent on older servers.
    var setByYou: Int?
    var failed: Int
    var awaitingParent: Int
    var inProgress: Int
    var cancelled: Int

    var setByYouCount: Int { setByYou ?? 0 }

    /// "3 of 10 done", plus "· 2 set by you" when some were set by the parent. Not "verified": those weren't checked.
    var progressText: String {
        let done = "\(verified) of \(total) done"
        return setByYouCount > 0 ? "\(done) · \(setByYouCount) set by you" : done
    }
}

nonisolated struct Batch: Codable, Equatable, Sendable {
    var batchId: String
    var childId: String
    var done: Bool
    var summary: BatchSummary
    var items: [BatchItem]
    var health: HealthScore
    var confirmed: Int?

    var verifiedItems: [BatchItem] { items.filter { $0.status == .verified } }
}

nonisolated struct CancelResponse: Codable, Sendable {
    var cancelled: Int
}

// MARK: - Child detail and protections

nonisolated struct TopApp: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var minutes: Int

    var id: String { name }
}

nonisolated struct TodaySummary: Codable, Equatable, Sendable {
    var minutes: Int
    var limitMinutes: Int?
    var appsUsed: Int
    var topApps: [TopApp]
}

nonisolated struct BedtimeInfo: Codable, Equatable, Sendable {
    var enabled: Bool
    var start: String
    var end: String
    var days: String
    var label: String
}

/// Where a child's location stands: the same values as `GET /locations`, plus `plan_required`.
nonisolated enum LocationState: String, Sendable {
    case located
    case waiting
    case sharingOff = "sharing_off"
    case noDevices = "no_devices"
    case planRequired = "plan_required"

    var title: String {
        switch self {
        case .located: "Sharing enabled"
        case .waiting: "Waiting for location"
        case .sharingOff: "Sharing off"
        case .noDevices: "No devices yet"
        case .planRequired: "Not on your plan"
        }
    }
}

nonisolated struct LocationInfo: Codable, Equatable, Sendable {
    var sharing: Bool
    var state: String?
    var placeLabel: String?
    var updatedAt: Date?
    var label: String

    var locationState: LocationState? { state.flatMap(LocationState.init(rawValue:)) }
}

nonisolated struct DeviceProtectionInfo: Codable, Equatable, Sendable {
    var state: String
    var label: String
}

nonisolated struct ChangeRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var key: String
    var title: String
    var actor: String
    var fromValue: String?
    var toValue: String?
    var createdAt: Date
    var timeLabel: String?
}

nonisolated struct ChildDetail: Codable, Equatable, Sendable {
    var child: ChildSummary
    var health: HealthReport
    var today: TodaySummary
    var bedtime: BedtimeInfo?
    var location: LocationInfo
    var deviceProtection: DeviceProtectionInfo
    var pendingApprovals: Int
    var devices: [APIDevice]
    var recentChanges: [ChangeRecord]
}

nonisolated struct HistoryPage: Codable, Equatable, Sendable {
    var changes: [ChangeRecord]
    var nextBefore: Date?
}

nonisolated struct ProtectionDevice: Codable, Equatable, Identifiable, Sendable {
    var deviceId: String
    var deviceName: String
    var platform: DevicePlatformKind
    var capability: Capability
    var status: CheckStatus
    var reported: JSONValue?
    var reportedLabel: String?
    var message: String?
    var lastVerifiedAt: Date?
    var guide: [String]?

    var id: String { deviceId }
    /// The status as the parent reads it: "Set by you" or "Not set up yet" for a PARENT_SET protection.
    var statusTitle: String { capability.statusTitle(status) }
    var displayStatus: HealthStatus { capability.healthStatus(status) }
}

nonisolated struct Protection: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var name: String
    var checkName: String?
    var icon: String?
    var policy: JSONValue
    var policyLabel: String
    var status: CheckStatus
    var openBatchId: String?
    /// Sent back as `baseVersion` when saving, so a change another parent made or queued since is refused (`409 stale`).
    var version: String? = nil
    var devices: [ProtectionDevice]

    var id: String { key }

    /// True when no device can apply it, so the control should be disabled.
    var isUnsupportedEverywhere: Bool {
        !devices.isEmpty && devices.allSatisfy { $0.capability == .unsupported }
    }

    /// UNSUPPORTED only because the parent set it on a device (PARENT_SET), as the server's health check says
    /// "Set by you" rather than "Not supported".
    var isParentSet: Bool {
        status == .unsupported && devices.contains { $0.capability == .parentSet && $0.status == .unsupported }
    }

    var displayStatus: HealthStatus { isParentSet ? .setByYou : status.healthStatus }
}

/// What `PUT /children/{id}/protections/{KEY}` did: a change for the devices to verify (202 `Batch`), or, for a child
/// with no device yet, saved as their setting and applied when one pairs (200 `{ batchId: null, saved }`).
nonisolated enum ProtectionUpdate: Decodable, Sendable {
    case queued(Batch)
    case savedForPairing

    var batch: Batch? {
        if case .queued(let batch) = self { return batch }
        return nil
    }

    private enum CodingKeys: String, CodingKey { case batchId }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(String.self, forKey: .batchId) == nil {
            self = .savedForPairing
        } else {
            self = .queued(try Batch(from: decoder))
        }
    }
}

nonisolated struct ProtectionsResponse: Codable, Sendable {
    var protections: [Protection]
}

// MARK: - Screen time

nonisolated enum ScreenTimePeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week = "7d"
    case month = "30d"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }
}

nonisolated struct DayMinutes: Codable, Equatable, Identifiable, Sendable {
    var date: String
    var minutes: Int
    var limitMinutes: Int?

    var id: String { date }
}

nonisolated struct AppUsage: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var minutes: Int
    var appId: String?
    var approval: AppApproval?
    var dailyLimitMinutes: Int?

    var id: String { appId ?? name }
}

/// `GET /children/{id}/extra-time`: running extra time (`until`, nil when none) and the child's open request for more.
nonisolated struct ExtraTime: Codable, Equatable, Sendable {
    nonisolated struct Request: Codable, Equatable, Sendable {
        var body: String
        var askedAt: Date
    }

    var until: Date?
    var request: Request?
    /// Minutes a parent can give at once.
    var choices: [Int]

    /// Extra time that hasn't ended yet (the server sends `until` only while it runs, but the screen can sit open).
    func isRunning(now: Date = .now) -> Bool { until.map { $0 > now } ?? false }
}

/// `POST /children/{id}/extra-time`. `addedMinutes` can be less than asked: extra time never runs more than 4 hours
/// ahead (absent on older servers).
nonisolated struct ExtraTimeGrant: Codable, Equatable, Sendable {
    var until: Date
    var addedMinutes: Int?
}

/// Tabs the plan doesn't include (`["30d"]`) and what to say about them.
nonisolated struct ScreenTimeLock: Codable, Equatable, Sendable {
    var periods: [String]
    var message: String
}

nonisolated struct ScreenTimeReport: Codable, Equatable, Sendable {
    var period: String
    var from: String
    var to: String
    var totalMinutes: Int
    /// Over complete days only (today is still in progress); for `today`, today's total.
    var averageMinutes: Int
    /// nil for `today`: nothing complete to compare.
    var previousAverageMinutes: Int?
    var limitMinutes: Int?
    var days: [DayMinutes]
    var hourly: [Int]?
    var apps: [AppUsage]
    /// Apps left unnamed because of the plan's `appMonitoringLimit`; 0 or absent otherwise.
    var hiddenApps: Int?
    var completeDays: Int?
    /// Phones and tablets paired to the child (browsers don't send screen time). nil from older servers.
    var deviceCount: Int?
    /// Sent with every period, so the 30-day tab is locked before it's tapped.
    var locked: ScreenTimeLock?

    var hiddenAppCount: Int { hiddenApps ?? 0 }

    /// A `YYYY-MM-DD` day from the server: a calendar day in the family's time zone. Parsed at UTC midnight with a
    /// fixed calendar, so neither the phone's time zone nor a Buddhist or Japanese calendar moves it; format it in UTC.
    static func day(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    /// "Oct 7 – Oct 13" for a multi-day report, nil for one day.
    var rangeLabel: String? {
        guard from != to, let start = Self.day(from), let end = Self.day(to) else { return nil }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = TimeZone(identifier: "UTC")!
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    /// "↓ 12% vs last week"-style change, or nil when there is nothing to compare.
    var changePercent: Int? {
        guard let previous = previousAverageMinutes, previous > 0 else { return nil }
        return Int((Double(averageMinutes - previous) / Double(previous) * 100).rounded())
    }
}

// MARK: - Apps

nonisolated enum AppApproval: String, Codable, Sendable {
    case allowed = "ALLOWED"
    case alwaysAllowed = "ALWAYS_ALLOWED"
    case filtered = "FILTERED"
    case blocked = "BLOCKED"
    case pending = "PENDING"

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .allowed) }

    var title: String {
        switch self {
        case .allowed: "Allowed"
        case .alwaysAllowed: "Always allowed"
        case .filtered: "Filtered (blocked)"
        case .blocked: "Blocked"
        case .pending: "Ask parent"
        }
    }
}

nonisolated enum AppsFilter: String, CaseIterable, Identifiable, Sendable {
    case installed
    case blocked
    case pending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed: "Installed"
        case .blocked: "Blocked"
        case .pending: "Pending"
        }
    }
}

nonisolated struct ChildApp: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var approval: AppApproval
    var approvalLabel: String
    /// True while a request waits for the parent, including a blocked app the child asked for again.
    var requested: Bool?
    var allowed: Bool
    var dailyLimitMinutes: Int?
    var todayMinutes: Int?
    var installedAt: Date?

    init(id: String, name: String, approval: AppApproval, approvalLabel: String, requested: Bool? = nil, allowed: Bool, dailyLimitMinutes: Int?, todayMinutes: Int?, installedAt: Date?) {
        self.id = id
        self.name = name
        self.approval = approval
        self.approvalLabel = approvalLabel
        self.requested = requested
        self.allowed = allowed
        self.dailyLimitMinutes = dailyLimitMinutes
        self.todayMinutes = todayMinutes
        self.installedAt = installedAt
    }

    /// Show Approve and Decline while this is true, even for an app that is already blocked.
    var isRequested: Bool { requested ?? (approval == .pending) }

    /// Blocked on the device: `FILTERED` is enforced like `BLOCKED` (child-app-spec §7).
    var isBlocked: Bool { approval == .blocked || approval == .filtered }

    /// The design's subtitle: "Always allowed", "1 hour/day", "Ask parent", or "Blocked".
    var subtitle: String {
        switch approval {
        case .alwaysAllowed: return "Always allowed"
        case .pending: return "Ask parent"
        case .blocked: return isRequested ? "Blocked · asked again" : "Blocked"
        case .filtered: return isRequested ? "Filtered (blocked) · asked again" : "Filtered (blocked)"
        case .allowed:
            if let minutes = dailyLimitMinutes {
                return ProtectionSettings.formatDailyAllowance(minutes).replacingOccurrences(of: " / day", with: "/day")
            }
            return approvalLabel
        }
    }
}

nonisolated struct AppCounts: Codable, Equatable, Sendable {
    var all: Int
    var blocked: Int
    var pending: Int
    var installed: Int
}

/// Set on plans with an `appMonitoringLimit`: how many more apps exist than are listed.
nonisolated struct AppsLimited: Codable, Equatable, Sendable {
    var hidden: Int
    var message: String
}

nonisolated struct AppsResponse: Codable, Equatable, Sendable {
    var counts: AppCounts
    var apps: [ChildApp]
    var limited: AppsLimited?

    init(counts: AppCounts, apps: [ChildApp], limited: AppsLimited? = nil) {
        self.counts = counts
        self.apps = apps
        self.limited = limited
    }
}

nonisolated struct AppRuleUpdate: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var approval: AppApproval
    var approvalLabel: String
    var dailyLimitMinutes: Int?
}

nonisolated struct AppPatch: Codable, Sendable {
    var approval: AppApproval?
    /// Encoded as `null` when `removeLimit` is set, so the server clears the limit.
    var dailyLimitMinutes: Int?
    var removeLimit = false

    enum CodingKeys: String, CodingKey { case approval, dailyLimitMinutes }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(approval, forKey: .approval)
        if removeLimit {
            try container.encodeNil(forKey: .dailyLimitMinutes)
        } else {
            try container.encodeIfPresent(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        }
    }
}

nonisolated struct NewAppRequest: Codable, Sendable {
    var name: String
    var approval: AppApproval
    var dailyLimitMinutes: Int?
}

// MARK: - Location

nonisolated struct DayGroup: Codable, Equatable, Hashable, Sendable {
    var key: String
    var label: String
}

nonisolated struct CurrentLocation: Codable, Equatable, Sendable {
    var deviceId: String
    var deviceName: String
    var lat: Double
    var lng: Double
    var accuracyM: Double?
    var placeLabel: String?
    var locatedAt: Date
    var updatedLabel: String?
    /// Under 15 minutes old with the device still syncing. Otherwise show "Last seen", never live.
    var fresh: Bool?
    /// Accuracy over 200 m, e.g. a cell-tower fix. Draw the circle and say "approximate".
    var approximate: Bool?

    init(deviceId: String, deviceName: String, lat: Double, lng: Double, accuracyM: Double?, placeLabel: String?, locatedAt: Date, updatedLabel: String?, fresh: Bool? = nil, approximate: Bool? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.placeLabel = placeLabel
        self.locatedAt = locatedAt
        self.updatedLabel = updatedLabel
        self.fresh = fresh
        self.approximate = approximate
    }

    var isFresh: Bool { fresh ?? (Date.now.timeIntervalSince(locatedAt) < 15 * 60) }
    var isApproximate: Bool { approximate ?? ((accuracyM ?? 0) > 200) }

    /// "Live · Near Home" or "Last seen Today, 1:28 PM".
    var freshnessLabel: String {
        let when = updatedLabel ?? locatedAt.verifiedDescription()
        return isFresh ? "Live · updated \(when)" : "Last seen \(when)"
    }
}

nonisolated struct LocationDevice: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var sharing: Bool
    var hasLocation: Bool
}

nonisolated struct Visit: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var deviceName: String
    var lat: Double
    var lng: Double
    /// nil unless a saved place (or the device) named it, which is most visits: devices don't reverse-geocode.
    var placeLabel: String?
    var arrivedAt: Date
    var lastSeenAt: Date?
    var timeLabel: String
    var day: DayGroup
    /// false for a fix taken while passing by. nil from older servers (treated as a stay).
    var stayed: Bool?
    var durationMinutes: Int?
    /// "9:10 AM – 3:40 PM · 6 h 30 min", or one time when passing by (family time zone).
    var spanLabel: String?

    /// Worded as the web's: a fix taken while passing by isn't a place the child went to.
    var title: String {
        if stayed ?? true { return placeLabel ?? "Unnamed place" }
        return placeLabel.map { "Passed by \($0)" } ?? "Passing by"
    }

    /// When, and on which device.
    var detail: String { "\(spanLabel ?? timeLabel) · \(deviceName)" }
}

/// The device eGuard is waiting on to report whether location sharing is on.
nonisolated struct WaitingDevice: Codable, Equatable, Sendable {
    var deviceId: String?
    var deviceName: String
}

nonisolated struct LocationHistory: Codable, Equatable, Sendable {
    var enabled: Bool
    var visits: [Visit]
}

nonisolated struct LocationResponse: Codable, Equatable, Sendable {
    var childId: String
    var sharing: Bool
    var state: String?
    var current: CurrentLocation?
    var devices: [LocationDevice]
    var history: LocationHistory
    /// With state `waiting`: no device has said yet whether it shares; name it ("Waiting for iPad to report…").
    var waitingForReport: WaitingDevice?
    /// Set when the location comes from an iPhone or iPad: it updates only while eGuard is open there. Show it under the location.
    var note: String?

    init(childId: String, sharing: Bool, state: String? = nil, current: CurrentLocation?, devices: [LocationDevice], history: LocationHistory) {
        self.childId = childId
        self.sharing = sharing
        self.state = state
        self.current = current
        self.devices = devices
        self.history = history
    }

    var locationState: LocationState {
        if let state, let known = LocationState(rawValue: state) { return known }
        if devices.isEmpty { return .noDevices }
        if !sharing { return .sharingOff }
        return current == nil ? .waiting : .located
    }
}

nonisolated struct VisitsPage: Codable, Equatable, Sendable {
    var enabled: Bool
    var retentionDays: Int?
    var visits: [Visit]
    var nextBefore: Date?
}

nonisolated struct FamilyLocation: Codable, Equatable, Identifiable, Sendable {
    var childId: String
    var name: String
    var hue: Int
    var photoUrl: String?
    var sharing: Bool
    var state: String
    var location: CurrentLocation?
    /// As on `LocationResponse`: why an iPhone's location may be old.
    var note: String?

    var id: String { childId }
    var locationState: LocationState { LocationState(rawValue: state) ?? (location == nil ? .waiting : .located) }
}

nonisolated struct FamilyLocations: Codable, Equatable, Sendable {
    var children: [FamilyLocation]
}

// MARK: - Alerts

nonisolated enum AlertSeverity: String, Codable, Sendable {
    case info = "INFO"
    case attention = "ATTENTION"
    case actionRequired = "ACTION_REQUIRED"
    case critical = "CRITICAL"

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .info) }
}

nonisolated enum APIAlertCategory: String, Codable, Sendable {
    case protection = "PROTECTION"
    case devices = "DEVICES"
    case apps = "APPS"
    case screenTime = "SCREEN_TIME"
    case location = "LOCATION"
    case system = "SYSTEM"

    init(from decoder: Decoder) throws { self = try decodeLenient(decoder, fallback: .system) }
}

nonisolated enum AlertsFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "ALL"
    case protection = "PROTECTION"
    case apps = "APPS"
    case devices = "DEVICES"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .protection: "Protection"
        case .apps: "Apps"
        case .devices: "Devices"
        }
    }
}

nonisolated struct AlertAction: Codable, Equatable, Sendable {
    var type: String
    var label: String
    var childId: String?
    var key: String?
    var deviceId: String?

    /// The button text to show. Plan actions get a neutral label on iOS, where the app must not
    /// invite the parent to buy or upgrade outside In-App Purchase.
    var displayLabel: String {
        type == "MANAGE_SUBSCRIPTION" ? "View your plan" : label
    }
}

nonisolated struct APIAlert: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var childId: String?
    var deviceId: String?
    var severity: AlertSeverity
    var category: APIAlertCategory
    var icon: String?
    var title: String
    var body: String
    var subject: String?
    var fromValue: String?
    var toValue: String?
    var read: Bool
    var resolved: Bool
    var dismissible: Bool
    var createdAt: Date
    var timeLabel: String?
    var day: DayGroup
    var action: AlertAction?
}

nonisolated struct AlertsPage: Codable, Equatable, Sendable {
    var alerts: [APIAlert]
    var unread: Int
    var nextBefore: Date?
}

nonisolated struct UnreadCount: Codable, Sendable {
    var unread: Int
}

nonisolated struct ReadResponse: Codable, Sendable {
    var ok: Bool?
    var marked: Int?
    var unread: Int
}

// MARK: - Family and privacy

nonisolated struct FamilyMember: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var email: String
    var role: UserRole
    var createdAt: Date?
    var you: Bool
    /// True until the invited parent accepts the invitation.
    var pending: Bool?

    init(id: String, name: String, email: String, role: UserRole, createdAt: Date?, you: Bool, pending: Bool? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.createdAt = createdAt
        self.you = you
        self.pending = pending
    }

    var isPending: Bool { pending ?? false }
}

/// What a plan includes. Also returned on `GET /family`. The server enforces these either way.
nonisolated struct PlanEntitlements: Codable, Equatable, Sendable {
    var childLimit: Int?
    var deviceLimit: Int?
    var locationSharing: Bool?
    var appMonitoringLimit: Int?
    var realtimeAlerts: Bool?
    var advancedReports: Bool?
    var apiAccess: Bool?

    var hasLocationSharing: Bool { locationSharing ?? true }
    var hasAdvancedReports: Bool { advancedReports ?? true }
    var hasRealtimeAlerts: Bool { realtimeAlerts ?? true }
}

nonisolated struct Family: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var timezone: String
    var members: [FamilyMember]
    var children: [ChildSummary]
    /// Phones and tablets only.
    var deviceCount: Int
    /// Phones, tablets and connected browsers: compare this with `deviceLimit`.
    var devicesUsed: Int?
    var deviceLimit: Int
    var childCount: Int?
    var childLimit: Int?
    var plan: String?
    var entitlements: PlanEntitlements?
    var canManage: Bool

    init(id: String, name: String, timezone: String, members: [FamilyMember], children: [ChildSummary], deviceCount: Int, devicesUsed: Int? = nil, deviceLimit: Int, childCount: Int? = nil, childLimit: Int? = nil, plan: String? = nil, entitlements: PlanEntitlements? = nil, canManage: Bool) {
        self.id = id
        self.name = name
        self.timezone = timezone
        self.members = members
        self.children = children
        self.deviceCount = deviceCount
        self.devicesUsed = devicesUsed
        self.deviceLimit = deviceLimit
        self.childCount = childCount
        self.childLimit = childLimit
        self.plan = plan
        self.entitlements = entitlements
        self.canManage = canManage
    }

    var slotsUsed: Int { devicesUsed ?? deviceCount }
}

/// `POST /family/members`: the admin invited another parent by email.
nonisolated struct InvitationSent: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var email: String
    var role: UserRole?
    var pending: Bool?
    /// False when the email failed to send; offer Resend.
    var emailSent: Bool?
    var expiresInDays: Int?
}

nonisolated struct NewMember: Codable, Sendable {
    var name: String
    var email: String
}

// MARK: - Organizations

/// A school, community group or business the family joined with a join code.
nonisolated struct Organization: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var kind: String
    var kindLabel: String?
    var joinedAt: Date?

    var kindTitle: String {
        if let kindLabel { return kindLabel }
        switch kind {
        case "SCHOOL": return "School"
        case "COMMUNITY": return "Community group"
        case "BUSINESS": return "Business"
        default: return kind.capitalized
        }
    }

    var symbolName: String {
        switch kind {
        case "SCHOOL": "graduationcap.fill"
        case "COMMUNITY": "person.3.fill"
        case "BUSINESS": "building.2.fill"
        default: "building.columns.fill"
        }
    }
}

nonisolated struct OrganizationsResponse: Codable, Equatable, Sendable {
    var organizations: [Organization]
    var canManage: Bool
    /// A sentence to show under the list about what organizations can and can't see.
    var privacy: String?
}

nonisolated struct OrganizationPreview: Codable, Equatable, Sendable {
    var name: String
    var kind: String
    var kindLabel: String?
    var alreadyJoined: Bool
    var message: String
}

nonisolated struct OrganizationJoined: Codable, Sendable {
    var ok: Bool?
    var name: String
    var organizations: [Organization]?
}

nonisolated struct OrganizationLeft: Codable, Sendable {
    var ok: Bool?
    var name: String?
}

nonisolated struct PrivacySettings: Codable, Equatable, Sendable {
    var keepLocationHistory: Bool
    var shareAnalytics: Bool
    var retentionDays: Int?
}

nonisolated struct PrivacyPatch: Codable, Sendable {
    var keepLocationHistory: Bool?
    var shareAnalytics: Bool?
}

// MARK: - Subscription

nonisolated struct PlanFeature: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var included: Bool
    var label: String

    var id: String { key }
}

nonisolated struct PlanUsage: Codable, Equatable, Sendable {
    var devicesUsed: Int
    var deviceLimit: Int
    var children: Int
    var childLimit: Int?

    init(devicesUsed: Int, deviceLimit: Int, children: Int, childLimit: Int? = nil) {
        self.devicesUsed = devicesUsed
        self.deviceLimit = deviceLimit
        self.children = children
        self.childLimit = childLimit
    }
}

nonisolated struct StoreInfo: Codable, Equatable, Sendable {
    var name: String
    var productId: String?
    var autoRenewing: Bool?
    var expiresAt: Date?
    /// The organization that paid, for a VOUCHER plan (newer servers)
    var sponsor: String?

    /// How the plan is paid, in parent-friendly words. Sponsor codes are redeemed on the web only.
    var title: String {
        switch name {
        case "VOUCHER": sponsor.map { "Sponsored by \($0)" } ?? "Sponsored plan"
        case "GOOGLE_PLAY": "Google Play"
        case "PAYMONGO": autoRenewing == false ? "Pass" : "Web subscription"
        default: name.capitalized
        }
    }
}

nonisolated struct UpgradeInfo: Codable, Equatable, Sendable {
    var planId: String
    var name: String
    var googlePlayProductId: String?
}

nonisolated struct SubscriptionInfo: Codable, Equatable, Sendable {
    var plan: String
    var planId: String?
    var status: String
    var renewsAt: Date?
    var renewsLabel: String?
    var features: [PlanFeature]
    var entitlements: PlanEntitlements?
    var usage: PlanUsage
    var canManage: Bool
    var billingAvailable: Bool
    var store: StoreInfo?
    var upgrade: UpgradeInfo?

    init(plan: String, planId: String? = nil, status: String, renewsAt: Date?, renewsLabel: String?, features: [PlanFeature], entitlements: PlanEntitlements? = nil, usage: PlanUsage, canManage: Bool, billingAvailable: Bool, store: StoreInfo?, upgrade: UpgradeInfo?) {
        self.plan = plan
        self.planId = planId
        self.status = status
        self.renewsAt = renewsAt
        self.renewsLabel = renewsLabel
        self.features = features
        self.entitlements = entitlements
        self.usage = usage
        self.canManage = canManage
        self.billingAvailable = billingAvailable
        self.store = store
        self.upgrade = upgrade
    }

    var isActive: Bool { status == "ACTIVE" }
    /// Sponsored by an organization through a code redeemed on the website.
    var isSponsored: Bool { store?.name == "VOUCHER" }
}

// MARK: - Help and support

nonisolated struct HelpCategory: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String
    var icon: String?
}

nonisolated struct HelpArticleSummary: Codable, Equatable, Identifiable, Sendable {
    var slug: String
    var category: String
    var title: String
    var summary: String

    var id: String { slug }
}

nonisolated struct HelpContact: Codable, Equatable, Sendable {
    var email: String
    var replyTime: String?
}

nonisolated struct HelpIndex: Codable, Equatable, Sendable {
    var categories: [HelpCategory]
    var articles: [HelpArticleSummary]
    var contact: HelpContact?
}

nonisolated struct HelpArticle: Codable, Equatable, Sendable {
    var slug: String
    var category: String
    var title: String
    var summary: String
    var body: [String]
}

nonisolated struct SupportTicket: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var category: String?
    var subject: String?
    var message: String
    var status: String
    var createdAt: Date
}

nonisolated struct TicketsResponse: Codable, Sendable {
    var tickets: [SupportTicket]
}

nonisolated struct NewTicket: Codable, Sendable {
    var category: String?
    var subject: String
    var message: String
}

// MARK: - Icons

/// Maps the API's Lucide icon names to SF Symbols.
nonisolated enum LucideIcon {
    static func symbol(for name: String?, fallback: String = "shield.lefthalf.filled") -> String {
        switch name {
        case "moon": "moon.zzz.fill"
        case "hourglass": "hourglass"
        case "globe": "globe"
        case "map-pin": "mappin.circle.fill"
        case "shield-check": "checkmark.shield.fill"
        case "shield": "shield.fill"
        case "scale": "scalemass.fill"
        case "sliders-horizontal": "gearshape.fill"
        case "book-open": "list.clipboard.fill"
        case "wrench": "wrench.and.screwdriver.fill"
        case "lock": "lock.fill"
        case "help-circle", "circle-help": "questionmark.circle.fill"
        case "smartphone": "iphone"
        case "tablet": "ipad"
        case "bell": "bell.fill"
        case "bell-off": "bell.slash.fill"
        case "download": "arrow.down.app.fill"
        case "app-window", "layout-grid", "grid": "square.grid.2x2.fill"
        case "check-circle": "checkmark.circle.fill"
        case "alert-triangle", "triangle-alert": "exclamationmark.triangle.fill"
        case "clock": "clock.fill"
        case "eye-off": "eye.slash.fill"
        case "film", "tv": "play.rectangle.fill"
        case "crown": "crown.fill"
        case "trash": "trash.fill"
        case "user": "person.fill"
        // Devices alerts: "Switched to another user", "Used on another user"
        case "users": "person.2.fill"
        case "user-check": "person.crop.circle.badge.checkmark"
        case "message-circle": "bubble.left.and.bubble.right.fill"
        default: fallback
        }
    }

    /// A tile tint for a protection key.
    @MainActor
    static func tint(forKey key: String) -> Color {
        switch key {
        case "BEDTIME": EGuardColors.tilePurple
        case "SCREEN_TIME": EGuardColors.primary
        case "APP_RESTRICTIONS": EGuardColors.tileTeal
        case "APP_APPROVAL": EGuardColors.tileOrange
        case "CONTENT": EGuardColors.danger
        case "WEB": EGuardColors.danger
        case "DOWNLOADS": EGuardColors.primary
        case "LOCATION": EGuardColors.success
        case "NOTIFICATIONS": EGuardColors.tileYellow
        case "UNINSTALL_PROTECTION": EGuardColors.tileGray
        default: EGuardColors.primary
        }
    }
}
