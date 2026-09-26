import SwiftUI

/// 07 Complete
struct CompleteView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        EGuardScreen {
            OnboardingProgressIndicator(step: .complete)

            EGuardIllustration(symbolName: "checkmark.shield.fill", tint: EGuardColors.success, size: 120)
                .frame(maxWidth: .infinity)
                .padding(.top, EGuardSpacing.lg)

            ScreenHeader(
                title: "You're all set",
                subtitle: subtitle
            )

            if let report = model.lastHealthReport {
                EGuardCard {
                    Text("Configuration Health")
                        .font(EGuardTypography.overline)
                        .foregroundStyle(EGuardColors.textSecondary)
                    Text(report.scoreText)
                        .font(EGuardTypography.metric)
                        .foregroundStyle(EGuardTheme.color(for: report.protectionState))
                    Text(report.summary)
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }

            EGuardCard {
                Label("eGuard re-checks your configuration every time you open it.", systemImage: "arrow.clockwise.circle.fill")
                Label("Nothing on this device is monitored secretly.", systemImage: "eye.slash.fill")
            }
            .font(EGuardTypography.callout)
        } actions: {
            Button("Go to Dashboard") {
                model.completeSetup()
                router.popToRoot()
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("complete.goToDashboard")
        }
        .navigationTitle(OnboardingStep.complete.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }

    private var subtitle: String {
        if let child = model.childProfile {
            return "\(child.trimmedName)'s \(child.device.displayName) is set up with the \(model.settings.profile.title) profile."
        }
        return "Your child's device is set up with the \(model.settings.profile.title) profile."
    }
}

#Preview {
    NavigationStack {
        CompleteView()
    }
    .environment(AppModel.make(arguments: ["-uiTesting", "-setupComplete"]))
    .environment(AppRouter())
}
