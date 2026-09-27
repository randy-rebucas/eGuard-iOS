import SwiftUI

/// 05 Protection Profile, from `GET /profiles?age=`.
struct ProtectionProfileView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<[ProfileOption]> = .loading
    @State private var selected: String?

    private var child: ChildSummary? { model.children.first { $0.id == childId } }

    var body: some View {
        EGuardScreen {
            OnboardingProgressIndicator(step: .protectionProfile)
            ScreenHeader(
                title: "Choose a protection profile",
                subtitle: "You can change this anytime in the app."
            )

            if let child {
                HStack(spacing: EGuardSpacing.sm) {
                    ChildAvatar(child: child, size: 40)
                    Text("Recommendations are tuned for \(child.name), \(child.ageDescription).")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }

            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadProfiles() } }
            case .loaded(let profiles):
                VStack(spacing: EGuardSpacing.sm) {
                    ForEach(profiles) { profile in
                        SelectableOptionRow(
                            title: profile.recommended ? "\(profile.name) · Recommended" : profile.name,
                            subtitle: profile.description,
                            symbolName: LucideIcon.symbol(for: profile.icon),
                            tint: tint(for: profile.id),
                            isSelected: selected == profile.id
                        ) {
                            selected = profile.id
                        }
                        .accessibilityIdentifier("profile.option.\(profile.id.lowercased())")
                    }
                }
                Text("All profiles keep every protection on. You can change each value on the next screen.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            Button("Continue") {
                if let selected {
                    router.push(.recommendedSetup(childId: childId, profile: selected))
                }
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(selected == nil)
            .accessibilityIdentifier("profile.continue")
        }
        .brandNavigationTitle()
        .task { await loadProfiles() }
    }

    private func loadProfiles() async {
        state = .loading
        let age = child?.age ?? 12
        state = await load { try await model.api.profiles(age: age) }
        if selected == nil, let profiles = state.value {
            selected = profiles.first { $0.recommended }?.id ?? profiles.first?.id
        }
    }

    private func tint(for id: String) -> Color {
        switch id {
        case "BALANCED": EGuardColors.tileYellow
        case "PROTECTED": EGuardColors.success
        default: EGuardColors.tileGray
        }
    }
}

#Preview {
    NavigationStack {
        ProtectionProfileView(childId: "child_1")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
