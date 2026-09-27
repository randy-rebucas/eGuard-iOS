import SwiftUI

/// Version, tagline, and credits.
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        EGuardScreen {
            EGuardSplashLogo()
                .frame(maxWidth: .infinity)
                .padding(.top, EGuardSpacing.lg)

            Text("Simple Setup. Stronger Protection. A Safer Tomorrow.")
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            EGuardCard {
                EGuardValueRow(label: "Version", value: "\(version) (\(build))")
                Divider()
                EGuardValueRow(label: "Platform", value: "iOS · Screen Time frameworks")
                Divider()
                EGuardValueRow(label: "Data storage", value: "This device only")
            }

            EGuardCard {
                Text("eGuard helps parents configure, manage, and verify Apple's built-in parental controls with clear, honest status reporting. It never claims a protection is active unless Apple's frameworks confirm it.")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            EmptyView()
        }
        .navigationTitle("About eGuard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
