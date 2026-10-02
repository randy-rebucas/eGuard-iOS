import SwiftUI

/// Version, tagline, publisher, and contact details.
struct AboutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

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
                EGuardValueRow(label: "Data storage", value: "Your family's eGuard account")
                Divider()
                EGuardValueRow(label: "Analytics or ads", value: "None")
            }

            EGuardCard {
                SectionHeader(title: "Publisher")
                EGuardValueRow(label: "Company", value: EGuardPublisher.name)
                Divider()
                Text(EGuardPublisher.address)
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
                Divider()
                EGuardNavRow(title: "Website", subtitle: EGuardPublisher.websiteLabel, symbolName: "globe", tint: EGuardColors.primary) {
                    openURL(EGuardPublisher.websiteURL)
                }
                Divider()
                EGuardNavRow(title: "Support & privacy", subtitle: model.supportEmail, symbolName: "envelope.fill", tint: EGuardColors.tileTeal) {
                    if let url = EGuardPublisher.mailURL(for: model.supportEmail) { openURL(url) }
                }
            }

            EGuardCard {
                SectionHeader(title: "Legal")
                EGuardNavRow(title: "Privacy Policy", subtitle: "How eGuard handles your family's data", symbolName: "doc.text.fill", tint: EGuardColors.tilePurple) {
                    openURL(EGuardPublisher.privacyPolicyURL)
                }
                .accessibilityIdentifier("about.privacyPolicy")
                Divider()
                EGuardNavRow(title: "Terms of Service", subtitle: EGuardPublisher.termsURL.host() ?? "", symbolName: "doc.plaintext.fill", tint: EGuardColors.tileGray) {
                    openURL(EGuardPublisher.termsURL)
                }
                Divider()
                EGuardNavRow(title: "Delete your account", subtitle: "In Settings › Account, or on eguard.family", symbolName: "trash.fill", tint: EGuardColors.danger) {
                    openURL(EGuardPublisher.deleteAccountURL)
                }
            }

            EGuardCard {
                Text("eGuard helps parents configure, manage, and verify their children's device protections with clear, honest status reporting. A setting is only shown as saved once the child's device has verified it. The same app runs on a child's device to apply those settings.")
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
    .environment(AppModel.preview())
}
