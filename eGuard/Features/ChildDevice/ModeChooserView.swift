import SwiftUI

/// First launch: "Who's using this device?" Picking an option never stores a mode by itself;
/// the install becomes a parent's or a child's only once sign-in or pairing succeeds.
struct ModeChooserView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        EGuardScreen {
            EGuardWordmark(markSize: 30, showsTagline: true)
                .frame(maxWidth: .infinity)
                .padding(.top, EGuardSpacing.sm)

            ScreenHeader(
                title: "Who's using this device?",
                subtitle: "eGuard is one app for the whole family. Tell us whose device this is."
            )

            Button {
                model.chooseParentSide()
                router.push(.welcome)
            } label: {
                choiceCard(
                    symbol: "person.2.fill",
                    tint: EGuardColors.primary,
                    title: "I'm a parent or guardian",
                    detail: "Sign in or create an account to set up and check your children's protections from this phone."
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mode.parent")

            Button {
                router.push(.childSetup)
            } label: {
                choiceCard(
                    symbol: "figure.child",
                    tint: EGuardColors.tilePurple,
                    title: "This is my child's device",
                    detail: "Enter the pairing code from a parent's eGuard app. This device then follows the protections they chose."
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mode.child")

            EGuardCard {
                Label("Nobody signs in on a child's device, and no parent screens are reachable from it. You can go back and choose again until sign-in or pairing finishes.", systemImage: "lock.shield")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            EmptyView()
        }
        .background(EGuardColors.heroGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func choiceCard(symbol: String, tint: Color, title: String, detail: String) -> some View {
        EGuardCard {
            HStack(alignment: .top, spacing: EGuardSpacing.md) {
                IconTile(symbolName: symbol, tint: tint, size: 56, filled: true)
                VStack(alignment: .leading, spacing: EGuardSpacing.xxs) {
                    Text(title)
                        .font(EGuardTypography.title3)
                        .foregroundStyle(EGuardColors.textPrimary)
                    Text(detail)
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(EGuardColors.neutral)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        ModeChooserView()
    }
    .environment(AppModel.mock(mode: .unset))
    .environment(AppRouter())
}
