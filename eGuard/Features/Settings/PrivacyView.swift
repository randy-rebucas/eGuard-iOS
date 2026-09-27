import SwiftUI

/// What eGuard does and does not do with family data.
struct PrivacyView: View {
    var body: some View {
        EGuardScreen {
            EGuardIllustration(symbolName: "lock.shield.fill", size: 96)
                .frame(maxWidth: .infinity)
            ScreenHeader(
                title: "Your data stays with you",
                subtitle: "eGuard has no servers. Everything it stores lives on this device."
            )

            EGuardCard {
                SectionHeader(title: "What eGuard does")
                point("Configures Apple's Screen Time protections and verifies they are active.", symbol: "checkmark.shield.fill", tint: EGuardColors.success)
                Divider()
                point("Stores your child's name, age, and photo in the device Keychain.", symbol: "key.fill", tint: EGuardColors.primary)
                Divider()
                point("Keeps app choices as Apple's privacy-preserving tokens, never app names.", symbol: "lock.fill", tint: EGuardColors.tilePurple)
                Divider()
                point("Reads location only while the app is open and only if you turn sharing on.", symbol: "location.fill", tint: EGuardColors.success)
            }

            EGuardCard {
                SectionHeader(title: "What eGuard never does")
                point("Read messages, record audio or video, or collect passwords.", symbol: "eye.slash.fill", tint: EGuardColors.danger)
                Divider()
                point("Upload family information or usage data anywhere.", symbol: "icloud.slash.fill", tint: EGuardColors.danger)
                Divider()
                point("Monitor your child secretly. Apple shows the child that Screen Time is managed.", symbol: "person.fill.viewfinder", tint: EGuardColors.danger)
            }
        } actions: {
            EmptyView()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: EGuardSpacing.sm) {
            IconTile(symbolName: symbol, tint: tint, size: 32)
            Text(text)
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textPrimary)
        }
        .padding(.vertical, EGuardSpacing.xxs)
    }
}

#Preview {
    NavigationStack {
        PrivacyView()
    }
}
