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

            if let user = model.user {
                EGuardCard {
                    Label("Signed in as \(user.name). Add your first child to get started.", systemImage: "person.crop.circle.badge.checkmark")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                VerifyEmailBanner()
            }

            if let error = model.refreshError, model.isSignedIn {
                ErrorCard(message: error) { Task { await model.refreshDashboard() } }
            }
        } actions: {
            Button(model.isSignedIn ? "Add Your First Child" : "Get Started") {
                router.push(model.isSignedIn ? .addChild : .createAccount)
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("welcome.getStarted")

            if model.isSignedIn {
                Button("Sign out") {
                    Task { await model.signOut() }
                }
                .buttonStyle(.eGuardText)
                .accessibilityIdentifier("welcome.signOut")
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
