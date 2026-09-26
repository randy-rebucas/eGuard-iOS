import Foundation

/// Verifies every enabled protection against what Apple's frameworks actually report.
/// Guided settings that Apple does not expose are never claimed as verified.
@MainActor
final class RunHealthCheckUseCase {
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

    func run(
        settings: ProtectionSettings,
        progress: SetupProgress,
        selections: ProtectionSelections,
        now: Date = .now
    ) -> ConfigurationHealthReport {
        authorization.refreshAuthorizationStatus()
        let isAuthorized = authorization.authorizationStatus.isAuthorized
        let restrictionState = restrictions.snapshot()
        let scheduleState = schedules.snapshot()

        let checks = settings.enabledFeatures.map { feature in
            check(
                feature,
                settings: settings,
                progress: progress,
                selections: selections,
                isAuthorized: isAuthorized,
                restrictionState: restrictionState,
                scheduleState: scheduleState,
                now: now
            )
        }
        return ConfigurationHealthReport(checks: checks, generatedAt: now)
    }

    // MARK: - Per-feature checks

    private func check(
        _ feature: ProtectionFeature,
        settings: ProtectionSettings,
        progress: SetupProgress,
        selections: ProtectionSelections,
        isAuthorized: Bool,
        restrictionState: RestrictionSnapshot,
        scheduleState: ActivityScheduleSnapshot,
        now: Date
    ) -> ConfigurationCheck {
        let capability = capabilities.capability(for: feature, settings: settings)
        let state = progress.state(for: feature)

        switch capability.mode {
        case .unsupported:
            return ConfigurationCheck(
                feature: feature,
                status: .unsupported,
                mode: .unsupported,
                explanation: capability.explanation
            )

        case .guided, .verificationOnly:
            return guidedCheck(feature, state: state, mode: capability.mode, explanation: capability.explanation)

        case .automatic:
            guard isAuthorized else {
                return ConfigurationCheck(
                    feature: feature,
                    status: .actionRequired,
                    mode: .automatic,
                    explanation: "eGuard is not authorized to configure parental controls.",
                    remediation: "Grant Family Controls authorization in eGuard, then check again."
                )
            }
            let verified = verifyAutomatic(
                feature,
                settings: settings,
                selections: selections,
                restrictionState: restrictionState,
                scheduleState: scheduleState
            )
            return automaticCheck(feature, verification: verified, state: state, now: now)
        }
    }

    private enum Verification {
        case active
        case inactive
        case selectionMissing
    }

    private func verifyAutomatic(
        _ feature: ProtectionFeature,
        settings: ProtectionSettings,
        selections: ProtectionSelections,
        restrictionState: RestrictionSnapshot,
        scheduleState: ActivityScheduleSnapshot
    ) -> Verification {
        switch feature {
        case .downtime:
            let matches = scheduleState.isDowntimeScheduled && scheduleState.downtimeWindow == settings.downtime
            return matches ? .active : .inactive

        case .gaming:
            if selections.gaming.isEmpty { return .selectionMissing }
            let matches = scheduleState.isDailyLimitMonitoring
                && scheduleState.gamingLimitMinutes == settings.gamingLimitMinutes
            return matches ? .active : .inactive

        case .socialApps:
            if selections.socialApps.isEmpty { return .selectionMissing }
            let matches = scheduleState.isDailyLimitMonitoring
                && scheduleState.socialAppsLimitMinutes == settings.socialAppsLimitMinutes
            return matches ? .active : .inactive

        case .webContent:
            return restrictionState.webContentLimited == (settings.webContent == .limited) ? .active : .inactive

        case .appInstallation:
            return restrictionState.denyAppInstallation == (settings.appInstallation == .blocked) ? .active : .inactive

        case .appRestrictions:
            if selections.restrictedApps.isEmpty { return .selectionMissing }
            return restrictionState.hasAppRestrictions ? .active : .inactive

        case .purchases:
            return restrictionState.requirePasswordForPurchases == true ? .active : .inactive

        case .explicitContent:
            return restrictionState.denyExplicitContent == true ? .active : .inactive

        case .deviceActivity:
            return scheduleState.isMonitoringAnything ? .active : .inactive

        case .screenTimePasscode:
            return .inactive
        }
    }

    private func automaticCheck(
        _ feature: ProtectionFeature,
        verification: Verification,
        state: FeatureConfigurationState,
        now: Date
    ) -> ConfigurationCheck {
        switch verification {
        case .active:
            return ConfigurationCheck(
                feature: feature,
                status: .pass,
                mode: .automatic,
                lastVerified: now,
                explanation: "Verified with Apple's frameworks."
            )

        case .selectionMissing:
            return ConfigurationCheck(
                feature: feature,
                status: .warning,
                mode: .automatic,
                lastVerified: now,
                explanation: "No apps are selected for this protection yet.",
                remediation: "Choose the apps this protection applies to, then configure it."
            )

        case .inactive:
            if state.isComplete {
                // Configuration drift: eGuard applied this earlier, but the system no longer reports it.
                return ConfigurationCheck(
                    feature: feature,
                    status: .actionRequired,
                    mode: .automatic,
                    lastVerified: now,
                    explanation: "This protection was configured earlier but is no longer active on the device.",
                    remediation: "Configure it again from Manage Protection."
                )
            }
            if let failure = state.failureMessage {
                return ConfigurationCheck(
                    feature: feature,
                    status: .actionRequired,
                    mode: .automatic,
                    lastVerified: now,
                    explanation: failure,
                    remediation: "Try configuring this protection again."
                )
            }
            return ConfigurationCheck(
                feature: feature,
                status: .notConfigured,
                mode: .automatic,
                lastVerified: now,
                explanation: "This protection has not been configured yet.",
                remediation: "Configure it from Manage Protection."
            )
        }
    }

    private func guidedCheck(
        _ feature: ProtectionFeature,
        state: FeatureConfigurationState,
        mode: ConfigurationMode,
        explanation: String
    ) -> ConfigurationCheck {
        switch state {
        case .confirmedByParent(let date):
            return ConfigurationCheck(
                feature: feature,
                status: .pass,
                mode: mode,
                lastVerified: date,
                explanation: "You marked this complete on \(date.formatted(date: .abbreviated, time: .shortened)). Apple does not let eGuard verify it automatically."
            )
        case .awaitingReturn:
            return ConfigurationCheck(
                feature: feature,
                status: .actionRequired,
                mode: mode,
                explanation: "You started this setting in Settings but haven't confirmed it in eGuard.",
                remediation: "Finish the steps in Settings, return to eGuard, and confirm."
            )
        case .configured(let date):
            return ConfigurationCheck(
                feature: feature,
                status: .pass,
                mode: mode,
                lastVerified: date,
                explanation: explanation
            )
        case .failed(let message):
            return ConfigurationCheck(
                feature: feature,
                status: .actionRequired,
                mode: mode,
                explanation: message,
                remediation: "Open Settings and follow the guided steps again."
            )
        case .notConfigured, .skipped:
            return ConfigurationCheck(
                feature: feature,
                status: .notConfigured,
                mode: mode,
                explanation: explanation,
                remediation: "Follow the guided steps in Settings, then confirm in eGuard."
            )
        }
    }
}
