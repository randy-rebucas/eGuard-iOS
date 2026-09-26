import Observation
import SwiftUI

/// Runs and presents the Configuration Health Check.
@Observable
final class HealthCheckViewModel {
    private(set) var report: ConfigurationHealthReport?
    private(set) var isChecking = false

    func run(using model: AppModel) {
        isChecking = true
        report = model.performHealthCheck()
        isChecking = false
    }

    func loadStored(from model: AppModel) {
        report = model.lastHealthReport
    }

    var firstAttentionFeature: ProtectionFeature? {
        report?.attentionChecks.first?.feature
    }
}

/// 06 Configuration Health Check. Also reused for "View Health Check" from the dashboard.
struct HealthCheckView: View {
    let isOnboarding: Bool

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = HealthCheckViewModel()

    var body: some View {
        EGuardScreen {
            if isOnboarding {
                OnboardingProgressIndicator(step: .healthCheck)
            }
            ScreenHeader(title: "Configuration Health")

            if !model.isOnline {
                OfflineBanner(lastVerified: viewModel.report?.generatedAt)
            }

            if let report = viewModel.report {
                scoreCard(report)
                checksCard(report)
                if let attention = report.attentionSummary {
                    attentionCard(attention)
                }
            } else {
                EGuardCard {
                    Text("No health check has been run yet.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
        } actions: {
            if isOnboarding {
                Button("Continue") { router.push(.complete) }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("health.continue")
                Button("Check Again") { viewModel.run(using: model) }
                    .buttonStyle(.eGuardText)
                    .accessibilityIdentifier("health.checkAgain")
            } else {
                Button("Check Again") { viewModel.run(using: model) }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("health.checkAgain")
            }
        }
        .navigationTitle(isOnboarding ? OnboardingStep.healthCheck.title : "Configuration Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadStored(from: model)
            viewModel.run(using: model)
        }
    }

    private func scoreCard(_ report: ConfigurationHealthReport) -> some View {
        EGuardCard {
            Text(report.scoreText)
                .font(EGuardTypography.metric)
                .foregroundStyle(EGuardTheme.color(for: report.protectionState))
                .accessibilityIdentifier("health.score")
            Text(report.summary)
                .font(EGuardTypography.headline)
            EGuardValueRow(label: "Last verified", value: report.generatedAt.verifiedDescription())
        }
        .accessibilityElement(children: .combine)
    }

    private func checksCard(_ report: ConfigurationHealthReport) -> some View {
        EGuardCard {
            ForEach(report.checks) { check in
                Button {
                    router.push(.featureDetail(check.feature))
                } label: {
                    HStack(alignment: .top, spacing: EGuardSpacing.sm) {
                        Image(systemName: EGuardTheme.symbol(for: check.status))
                            .foregroundStyle(EGuardTheme.color(for: check.status))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: EGuardSpacing.xxs) {
                            HStack {
                                Text(check.feature.title)
                                    .font(EGuardTypography.headline)
                                    .foregroundStyle(EGuardColors.textPrimary)
                                Spacer()
                                HealthStatusBadge(status: check.status)
                            }
                            if let explanation = check.explanation {
                                Text(explanation)
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            if let remediation = check.remediation {
                                Text(remediation)
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.primary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("health.check.\(check.feature.rawValue)")
                if check.id != report.checks.last?.id {
                    Divider()
                }
            }
        }
    }

    private func attentionCard(_ attention: String) -> some View {
        EGuardCard {
            Label(attention, systemImage: "exclamationmark.triangle.fill")
                .font(EGuardTypography.headline)
                .foregroundStyle(EGuardColors.warning)
            Button("Review") {
                if let feature = viewModel.firstAttentionFeature {
                    router.push(.featureDetail(feature))
                }
            }
            .buttonStyle(.eGuardSecondary)
            .accessibilityIdentifier("health.review")
        }
    }
}

#Preview {
    NavigationStack {
        HealthCheckView(isOnboarding: true)
    }
    .environment(AppModel.make(arguments: ["-uiTesting", "-setupComplete"]))
    .environment(AppRouter())
}
