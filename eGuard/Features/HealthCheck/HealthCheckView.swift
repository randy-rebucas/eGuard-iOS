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

    /// "Fix 2 Settings", or nil when nothing needs attention.
    var fixTitle: String? {
        guard let count = report?.attentionChecks.count, count > 0 else { return nil }
        return count == 1 ? "Fix 1 Setting" : "Fix \(count) Settings"
    }
}

/// 08 Configuration Health. Also reused for "View Health Check" from the dashboard.
struct HealthCheckView: View {
    let isOnboarding: Bool

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = HealthCheckViewModel()

    var body: some View {
        EGuardScreen {
            if isOnboarding {
                OnboardingProgressIndicator(step: .healthCheck)
                ScreenHeader(title: "Configuration Health")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if !model.isOnline {
                OfflineBanner(lastVerified: viewModel.report?.generatedAt)
            }

            if let report = viewModel.report {
                scoreGauge(report)
                checksCard(report)
                if let attention = report.attentionSummary {
                    attentionCard(attention)
                }
            } else {
                EmptyStateView(
                    symbolName: "heart.text.square",
                    title: "No health check yet",
                    message: "eGuard verifies each protection against what Apple's frameworks report."
                )
            }
        } actions: {
            if isOnboarding {
                Button(viewModel.fixTitle ?? "Continue") {
                    if let feature = viewModel.firstAttentionFeature {
                        router.push(.featureDetail(feature))
                    } else {
                        router.push(.complete)
                    }
                }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier(viewModel.fixTitle == nil ? "health.continue" : "health.fix")
                if viewModel.fixTitle != nil {
                    Button("Continue anyway") { router.push(.complete) }
                        .buttonStyle(.eGuardText)
                        .accessibilityIdentifier("health.continue")
                }
                Button("Check Again") { viewModel.run(using: model) }
                    .buttonStyle(.eGuardText)
                    .accessibilityIdentifier("health.checkAgain")
            } else {
                if let fixTitle = viewModel.fixTitle {
                    Button(fixTitle) {
                        if let feature = viewModel.firstAttentionFeature {
                            router.push(.featureDetail(feature))
                        }
                    }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("health.fix")
                    Button("Check Again") { viewModel.run(using: model) }
                        .buttonStyle(.eGuardText)
                        .accessibilityIdentifier("health.checkAgain")
                } else {
                    Button("Check Again") { viewModel.run(using: model) }
                        .buttonStyle(.eGuardPrimary)
                        .accessibilityIdentifier("health.checkAgain")
                }
            }
        }
        .modifier(HealthTitle(isOnboarding: isOnboarding))
        .onAppear {
            viewModel.loadStored(from: model)
            viewModel.run(using: model)
        }
    }

    private func scoreGauge(_ report: ConfigurationHealthReport) -> some View {
        let tint = EGuardTheme.color(for: report.protectionState)
        let progress = report.evaluatedCount == 0 ? 0 : Double(report.passedCount) / Double(report.evaluatedCount)
        return VStack(spacing: EGuardSpacing.sm) {
            RingGauge(progress: progress, tint: tint, lineWidth: 16, size: 170) {
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(report.passedCount)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(EGuardColors.textPrimary)
                        Text("/ \(report.evaluatedCount)")
                            .font(EGuardTypography.title3)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                    Text(EGuardTheme.grade(passed: report.passedCount, total: report.evaluatedCount))
                        .font(EGuardTypography.label)
                        .foregroundStyle(tint)
                }
            }
            .accessibilityLabel("Health score \(report.scoreText). \(report.summary)")
            .accessibilityIdentifier("health.score")

            Text(report.summary)
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
            Text("Last verified \(report.generatedAt.verifiedDescription())")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func checksCard(_ report: ConfigurationHealthReport) -> some View {
        EGuardCard {
            ForEach(report.checks) { check in
                Button {
                    router.push(.featureDetail(check.feature))
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: EGuardSpacing.sm) {
                        Image(systemName: EGuardTheme.symbol(for: check.status))
                            .foregroundStyle(EGuardTheme.color(for: check.status))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.feature.title)
                                .font(EGuardTypography.label)
                                .foregroundStyle(EGuardColors.textPrimary)
                            if check.status != .pass, let remediation = check.remediation {
                                Text(remediation)
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer()
                        HealthStatusBadge(status: check.status)
                    }
                    .padding(.vertical, EGuardSpacing.xxs)
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
            Text("Tap a setting above to see what to do, or use the button below to start with the first one.")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
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

private struct HealthTitle: ViewModifier {
    let isOnboarding: Bool

    func body(content: Content) -> some View {
        if isOnboarding {
            content.brandNavigationTitle()
        } else {
            content
                .navigationTitle("Configuration Health")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        HealthCheckView(isOnboarding: true)
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
