import Foundation

// The wire shapes of the child device API (`/api/device/v1`). Every call is a POST with a device token.

/// The device token and what it was paired to. Lives in the Keychain; it never expires.
nonisolated struct DeviceSession: Codable, Equatable, Sendable {
    var deviceId: String
    var token: String
    var childName: String
    var deviceName: String
    var pairedAt: Date
}

nonisolated struct PairRequest: Encodable, Sendable {
    var code: String
    var platform = "IOS"
    var name: String
    var model: String
    var kind: String
    var osVersion: String
    var appVersion: String?
}

nonisolated struct PairResponse: Decodable, Sendable {
    var deviceId: String
    var token: String
    var childName: String
}

/// `battery`, `osVersion` and `appVersion` travel in request bodies, not headers.
nonisolated struct DeviceStatus: Encodable, Sendable {
    var battery: Int?
    var osVersion: String?
    var appVersion: String?
}

/// One of the child's current settings. This is what the device enforces, including offline.
nonisolated struct PolicyEntry: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var config: JSONValue

    var id: String { key }
}

/// A change a parent made that this device hasn't verified yet. Apply, read back, report.
nonisolated struct DeviceRequest: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var key: String
    var config: JSONValue
}

nonisolated struct AppRule: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var approval: AppApproval
    var dailyLimitMinutes: Int?

    var id: String { name }
}

nonisolated struct SyncFeatures: Codable, Equatable, Sendable {
    var locationSharing: Bool?
}

nonisolated struct SyncResponse: Codable, Equatable, Sendable {
    var deviceId: String
    var policy: [PolicyEntry]
    var requests: [DeviceRequest]
    var apps: [AppRule]
    var fullReportRequested: Bool
    var nextSyncSeconds: Int
    var timezone: String
    var features: SyncFeatures?
    var minAppVersion: String?

    var isLocationSharingAllowed: Bool { features?.locationSharing ?? true }
}

/// The configuration the device actually has for one protection, without `key` inside `config`.
nonisolated struct ReportEntry: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var config: JSONValue

    var id: String { key }
}

nonisolated struct ReportRequest: Encodable, Sendable {
    var full: Bool?
    var protections: [ReportEntry]
    var battery: Int?
    var osVersion: String?
    var appVersion: String?
}

nonisolated struct IgnoredEntry: Codable, Equatable, Sendable {
    var key: String
    var error: String
}

nonisolated struct ReportResponse: Codable, Sendable {
    var ok: Bool?
    var ignored: [IgnoredEntry]?
}

nonisolated struct AppMinutes: Codable, Equatable, Sendable {
    var name: String
    var minutes: Int
}

/// Daily screen-time totals for the device's local date. Idempotent per device and day.
nonisolated struct UsageRequest: Codable, Equatable, Sendable {
    var date: String
    var totalMinutes: Int
    var apps: [AppMinutes]?
    var hourly: [Int]?
}

nonisolated struct LocationFix: Codable, Equatable, Sendable {
    var lat: Double
    var lng: Double
    var accuracyM: Double?
    var placeLabel: String?
}

nonisolated enum DeviceEventType: String, Codable, Sendable {
    case appInstalled = "APP_INSTALLED"
    case appRequested = "APP_REQUESTED"
    case appBlocked = "APP_BLOCKED"
    case limitReached = "LIMIT_REACHED"
}

/// Something that happened on the device that parents should hear about. `eventId` makes retries safe.
nonisolated struct DeviceEvent: Codable, Equatable, Identifiable, Sendable {
    var type: DeviceEventType
    var app: String?
    var ageRating: Int?
    var minutes: Int?
    var eventId: String

    var id: String { eventId }

    init(type: DeviceEventType, app: String? = nil, ageRating: Int? = nil, minutes: Int? = nil, eventId: String = UUID().uuidString) {
        self.type = type
        self.app = app
        self.ageRating = ageRating
        self.minutes = minutes
        self.eventId = eventId
    }
}

nonisolated struct EventResponse: Codable, Sendable {
    var ok: Bool?
    /// For `APP_REQUESTED`: the parent's existing answer when the app already has a rule.
    var approval: AppApproval?
    var duplicate: Bool?
}

nonisolated struct DeviceOK: Codable, Sendable {
    var ok: Bool?
}
