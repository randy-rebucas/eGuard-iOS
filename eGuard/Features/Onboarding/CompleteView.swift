import SwiftUI

/// 09 Setup Complete
struct CompleteView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var isCelebrating = false

    var body: some View {
        EGuardScreen {
            OnboardingProgressIndicator(step: .complete)

            ZStack {
                ConfettiView()
                    .frame(height: 200)
                    .opacity(isCelebrating && isFullyProtected ? 1 : 0)
                Image(systemName: isFullyProtected ? "checkmark" : "checkmark.circle.trianglebadge.exclamationmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 110, height: 110)
                    .background(isFullyProtected ? EGuardColors.success : EGuardColors.warning, in: Circle())
                    .shadow(color: (isFullyProtected ? EGuardColors.success : EGuardColors.warning).opacity(0.3), radius: 16, y: 6)
                    .scaleEffect(isCelebrating ? 1 : 0.6)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, EGuardSpacing.md)

            VStack(spacing: EGuardSpacing.xs) {
                Text(isFullyProtected ? "You're all set!" : "Setup saved")
                    .font(EGuardTypography.display)
                    .foregroundStyle(EGuardColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(EGuardTypography.body)
                    .foregroundStyle(EGuardColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            if let report = model.lastHealthReport, !report.checks.isEmpty {
                EGuardCard {
                    ForEach(report.checks) { check in
                        ChecklistRow(title: checklistTitle(for: check), status: check.status)
                    }
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
        .brandNavigationTitle()
        .navigationBarBackButtonHidden()
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.3)) {
                isCelebrating = true
            }
        }
    }

    /// True only when every evaluated protection is verified active. The copy never overclaims.
    private var isFullyProtected: Bool {
        guard let report = model.lastHealthReport, report.evaluatedCount > 0 else { return false }
        return report.attentionChecks.isEmpty
    }

    private var subtitle: String {
        let device = model.childProfile?.deviceName ?? "your child's device"
        if isFullyProtected {
            return "eGuard has successfully set up and verified the safety settings on \(device)."
        }
        let count = model.lastHealthReport?.attentionChecks.count ?? 0
        let noun = count == 1 ? "1 setting" : "\(count) settings"
        return "\(device) is protected, but \(noun) still need attention. Finish them anytime from Manage Protection."
    }

    private func checklistTitle(for check: ConfigurationCheck) -> String {
        switch check.status {
        case .pass: "\(check.feature.title) configured"
        case .unsupported: "\(check.feature.title) not supported here"
        default: "\(check.feature.title) still needs attention"
        }
    }
}

#Preview {
    NavigationStack {
        CompleteView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
