import Foundation

/// A wall-clock time without a date, used for downtime schedules.
nonisolated struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    /// A date on the given day with this time, used to drive native time pickers.
    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// A short localized time such as "9:30 PM".
    var formatted: String {
        date().formatted(date: .omitted, time: .shortened)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// A nightly window during which apps are shielded.
nonisolated struct DowntimeWindow: Codable, Hashable, Sendable {
    var start: TimeOfDay
    var end: TimeOfDay

    var formatted: String {
        "\(start.formatted) – \(end.formatted)"
    }

    /// Apple requires at least fifteen minutes of monitoring per interval.
    var isValid: Bool {
        let length = (end.minutesSinceMidnight - start.minutesSinceMidnight + 24 * 60) % (24 * 60)
        return length >= 15
    }
}

/// Web filtering levels. Apple supports an automatic adult-content filter and specific domains.
nonisolated enum WebContentLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case unrestricted
    case limited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unrestricted: "Unrestricted"
        case .limited: "Limited"
        }
    }

    var detail: String {
        switch self {
        case .unrestricted: "All websites are allowed."
        case .limited: "Adult websites are blocked automatically."
        }
    }
}

/// How new apps may be installed on the child's device.
nonisolated enum AppInstallationPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case allowed
    case parentApproval
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allowed: "Allowed"
        case .parentApproval: "Parent approval"
        case .blocked: "Blocked"
        }
    }

    var detail: String {
        switch self {
        case .allowed: "The child can install apps freely."
        case .parentApproval: "Apple's Ask to Buy sends every download to you for approval."
        case .blocked: "The App Store cannot install new apps."
        }
    }
}

/// The complete, editable protection configuration for one child.
nonisolated struct ProtectionSettings: Codable, Equatable, Sendable {
    var profile: ProtectionProfile
    var downtime: DowntimeWindow?
    var gamingLimitMinutes: Int?
    var socialAppsLimitMinutes: Int?
    var webContent: WebContentLevel
    var appInstallation: AppInstallationPolicy
    var blockExplicitContent: Bool
    var requirePasswordForPurchases: Bool
    var restrictSelectedApps: Bool
    var monitorDeviceActivity: Bool
    var requireScreenTimePasscode: Bool

    /// Everything switched off. Used as the starting point for the Custom profile.
    static let off = ProtectionSettings(
        profile: .custom,
        downtime: nil,
        gamingLimitMinutes: nil,
        socialAppsLimitMinutes: nil,
        webContent: .unrestricted,
        appInstallation: .allowed,
        blockExplicitContent: false,
        requirePasswordForPurchases: false,
        restrictSelectedApps: false,
        monitorDeviceActivity: false,
        requireScreenTimePasscode: false
    )

    /// Whether the parent has turned this protection on.
    func isEnabled(_ feature: ProtectionFeature) -> Bool {
        switch feature {
        case .downtime: downtime != nil
        case .gaming: gamingLimitMinutes != nil
        case .socialApps: socialAppsLimitMinutes != nil
        case .webContent: webContent != .unrestricted
        case .appInstallation: appInstallation != .allowed
        case .appRestrictions: restrictSelectedApps
        case .purchases: requirePasswordForPurchases
        case .explicitContent: blockExplicitContent
        case .deviceActivity: monitorDeviceActivity
        case .screenTimePasscode: requireScreenTimePasscode
        }
    }

    var enabledFeatures: [ProtectionFeature] {
        ProtectionFeature.configurationOrder.filter(isEnabled)
    }

    /// The short value shown on eGuard cards, such as "9:30 PM – 6:00 AM" or "1 hour / day".
    func summary(for feature: ProtectionFeature) -> String {
        switch feature {
        case .downtime:
            downtime?.formatted ?? "Off"
        case .gaming:
            gamingLimitMinutes.map(Self.formatDailyAllowance) ?? "No limit"
        case .socialApps:
            socialAppsLimitMinutes.map(Self.formatDailyAllowance) ?? "No limit"
        case .webContent:
            webContent.title
        case .appInstallation:
            appInstallation.title
        case .appRestrictions:
            restrictSelectedApps ? "Selected apps shielded" : "Off"
        case .purchases:
            requirePasswordForPurchases ? "Password required" : "Off"
        case .explicitContent:
            blockExplicitContent ? "Hidden" : "Allowed"
        case .deviceActivity:
            monitorDeviceActivity ? "Monitoring schedules" : "Off"
        case .screenTimePasscode:
            requireScreenTimePasscode ? "Required" : "Off"
        }
    }

    /// Formats a daily allowance in minutes as "1 hour / day", "45 min / day", or "1h 30m / day".
    static func formatDailyAllowance(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, _): return "\(remainder) min / day"
        case (1, 0): return "1 hour / day"
        case (_, 0): return "\(hours) hours / day"
        default: return "\(hours)h \(remainder)m / day"
        }
    }
}
