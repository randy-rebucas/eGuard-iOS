import SwiftUI

/// 09 Setup Complete. Lists what the device verified, straight from the last batch or the health report.
struct CompleteView: View {
    let childId: String
    let batchId: String?

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var isCelebrating = false
    @State private var state: LoadState<HealthReport> = .loading

    private var child: ChildSummary? { model.children.first { $0.id == childId } }

    /// True only when every evaluated protection is verified. The copy never overclaims.
    private var isFullyProtected: Bool {
        guard let report = state.value, report.total > 0 else { return false }
        return report.fixCount == 0
    }

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

            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadReport() } }
            case .loaded(let report):
                EGuardCard {
                    ForEach(report.checks) { check in
                        ChecklistRow(title: title(for: check), status: check.status.healthStatus)
                    }
                }
            }

            EGuardCard {
                Label("eGuard re-checks every protection each time a device syncs.", systemImage: "arrow.clockwise.circle.fill")
                Label("Alerts tell you when something stops working.", systemImage: "bell.badge.fill")
            }
            .font(EGuardTypography.callout)
        } actions: {
            Button("Go to Dashboard") {
                Task {
                    await model.refreshDashboard()
                    router.popToRoot()
                }
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("complete.goToDashboard")
        }
        .brandNavigationTitle()
        .navigationBarBackButtonHidden()
        .task { await loadReport() }
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.3)) {
                isCelebrating = true
            }
        }
    }

    private func loadReport() async {
        state = .loading
        state = await load { try await model.api.health(childId: childId) }
    }

    private var subtitle: String {
        let device = child?.deviceName ?? "your child's device"
        guard let report = state.value else { return "Checking what the device verified…" }
        if report.total == 0 || child?.deviceCount == 0 {
            return "Your settings are saved. eGuard applies and verifies them as soon as \(child?.name ?? "your child")'s device is paired."
        }
        if isFullyProtected {
            return "eGuard has successfully set up and verified the safety settings on \(device)."
        }
        let noun = report.fixCount == 1 ? "1 setting" : "\(report.fixCount) settings"
        return "\(device) is protected, but \(noun) still need attention. Finish them anytime from Protection & Controls."
    }

    private func title(for check: HealthCheck) -> String {
        switch check.status {
        case .pass: "\(check.name) verified"
        case .unsupported: "\(check.name) not supported here"
        case .notConfigured: child?.deviceCount == 0 ? "\(check.name) saved" : "\(check.name) not configured"
        default: "\(check.name) needs attention"
        }
    }
}

#Preview {
    NavigationStack {
        CompleteView(childId: "child_1", batchId: nil)
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
