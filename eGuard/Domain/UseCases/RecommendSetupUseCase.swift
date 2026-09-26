import Foundation

/// Turns a protection profile and the child's age into recommended settings. Pure and testable.
nonisolated struct RecommendSetupUseCase: Sendable {
    func recommend(profile: ProtectionProfile, childAge: Int) -> ProtectionSettings {
        let isYoungChild = childAge < 10

        switch profile {
        case .balanced:
            return ProtectionSettings(
                profile: .balanced,
                downtime: DowntimeWindow(start: TimeOfDay(hour: 21, minute: 30), end: TimeOfDay(hour: 6, minute: 0)),
                gamingLimitMinutes: isYoungChild ? 45 : 60,
                socialAppsLimitMinutes: isYoungChild ? 30 : 60,
                webContent: .limited,
                appInstallation: .parentApproval,
                blockExplicitContent: true,
                requirePasswordForPurchases: true,
                restrictSelectedApps: false,
                monitorDeviceActivity: true,
                requireScreenTimePasscode: true
            )

        case .protected:
            return ProtectionSettings(
                profile: .protected,
                downtime: isYoungChild
                    ? DowntimeWindow(start: TimeOfDay(hour: 20, minute: 0), end: TimeOfDay(hour: 7, minute: 0))
                    : DowntimeWindow(start: TimeOfDay(hour: 20, minute: 30), end: TimeOfDay(hour: 6, minute: 30)),
                gamingLimitMinutes: isYoungChild ? 30 : 45,
                socialAppsLimitMinutes: 30,
                webContent: .limited,
                appInstallation: .parentApproval,
                blockExplicitContent: true,
                requirePasswordForPurchases: true,
                restrictSelectedApps: true,
                monitorDeviceActivity: true,
                requireScreenTimePasscode: true
            )

        case .custom:
            var settings = ProtectionSettings.off
            settings.profile = .custom
            return settings
        }
    }
}
