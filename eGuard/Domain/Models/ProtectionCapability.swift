import Foundation

/// How eGuard can act on a protection feature on this platform.
nonisolated enum ConfigurationMode: String, Codable, Sendable {
    /// eGuard applies the setting directly with Apple's frameworks.
    case automatic
    /// Apple requires the parent to finish the setting in the Settings app.
    case guided
    /// eGuard can only read the current state; it cannot change it.
    case verificationOnly
    /// The platform offers no supported way to configure or verify the setting.
    case unsupported

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .guided: "Guided"
        case .verificationOnly: "Verification only"
        case .unsupported: "Unsupported"
        }
    }
}

/// What eGuard can do for a feature and why.
nonisolated struct ProtectionCapability: Equatable, Sendable {
    let feature: ProtectionFeature
    let mode: ConfigurationMode
    let explanation: String
}

/// Facts about the platform that affect what eGuard can configure.
nonisolated struct PlatformEnvironment: Equatable, Sendable {
    /// Family Controls authorization can succeed on this device.
    var isFamilyControlsAvailable: Bool
    /// The app runs in the simulator, where Screen Time enforcement is not available.
    var isSimulator: Bool

    static let iPhone = PlatformEnvironment(isFamilyControlsAvailable: true, isSimulator: false)
    static let unavailable = PlatformEnvironment(isFamilyControlsAvailable: false, isSimulator: false)
}
