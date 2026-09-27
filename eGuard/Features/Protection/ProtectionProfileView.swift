import SwiftUI

/// 05 Protection Profile
struct ProtectionProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var selectedProfile: ProtectionProfile = .balanced
    @State private var hasLoaded = false

    private var isEditing: Bool { model.isSetupComplete }

    var body: some View {
        EGuardScreen {
            if !isEditing {
                OnboardingProgressIndicator(step: .protectionProfile)
            }
            ScreenHeader(
                title: "Choose a protection profile",
                subtitle: "You can change this anytime in the app."
            )

            if let child = model.childProfile {
                HStack(spacing: EGuardSpacing.sm) {
                    AvatarView(name: child.trimmedName, imageData: child.photoData, size: 40)
                    Text("Recommendations are tuned for \(child.trimmedName), \(child.ageDescription).")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }

            VStack(spacing: EGuardSpacing.sm) {
                ForEach(ProtectionProfile.allCases) { profile in
                    SelectableOptionRow(
                        title: profile.title,
                        subtitle: subtitle(for: profile),
                        symbolName: profile.symbolName,
                        tint: EGuardTheme.tint(for: profile),
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
        .brandNavigationTitle()
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

    private func subtitle(for profile: ProtectionProfile) -> String {
        switch profile {
        case .balanced: "Moderate limits for independent kids"
        case .protected: "Stronger controls for younger children"
        case .custom: "Choose settings yourself"
        }
    }
}

#Preview {
    NavigationStack {
        ProtectionProfileView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
