import Foundation

/// Decides whether each feature is automatic, guided, verification-only, or unsupported on this device.
/// The UI never assumes a feature is automatic; it always asks this resolver.
nonisolated struct CapabilityResolver: Sendable {
    var environment: PlatformEnvironment

    init(environment: PlatformEnvironment) {
        self.environment = environment
    }

    func capabilities(for settings: ProtectionSettings) -> [ProtectionCapability] {
        settings.enabledFeatures.map { capability(for: $0, settings: settings) }
    }

    func capability(for feature: ProtectionFeature, settings: ProtectionSettings) -> ProtectionCapability {
        let intended = intendedMode(for: feature, settings: settings)

        // Without Family Controls, Apple's frameworks cannot apply anything. Guided steps still work.
        if !environment.isFamilyControlsAvailable && intended.mode == .automatic {
            return ProtectionCapability(
                feature: feature,
                mode: .unsupported,
                explanation: "Apple's Screen Time frameworks are not available on this device, so eGuard cannot configure this setting."
            )
        }
        return intended
    }

    private func intendedMode(for feature: ProtectionFeature, settings: ProtectionSettings) -> ProtectionCapability {
        switch feature {
        case .downtime:
            return ProtectionCapability(
                feature: feature,
                mode: .automatic,
                explanation: "eGuard schedules downtime with Device Activity and shields apps during the window."
            )
        case .gaming, .socialApps:
            return ProtectionCapability(
                feature: feature,
                mode: .automatic,
                explanation: "eGuard tracks the daily allowance for the apps you choose and shields them when it runs out."
            )
        case .webContent:
            return ProtectionCapability(
                feature: feature,
                mode: .automatic,
                explanation: "eGuard turns on Apple's adult website filter with Managed Settings."
            )
        case .appInstallation:
            switch settings.appInstallation {
            case .parentApproval:
                return ProtectionCapability(
                    feature: feature,
                    mode: .guided,
                    explanation: "Ask to Buy is part of Family Sharing. Apple requires a parent to turn it on in Settings, and eGuard cannot verify it automatically."
                )
            case .blocked, .allowed:
                return ProtectionCapability(
                    feature: feature,
                    mode: .automatic,
                    explanation: "eGuard blocks new app installation with Managed Settings."
                )
            }
        case .appRestrictions:
            return ProtectionCapability(
                feature: feature,
                mode: .automatic,
                explanation: "eGuard shields the apps you choose with Managed Settings."
            )
        case .purchases:
            return ProtectionCapability(
                feature: feature,
                mode: .automatic,
                explanation: "eGuard requires a password for App Store purchases with Managed Settings."
            )
        case .explicitContent:
            return ProtectionCapability(
                feature: feature,
                mode: .automatic,
                explanation: "eGuard hides explicit music and video with Managed Settings."
            )
        case .deviceActivity:
            return ProtectionCapability(
                feature: feature,
                mode: .automatic,
                explanation: "eGuard registers schedules with Device Activity so downtime and limits are enforced."
            )
        case .screenTimePasscode:
            return ProtectionCapability(
                feature: feature,
                mode: .guided,
                explanation: "Apple requires the Screen Time passcode to be set in Settings. eGuard cannot read or verify it."
            )
        }
    }
}
