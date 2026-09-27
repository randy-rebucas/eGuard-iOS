import SwiftUI

/// 01 Welcome
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        EGuardScreen {
            EGuardWordmark(markSize: 30, showsTagline: true)
                .frame(maxWidth: .infinity)
                .padding(.top, EGuardSpacing.sm)

            OnboardingProgressIndicator(step: .welcome)

            VStack(alignment: .leading, spacing: EGuardSpacing.md) {
                Text("A safer digital world for their brighter tomorrow.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(EGuardColors.primary)
                    .accessibilityAddTraits(.isHeader)
                Text("eGuard helps you configure, manage, and verify digital safety protections for your children's devices.")
                    .font(EGuardTypography.body)
                    .foregroundStyle(EGuardColors.textSecondary)
            }

            FamilyIllustration(height: 260)

            if model.isSignedIn, let account = model.account {
                EGuardCard {
                    Label("Signed in as \(account.fullName). Let's finish setting up your child's device.", systemImage: "person.crop.circle.badge.checkmark")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
        } actions: {
            Button("Get Started") {
                router.push(model.isSignedIn ? .childDevice : .createAccount)
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("welcome.getStarted")

            if model.isSignedIn {
                Button("Already configured? Check my setup") {
                    router.push(.healthReview)
                }
                .buttonStyle(.eGuardText)
                .accessibilityIdentifier("welcome.checkSetup")
            } else {
                Button("I already have an account") {
                    router.push(.signIn)
                }
                .buttonStyle(.eGuardText)
                .accessibilityIdentifier("welcome.signIn")
            }
        }
        .background(EGuardColors.heroGradient.ignoresSafeArea())
        .navigationTitle(OnboardingStep.welcome.title)
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
