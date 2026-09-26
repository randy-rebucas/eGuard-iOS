import Foundation

/// Every protection eGuard can configure or verify. Terminology is shared with Android.
nonisolated enum ProtectionFeature: String, Codable, CaseIterable, Identifiable, Sendable {
    case downtime
    case gaming
    case socialApps
    case webContent
    case appInstallation
    case appRestrictions
    case purchases
    case explicitContent
    case deviceActivity
    case screenTimePasscode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downtime: "Downtime"
        case .gaming: "Gaming"
        case .socialApps: "Social Apps"
        case .webContent: "Web Content"
        case .appInstallation: "App Installation"
        case .appRestrictions: "App Restrictions"
        case .purchases: "Purchases"
        case .explicitContent: "Explicit Content"
        case .deviceActivity: "Device Activity"
        case .screenTimePasscode: "Screen Time Passcode"
        }
    }

    var shortDescription: String {
        switch self {
        case .downtime: "Apps are shielded during a nightly schedule."
        case .gaming: "A daily time allowance for gaming apps."
        case .socialApps: "A daily time allowance for social apps."
        case .webContent: "Adult websites are blocked automatically."
        case .appInstallation: "Control how new apps are installed."
        case .appRestrictions: "Specific apps are always shielded."
        case .purchases: "Require a password for App Store purchases."
        case .explicitContent: "Hide music and video marked explicit."
        case .deviceActivity: "eGuard monitors schedules and limits."
        case .screenTimePasscode: "Stops the child from changing Screen Time settings."
        }
    }

    var symbolName: String {
        switch self {
        case .downtime: "moon.zzz.fill"
        case .gaming: "gamecontroller.fill"
        case .socialApps: "bubble.left.and.bubble.right.fill"
        case .webContent: "globe"
        case .appInstallation: "arrow.down.app.fill"
        case .appRestrictions: "lock.app.dashed"
        case .purchases: "creditcard.fill"
        case .explicitContent: "music.note.list"
        case .deviceActivity: "chart.bar.fill"
        case .screenTimePasscode: "hourglass"
        }
    }

    /// The app selection this feature depends on, if any.
    var selectionPurpose: SelectionPurpose? {
        switch self {
        case .gaming: .gaming
        case .socialApps: .socialApps
        case .appRestrictions: .restrictedApps
        default: nil
        }
    }

    /// Features shown on the Recommended Setup screen, in display order.
    static let recommendedSetupOrder: [ProtectionFeature] = [
        .downtime, .gaming, .socialApps, .webContent, .appInstallation,
    ]

    /// Features shown on the Configure Settings and Health Check screens, in display order.
    static let configurationOrder: [ProtectionFeature] = [
        .downtime, .gaming, .socialApps, .appRestrictions, .webContent,
        .appInstallation, .purchases, .explicitContent, .deviceActivity, .screenTimePasscode,
    ]
}
