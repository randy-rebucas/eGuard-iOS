import SwiftUI

/// 03 Protection Profile
struct ProtectionProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var selectedProfile: ProtectionProfile = .balanced
    @State private var hasLoaded = false

    var body: some View {
        EGuardScreen {
            OnboardingProgressIndicator(step: .protectionProfile)
            ScreenHeader(
                title: "Choose a protection profile",
                subtitle: childSubtitle
            )

            VStack(spacing: EGuardSpacing.sm) {
                ForEach(ProtectionProfile.allCases) { profile in
                    SelectableOptionRow(
                        title: profile.title,
                        subtitle: profile.summary,
                        symbolName: profile.symbolName,
                        isSelected: selectedProfile == profile
                    ) {
                        selectedProfile = profile
                    }
                    .accessibilityIdentifier("profile.option.\(profile.rawValue)")
                }
            }

            Text("You can change every recommendation on the next screen.")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        } actions: {
            Button("Continue") {
                model.chooseProfile(selectedProfile)
                router.push(.recommendedSetup)
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("profile.continue")
        }
        .navigationTitle(OnboardingStep.protectionProfile.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            if model.settings != .off || model.settings.profile != .custom {
                selectedProfile = model.settings.profile
            } else if let age = model.childProfile?.age, age < 10 {
                selectedProfile = .protected
            }
        }
    }

    private var childSubtitle: String? {
        guard let child = model.childProfile else { return nil }
        return "Recommendations are tuned for \(child.trimmedName), \(child.ageDescription)."
    }
}

#Preview {
    NavigationStack {
        ProtectionProfileView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
