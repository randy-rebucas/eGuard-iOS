import Foundation

/// Applies one automatic protection with Apple's frameworks and reports exactly what happened.
/// Never reports success unless the platform call completed without error.
@MainActor
final class ApplyProtectionUseCase {
    private let restrictions: RestrictionService
    private let schedules: ActivityScheduleService
    private let authorization: ParentalControlAuthorizationService
    private let capabilities: CapabilityResolver

    init(
        restrictions: RestrictionService,
        schedules: ActivityScheduleService,
        authorization: ParentalControlAuthorizationService,
        capabilities: CapabilityResolver
    ) {
        self.restrictions = restrictions
        self.schedules = schedules
        self.authorization = authorization
        self.capabilities = capabilities
    }

    func apply(
        _ feature: ProtectionFeature,
        settings: ProtectionSettings,
        selections: ProtectionSelections,
        now: Date = .now
    ) -> FeatureConfigurationState {
        let capability = capabilities.capability(for: feature, settings: settings)
        guard capability.mode == .automatic else {
            return .failed(ProtectionConfigurationError.unsupported.localizedDescription)
        }
        authorization.refreshAuthorizationStatus()
        guard authorization.authorizationStatus.isAuthorized else {
            return .failed(ProtectionConfigurationError.notAuthorized.localizedDescription)
        }

        do {
            try applyAutomatically(feature, settings: settings, selections: selections)
            return .configured(now)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Removes every restriction and schedule eGuard applied.
    func removeAllProtections() {
        restrictions.clearAllRestrictions()
        schedules.stopAll()
    }

    private func applyAutomatically(
        _ feature: ProtectionFeature,
        settings: ProtectionSettings,
        selections: ProtectionSelections
    ) throws {
        switch feature {
        case .downtime:
            guard let window = settings.downtime else {
                schedules.stopDowntime()
                return
            }
            guard window.isValid else { throw ProtectionConfigurationError.invalidSchedule }
            try schedules.scheduleDowntime(window)

        case .gaming:
            guard settings.gamingLimitMinutes != nil, !selections.gaming.isEmpty else {
                throw ProtectionConfigurationError.selectionRequired
            }
            try scheduleDailyLimits(settings: settings, selections: selections)

        case .socialApps:
            guard settings.socialAppsLimitMinutes != nil, !selections.socialApps.isEmpty else {
                throw ProtectionConfigurationError.selectionRequired
            }
            try scheduleDailyLimits(settings: settings, selections: selections)

        case .deviceActivity:
            // Device Activity is active when at least one schedule is registered.
            var registeredSomething = false
            if let window = settings.downtime, window.isValid {
                try schedules.scheduleDowntime(window)
                registeredSomething = true
            }
            if hasUsableDailyLimit(settings: settings, selections: selections) {
                try scheduleDailyLimits(settings: settings, selections: selections)
                registeredSomething = true
            }
            guard registeredSomething else {
                throw ProtectionConfigurationError.platformError(
                    "Turn on Downtime or a daily limit with selected apps so eGuard has something to monitor."
                )
            }

        case .webContent:
            try restrictions.applyWebContent(settings.webContent)

        case .appInstallation:
            try restrictions.applyAppInstallation(settings.appInstallation)

        case .appRestrictions:
            guard !selections.restrictedApps.isEmpty else { throw ProtectionConfigurationError.selectionRequired }
            try restrictions.applyAppRestrictions(selections.restrictedApps)
            try restrictions.applyWebsiteRestrictions(selections.websites)

        case .purchases:
            try restrictions.applyPurchaseProtection(requirePassword: settings.requirePasswordForPurchases)

        case .explicitContent:
            try restrictions.applyExplicitContent(block: settings.blockExplicitContent)

        case .screenTimePasscode:
            throw ProtectionConfigurationError.unsupported
        }
    }

    private func hasUsableDailyLimit(settings: ProtectionSettings, selections: ProtectionSelections) -> Bool {
        (settings.gamingLimitMinutes != nil && !selections.gaming.isEmpty)
            || (settings.socialAppsLimitMinutes != nil && !selections.socialApps.isEmpty)
    }

    /// Gaming and social limits share one Device Activity schedule, so both are re-registered together.
    /// A limit without a selection is skipped; otherwise it would apply to every app on the device.
    private func scheduleDailyLimits(settings: ProtectionSettings, selections: ProtectionSelections) throws {
        let gaming = settings.gamingLimitMinutes.flatMap { minutes -> DailyLimit? in
            selections.gaming.isEmpty ? nil : DailyLimit(minutes: minutes, selection: selections.gaming)
        }
        let social = settings.socialAppsLimitMinutes.flatMap { minutes -> DailyLimit? in
            selections.socialApps.isEmpty ? nil : DailyLimit(minutes: minutes, selection: selections.socialApps)
        }
        if gaming == nil && social == nil {
            schedules.stopDailyLimits()
            return
        }
        try schedules.scheduleDailyLimits(gaming: gaming, socialApps: social)
    }
}
