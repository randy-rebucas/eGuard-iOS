import Foundation
import Testing
@testable import eGuard

@Suite("Profile recommendation")
struct RecommendationTests {
    let useCase = RecommendSetupUseCase()

    @Test func balancedMatchesSharedContract() {
        let settings = useCase.recommend(profile: .balanced, childAge: 12)
        #expect(settings.profile == .balanced)
        #expect(settings.downtime == DowntimeWindow(start: TimeOfDay(hour: 21, minute: 30), end: TimeOfDay(hour: 6, minute: 0)))
        #expect(settings.gamingLimitMinutes == 60)
        #expect(settings.socialAppsLimitMinutes == 60)
        #expect(settings.webContent == .limited)
        #expect(settings.appInstallation == .parentApproval)
        #expect(settings.summary(for: .gaming) == "1 hour / day")
        #expect(settings.summary(for: .webContent) == "Limited")
        #expect(settings.summary(for: .appInstallation) == "Parent approval")
    }

    @Test func protectedIsStricterThanBalanced() {
        let balanced = useCase.recommend(profile: .balanced, childAge: 12)
        let protected = useCase.recommend(profile: .protected, childAge: 12)
        #expect(protected.gamingLimitMinutes! < balanced.gamingLimitMinutes!)
        #expect(protected.socialAppsLimitMinutes! < balanced.socialAppsLimitMinutes!)
        #expect(protected.restrictSelectedApps)
        #expect(protected.downtime!.start < balanced.downtime!.start)
    }

    @Test func youngChildrenGetTighterAllowances() {
        let older = useCase.recommend(profile: .balanced, childAge: 14)
        let younger = useCase.recommend(profile: .balanced, childAge: 7)
        #expect(younger.gamingLimitMinutes! < older.gamingLimitMinutes!)
        #expect(younger.socialAppsLimitMinutes! < older.socialAppsLimitMinutes!)
    }

    @Test func customStartsWithEverythingOff() {
        let settings = useCase.recommend(profile: .custom, childAge: 12)
        #expect(settings.profile == .custom)
        #expect(settings.enabledFeatures.isEmpty)
    }
}

@Suite("Configuration state")
struct ConfigurationStateTests {
    @Test func dailyAllowanceFormatting() {
        #expect(ProtectionSettings.formatDailyAllowance(60) == "1 hour / day")
        #expect(ProtectionSettings.formatDailyAllowance(45) == "45 min / day")
        #expect(ProtectionSettings.formatDailyAllowance(120) == "2 hours / day")
        #expect(ProtectionSettings.formatDailyAllowance(90) == "1h 30m / day")
    }

    @Test func downtimeWindowValidation() {
        #expect(DowntimeWindow(start: TimeOfDay(hour: 21, minute: 30), end: TimeOfDay(hour: 6, minute: 0)).isValid)
        #expect(!DowntimeWindow(start: TimeOfDay(hour: 21, minute: 0), end: TimeOfDay(hour: 21, minute: 10)).isValid)
        #expect(!DowntimeWindow(start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 8, minute: 0)).isValid)
    }

    @Test func timeOfDayClampsAndOrders() {
        let clamped = TimeOfDay(hour: 30, minute: 75)
        #expect(clamped.hour == 23 && clamped.minute == 59)
        #expect(TimeOfDay(hour: 6, minute: 0) < TimeOfDay(hour: 21, minute: 30))
    }

    @Test func enabledFeaturesFollowSettings() {
        var settings = ProtectionSettings.off
        #expect(settings.enabledFeatures.isEmpty)
        settings.webContent = .limited
        settings.requireScreenTimePasscode = true
        #expect(settings.enabledFeatures == [.webContent, .screenTimePasscode])
        #expect(settings.isEnabled(.webContent))
        #expect(!settings.isEnabled(.downtime))
    }

    @Test func featureStateLabelsAndCompletion() {
        #expect(FeatureConfigurationState.notConfigured.statusLabel == "Ready to configure")
        #expect(FeatureConfigurationState.configured(.now).isComplete)
        #expect(FeatureConfigurationState.confirmedByParent(.now).isComplete)
        #expect(!FeatureConfigurationState.awaitingReturn(.now).isComplete)
        #expect(FeatureConfigurationState.failed("boom").failureMessage == "boom")
    }

    @Test func setupProgressCountsCompletedFeatures() {
        var progress = SetupProgress()
        progress.set(.configured(.now), for: .downtime)
        progress.set(.skipped, for: .gaming)
        progress.set(.confirmedByParent(.now), for: .screenTimePasscode)
        #expect(progress.completedCount(of: [.downtime, .gaming, .screenTimePasscode]) == 2)
        #expect(progress.state(for: .webContent) == .notConfigured)
    }

    @Test func setupProgressRoundTripsThroughJSON() throws {
        var progress = SetupProgress()
        progress.set(.failed("Nope"), for: .purchases)
        progress.isSetupComplete = true
        let data = try JSONEncoder().encode(progress)
        let decoded = try JSONDecoder().decode(SetupProgress.self, from: data)
        #expect(decoded == progress)
    }

    @Test func selectionSummaryNeverShowsIdentifiers() {
        let snapshot = ActivitySelectionSnapshot(encodedSelection: Data([0x01]), applicationCount: 3, categoryCount: 1, webDomainCount: 0)
        #expect(snapshot.summary == "3 apps, 1 category")
        #expect(ActivitySelectionSnapshot.empty.summary == "Nothing selected")
    }
}

@Suite("Health calculation")
struct HealthCalculationTests {
    private func check(_ feature: ProtectionFeature, _ status: HealthStatus) -> ConfigurationCheck {
        ConfigurationCheck(feature: feature, status: status, mode: .automatic)
    }

    @Test func scoreExcludesUnsupportedChecks() {
        let checks = [
            check(.downtime, .pass), check(.gaming, .pass), check(.webContent, .warning),
            check(.screenTimePasscode, .unsupported),
        ]
        let report = ConfigurationHealthReport(checks: checks, generatedAt: .now)
        #expect(report.passedCount == 2)
        #expect(report.evaluatedCount == 3)
        #expect(report.scoreText == "2 / 3")
        #expect(report.attentionChecks.count == 1)
    }

    @Test func summariesMatchSharedCopy() {
        #expect(HealthScoreCalculator.summary(passed: 10, total: 10) == "All protections are active.")
        #expect(HealthScoreCalculator.summary(passed: 9, total: 10) == "Most protections are active.")
        #expect(HealthScoreCalculator.summary(passed: 3, total: 10) == "Several protections need attention.")
        #expect(HealthScoreCalculator.summary(passed: 0, total: 4) == "No protections are active yet.")
        #expect(HealthScoreCalculator.summary(passed: 0, total: 0) == "No protections are configured yet.")
        #expect(HealthScoreCalculator.attentionSummary(count: 1) == "One setting needs review")
        #expect(HealthScoreCalculator.attentionSummary(count: 3) == "3 settings need review")
        #expect(HealthScoreCalculator.attentionSummary(count: 0) == nil)
    }

    @Test func protectionStateFollowsScore() {
        #expect(HealthScoreCalculator.protectionState(passed: 0, total: 0) == .notConfigured)
        #expect(HealthScoreCalculator.protectionState(passed: 2, total: 2) == .active)
        #expect(HealthScoreCalculator.protectionState(passed: 1, total: 2) == .needsAttention)
    }

    @Test func healthStatusRawValuesMatchContract() {
        #expect(HealthStatus.pass.rawValue == "PASS")
        #expect(HealthStatus.warning.rawValue == "WARNING")
        #expect(HealthStatus.actionRequired.rawValue == "ACTION_REQUIRED")
        #expect(HealthStatus.unsupported.rawValue == "UNSUPPORTED")
        #expect(HealthStatus.notConfigured.rawValue == "NOT_CONFIGURED")
    }

    @Test func driftIsActionRequired() {
        let report = ConfigurationHealthReport(checks: [check(.downtime, .actionRequired)], generatedAt: .now)
        #expect(report.hasDrift)
    }
}
