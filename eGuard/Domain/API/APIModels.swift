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

// MARK: - Auth and user

nonisolated enum UserRole: String, Codable, Sendable {
    case familyAdmin = "FAMILY_ADMIN"
    case parent = "PARENT"

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
    var emailVerified: Bool?
    var createdAt: Date

    var isAdmin: Bool { role == .familyAdmin }
    var isEmailVerified: Bool { emailVerified ?? true }
}

nonisolated struct AuthResponse: Codable, Equatable, Sendable {
    var token: String
    var expiresAt: Date
    var user: APIUser
    var isNew: Bool?

    var session: APISession { APISession(token: token, expiresAt: expiresAt) }
}

nonisolated enum SocialProvider: String, Codable, Sendable {
    case apple
    case google
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
    var userAgent: String
    var createdAt: Date
    var lastSeenAt: Date?
    var current: Bool
}

// MARK: - Children and devices

nonisolated enum ChildStatus: String, Codable, Sendable {
    case protected
    case attention
    case notconfigured

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

    var text: String { "\(score) / \(total)" }
    var fraction: Double { total == 0 ? 0 : Double(score) / Double(total) }

    /// The spec's grade thresholds, used when `label` is absent.
    var grade: String {
        if let label { return label }
        if total == 0 { return "Not configured" }
        if score >= total { return "Fully protected" }
        if score >= 8 { return "Good protection" }
        if score >= 5 { return "Needs attention" }
        return "Action required"
    }
}

nonisolated enum DevicePlatformKind: String, Codable, Sendable {
    case android = "ANDROID"
    case ios = "IOS"

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
    var deviceCount: Int
    var primaryDevice: PrimaryDevice?

    var ageDescription: String { "\(age) years old" }
    var deviceName: String { primaryDevice?.name ?? "\(name)'s device" }
}

nonisolated enum DeviceState: String, Codable, Sendable {
    case healthy
    case issues
    case offline

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

    var symbolName: String { kind == "TABLET" ? "ipad" : "iphone" }
}

nonisolated struct DevicesResponse: Codable, Sendable {
    var devices: [APIDevice]
    var limit: Int?
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
    var protections: [DeviceProtectionStatus]

    var device: APIDevice {
        APIDevice(id: id, childId: childId, childName: childName, name: name, model: model, kind: kind, platform: platform, osVersion: osVersion, appVersion: appVersion, battery: battery, isPrimary: isPrimary, lastSeenAt: lastSeenAt, lastSeenLabel: lastSeenLabel, state: state, issues: issues)
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
}

nonisolated struct PhotoUploadResponse: Codable, Sendable {
    var photoUrl: String
}

// MARK: - Health and checks

nonisolated enum CheckStatus: String, Codable, Sendable {
    case pass = "PASS"
    case warning = "WARNING"
    case actionRequired = "ACTION_REQUIRED"
    case notConfigured = "NOT_CONFIGURED"
    case unsupported = "UNSUPPORTED"

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

    var id: String { key }
}

nonisolated struct FixItem: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var name: String
    var status: CheckStatus
    var detail: String?
    var childId: String
    var deviceId: String?

    var id: String { key + childId }
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
    var checks: [HealthCheck]
    var toFix: [FixItem]?
    var children: [ChildHealth]?

    var healthScore: HealthScore { HealthScore(score: score, total: total, label: label) }
    var fixCount: Int { toFix?.count ?? checks.filter { $0.status.needsAttention }.count }
}

// MARK: - Dashboard

nonisolated struct Dashboard: Codable, Equatable, Sendable {
    var user: APIUser
    var greeting: String
    var summary: String
    var health: HealthScore
    var children: [ChildSummary]
    var deviceCount: Int
    var recentAlerts: [APIAlert]
    var unreadAlerts: Int
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
    case unsupported = "UNSUPPORTED"

    var title: String {
        switch self {
        case .available: "Available"
        case .guided: "Guided"
        case .verifyOnly: "Verify only"
        case .unsupported: "Not supported"
        }
    }

    /// The local mode used by the design system's badge colors.
    var mode: ConfigurationMode {
        switch self {
        case .available: .automatic
        case .guided: .guided
        case .verifyOnly: .verificationOnly
        case .unsupported: .unsupported
        }
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

    var id: String { requestId }
    var isGuided: Bool { mode == "GUIDED" }
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
}

nonisolated struct BatchSummary: Codable, Equatable, Sendable {
    var total: Int
    var verified: Int
    var failed: Int
    var awaitingParent: Int
    var inProgress: Int
    var cancelled: Int
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

nonisolated struct LocationInfo: Codable, Equatable, Sendable {
    var sharing: Bool
    var placeLabel: String?
    var updatedAt: Date?
    var label: String
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
    var devices: [ProtectionDevice]

    var id: String { key }

    /// True when no device can apply it, so the control should be disabled.
    var isUnsupportedEverywhere: Bool {
        !devices.isEmpty && devices.allSatisfy { $0.capability == .unsupported }
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

nonisolated struct ScreenTimeReport: Codable, Equatable, Sendable {
    var period: String
    var from: String
    var to: String
    var totalMinutes: Int
    var averageMinutes: Int
    var previousAverageMinutes: Int?
    var limitMinutes: Int?
    var days: [DayMinutes]
    var hourly: [Int]?
    var apps: [AppUsage]

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

    var title: String {
        switch self {
        case .allowed: "Allowed"
        case .alwaysAllowed: "Always allowed"
        case .filtered: "Filtered"
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
    var allowed: Bool
    var dailyLimitMinutes: Int?
    var todayMinutes: Int?
    var installedAt: Date?

    /// The design's subtitle: "Always allowed", "1 hour/day", "Ask parent", or "Blocked".
    var subtitle: String {
        switch approval {
        case .alwaysAllowed: return "Always allowed"
        case .pending: return "Ask parent"
        case .blocked: return "Blocked"
        case .allowed, .filtered:
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

nonisolated struct AppsResponse: Codable, Equatable, Sendable {
    var counts: AppCounts
    var apps: [ChildApp]
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
    var placeLabel: String
    var arrivedAt: Date
    var lastSeenAt: Date?
    var timeLabel: String
    var day: DayGroup
}

nonisolated struct LocationHistory: Codable, Equatable, Sendable {
    var enabled: Bool
    var visits: [Visit]
}

nonisolated struct LocationResponse: Codable, Equatable, Sendable {
    var childId: String
    var sharing: Bool
    var current: CurrentLocation?
    var devices: [LocationDevice]
    var history: LocationHistory
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

    var id: String { childId }
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
}

nonisolated enum APIAlertCategory: String, Codable, Sendable {
    case protection = "PROTECTION"
    case devices = "DEVICES"
    case apps = "APPS"
    case screenTime = "SCREEN_TIME"
    case location = "LOCATION"
    case system = "SYSTEM"
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
    var createdAt: Date
    var you: Bool
}

nonisolated struct Family: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var timezone: String
    var members: [FamilyMember]
    var children: [ChildSummary]
    var deviceCount: Int
    var deviceLimit: Int
    var canManage: Bool
}

nonisolated struct NewMember: Codable, Sendable {
    var name: String
    var email: String
    var password: String
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
}

nonisolated struct StoreInfo: Codable, Equatable, Sendable {
    var name: String
    var productId: String?
    var autoRenewing: Bool?
    var expiresAt: Date?
}

nonisolated struct UpgradeInfo: Codable, Equatable, Sendable {
    var planId: String
    var name: String
    var googlePlayProductId: String?
}

nonisolated struct SubscriptionInfo: Codable, Equatable, Sendable {
    var plan: String
    var status: String
    var renewsAt: Date?
    var renewsLabel: String?
    var features: [PlanFeature]
    var usage: PlanUsage
    var canManage: Bool
    var billingAvailable: Bool
    var store: StoreInfo?
    var upgrade: UpgradeInfo?

    var isActive: Bool { status == "ACTIVE" }
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
        case "user", "users": "person.2.fill"
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
