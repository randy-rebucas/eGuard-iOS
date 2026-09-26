import Foundation

/// The seven-step flow shared with Android. Names and order must stay identical.
nonisolated enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome = 1
    case childDevice
    case protectionProfile
    case recommendedSetup
    case configureSettings
    case healthCheck
    case complete

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .childDevice: "Child & Device"
        case .protectionProfile: "Protection Profile"
        case .recommendedSetup: "Recommended Setup"
        case .configureSettings: "Configure Settings"
        case .healthCheck: "Configuration Health Check"
        case .complete: "Complete"
        }
    }

    /// Zero-padded step number such as "02".
    var number: String {
        String(format: "%02d", rawValue)
    }

    static var count: Int { allCases.count }
}
