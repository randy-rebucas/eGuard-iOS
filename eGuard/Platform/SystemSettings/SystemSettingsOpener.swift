import Foundation
import UIKit

/// Opens Settings and describes the guided steps Apple requires a parent to complete manually.
final class SystemSettingsOpener: SystemSettingsService {
    init() {}

    var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    func instructions(for feature: ProtectionFeature) -> GuidedInstructions {
        switch feature {
        case .appInstallation:
            GuidedInstructions(
                feature: feature,
                settingsPath: "Settings › Family › your child › Ask to Buy",
                steps: [
                    "Open Settings and tap your name at the top.",
                    "Tap Family, then choose your child.",
                    "Tap Ask to Buy and turn on Require Purchase Approval.",
                    "Return to eGuard and confirm below.",
                ],
                cannotVerifyNote: "Apple does not let apps read the Ask to Buy setting, so eGuard relies on your confirmation."
            )
        case .screenTimePasscode:
            GuidedInstructions(
                feature: feature,
                settingsPath: "Settings › Screen Time › Lock Screen Time Settings",
                steps: [
                    "Open Settings and tap Screen Time.",
                    "Tap Lock Screen Time Settings and choose a passcode your child does not know.",
                    "Enter your Apple Account details for passcode recovery.",
                    "Return to eGuard and confirm below.",
                ],
                cannotVerifyNote: "Apple does not let apps read the Screen Time passcode, so eGuard relies on your confirmation."
            )
        default:
            GuidedInstructions(
                feature: feature,
                settingsPath: "Settings › Screen Time",
                steps: [
                    "Open Settings and tap Screen Time.",
                    "Find the setting named \(feature.title) and follow the on-screen instructions.",
                    "Return to eGuard and confirm below.",
                ],
                cannotVerifyNote: "Apple does not let apps read this setting, so eGuard relies on your confirmation."
            )
        }
    }
}
