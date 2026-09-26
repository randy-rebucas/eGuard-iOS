import SwiftUI

/// 01 Welcome
struct WelcomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        EGuardScreen {
            OnboardingProgressIndicator(step: .welcome)

            VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
                EGuardIllustration(symbolName: "shield.lefthalf.filled", size: 120)
                    .frame(maxWidth: .infinity)
                    .padding(.top, EGuardSpacing.lg)

                Text("eGuard")
                    .font(EGuardTypography.overline)
                    .foregroundStyle(EGuardColors.primary)
                    .textCase(.uppercase)

                ScreenHeader(
                    title: "Simple Digital Protection for Your Family",
                    subtitle: "Set up your child's device with clear, age-appropriate protection."
                )

                EGuardCard {
                    Label("Set it up once.", systemImage: "1.circle.fill")
                    Label("eGuard helps you configure the right protections.", systemImage: "2.circle.fill")
                    Label("eGuard verifies that they are actually active.", systemImage: "3.circle.fill")
                }
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textPrimary)
            }
        } actions: {
            Button("Get Started") {
                router.push(.childDevice)
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("welcome.getStarted")

            Button("Already configured? Check my setup") {
                router.push(.healthReview)
            }
            .buttonStyle(.eGuardText)
            .accessibilityIdentifier("welcome.checkSetup")
        }
        .navigationTitle(OnboardingStep.welcome.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
