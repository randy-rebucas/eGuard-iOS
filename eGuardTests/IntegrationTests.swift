import Foundation
import Testing
@testable import eGuard

/// Integration of the use cases with mock platform services.
@Suite("Configuration and verification")
struct ConfigurationIntegrationTests {
    private func makeModel(
        status: ParentalControlAuthorizationStatus = .approved,
        environment: PlatformEnvironment = .iPhone
    ) -> AppModel {
        let model = AppModel.mock(authorizationStatus: status, environment: environment)
        model.saveChildProfile(ChildProfile(name: "Mia", age: 12))
        model.chooseProfile(.balanced)
        return model
    }

    private func selection(apps: Int) -> ActivitySelectionSnapshot {
        ActivitySelectionSnapshot(encodedSelection: Data([0xEE]), applicationCount: apps)
    }

    @Test func automaticFeatureIsVerifiedAfterApplying() {
        let model = makeModel()
        let state = model.configure(.webContent)
        #expect(state.isComplete)

        let report = model.performHealthCheck()
        let webCheck = report.checks.first { $0.feature == .webContent }
        #expect(webCheck?.status == .pass)
        #expect(webCheck?.lastVerified != nil)
    }

    @Test func deniedAuthorizationNeverReportsSuccess() {
        let model = makeModel(status: .denied)
        let state = model.configure(.webContent)
        #expect(!state.isComplete)
        #expect(state.failureMessage == ProtectionConfigurationError.notAuthorized.localizedDescription)

        let report = model.performHealthCheck()
        #expect(report.checks.allSatisfy { $0.status != .pass })
        #expect(report.checks.first { $0.feature == .webContent }?.status == .actionRequired)
    }

    @Test func limitsRequireAnAppSelection() {
        let model = makeModel()
        let failed = model.configure(.gaming)
        #expect(failed.failureMessage == ProtectionConfigurationError.selectionRequired.localizedDescription)

        model.updateSelection(selection(apps: 2), for: .gaming)
        let configured = model.configure(.gaming)
        #expect(configured.isComplete)

        let report = model.performHealthCheck()
        #expect(report.checks.first { $0.feature == .gaming }?.status == .pass)
        #expect(report.checks.first { $0.feature == .socialApps }?.status == .warning)
    }

    @Test func downtimeScheduleIsVerifiedAgainstSettings() {
        let model = makeModel()
        #expect(model.configure(.downtime).isComplete)
        #expect(model.performHealthCheck().checks.first { $0.feature == .downtime }?.status == .pass)

        var edited = model.settings
        edited.downtime = DowntimeWindow(start: TimeOfDay(hour: 20, minute: 0), end: TimeOfDay(hour: 7, minute: 0))
        model.updateSettings(edited)
        #expect(model.progress.state(for: .downtime) == .notConfigured)
        #expect(model.performHealthCheck().checks.first { $0.feature == .downtime }?.status == .notConfigured)
    }

    @Test func driftIsDetectedWhenSystemDropsSettings() {
        let model = makeModel()
        model.configure(.webContent)
        model.configure(.purchases)
        #expect(model.performHealthCheck().hasDrift == false)

        (model.restrictions as? MockRestrictionService)?.simulateDrift()
        let report = model.performHealthCheck()
        #expect(report.hasDrift)
        #expect(report.checks.first { $0.feature == .webContent }?.status == .actionRequired)
        #expect(report.attentionSummary != nil)
    }

    @Test func guidedFeaturesRelyOnParentConfirmation() {
        let model = makeModel()
        var report = model.performHealthCheck()
        #expect(report.checks.first { $0.feature == .screenTimePasscode }?.status == .notConfigured)

        model.markGuidedStepOpened(.screenTimePasscode)
        report = model.performHealthCheck()
        #expect(report.checks.first { $0.feature == .screenTimePasscode }?.status == .actionRequired)

        model.confirmGuidedStep(.screenTimePasscode)
        report = model.performHealthCheck()
        let check = report.checks.first { $0.feature == .screenTimePasscode }
        #expect(check?.status == .pass)
        #expect(check?.mode == .guided)
        #expect(check?.explanation?.contains("does not let eGuard verify") == true)
    }

    @Test func unsupportedPlatformIsReportedHonestly() {
        let model = makeModel(environment: .unavailable)
        let state = model.configure(.webContent)
        #expect(!state.isComplete)

        let report = model.performHealthCheck()
        let webCheck = report.checks.first { $0.feature == .webContent }
        #expect(webCheck?.status == .unsupported)
        #expect(!report.checks.map(\.status).filter(\.isEvaluated).isEmpty)
    }

    @Test func fullSetupFlowReachesCompletion() {
        let model = makeModel()
        model.updateSelection(selection(apps: 3), for: .gaming)
        model.updateSelection(selection(apps: 2), for: .socialApps)
        for feature in model.settings.enabledFeatures {
            switch model.capability(for: feature).mode {
            case .automatic: model.configure(feature)
            case .guided: model.confirmGuidedStep(feature)
            default: break
            }
        }
        let report = model.performHealthCheck()
        #expect(report.passedCount == report.evaluatedCount)
        #expect(report.summary == "All protections are active.")

        model.completeSetup()
        #expect(model.progress.isSetupComplete)

        model.resetEverything()
        #expect(!model.progress.isSetupComplete)
        #expect(model.childProfile == nil)
        #expect(model.restrictions.snapshot() == .empty)
        #expect(model.schedules.snapshot() == .empty)
    }

    @Test func offlineModeKeepsPreviousReport() {
        let model = makeModel()
        model.configure(.webContent)
        let report = model.performHealthCheck()
        // The stored report is what the offline UI shows, with its own verification time.
        #expect(model.lastHealthReport == report)
        #expect(report.generatedAt.verifiedDescription().hasPrefix("Today"))
    }

    @Test func stateSurvivesRepositoryRoundTrip() throws {
        let repository = LocalStateRepository.inMemory()
        let profile = ChildProfile(name: "Mia", age: 9, device: .iPad, relationship: .thisDeviceOwner)
        try repository.saveChildProfile(profile)
        try repository.saveSettings(RecommendSetupUseCase().recommend(profile: .protected, childAge: 9))
        #expect(try repository.loadChildProfile() == profile)
        #expect(try repository.loadSettings()?.profile == .protected)
        try repository.eraseAll()
        #expect(try repository.loadChildProfile() == nil)
    }
}
