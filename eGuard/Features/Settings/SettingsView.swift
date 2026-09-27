import SwiftUI

/// 16 Settings: the menu of app sections plus reset.
struct SettingsView: View {
    let isRoot: Bool

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var isConfirmingReset = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Version \(short)"
    }

    var body: some View {
        Group {
            if isRoot {
                TabScreen {
                    TabScreenHeader(title: "Settings")
                } content: {
                    content
                }
            } else {
                EGuardScreen {
                    content
                } actions: {
                    EmptyView()
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .confirmationDialog(
            "Remove all protections?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Remove and Reset", role: .destructive) {
                model.resetEverything()
                router.popToRoot()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downtime, limits, and restrictions applied by eGuard will be removed immediately, and the account on this device is deleted.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let account = model.account {
            Button {
                router.push(.account)
            } label: {
                EGuardCard {
                    HStack(spacing: EGuardSpacing.sm) {
                        AvatarView(name: account.fullName, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.fullName)
                                .font(EGuardTypography.headline)
                                .foregroundStyle(EGuardColors.textPrimary)
                            Text(account.email)
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(EGuardColors.neutral)
                    }
                }
            }
            .buttonStyle(.plain)
        }

        if !model.authorizationStatus.isAuthorized {
            EGuardCard {
                Label("eGuard needs Family Controls authorization", systemImage: "hand.raised.fill")
                    .font(EGuardTypography.headline)
                Text("Automatic protections can only be applied and verified after you grant it.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
                Button("Grant Authorization") { router.push(.authorization) }
                    .buttonStyle(.eGuardSecondary)
                    .accessibilityIdentifier("settings.authorize")
            }
        }

        EGuardCard {
            EGuardNavRow(title: "Family", subtitle: "Manage children and devices", symbolName: "person.2.fill") {
                router.show(.children)
            }
            Divider()
            EGuardNavRow(title: "Protection & Controls", subtitle: "Screen time, apps, content", symbolName: "shield.lefthalf.filled", tint: EGuardColors.tileTeal) {
                router.push(.manageProtection)
            }
            Divider()
            EGuardNavRow(title: "Notifications", subtitle: "Alert preferences", symbolName: "bell.fill", tint: EGuardColors.tileOrange) {
                router.push(.notifications)
            }
            Divider()
            EGuardNavRow(title: "Privacy", subtitle: "Your data and security", symbolName: "lock.fill", tint: EGuardColors.tilePurple) {
                router.push(.privacy)
            }
            Divider()
            EGuardNavRow(title: "Account", subtitle: "Profile and login", symbolName: "person.crop.circle.fill", tint: EGuardColors.primary) {
                router.push(.account)
            }
            Divider()
            EGuardNavRow(title: "Subscription", subtitle: "Manage your plan", symbolName: "crown.fill", tint: EGuardColors.tileYellow) {
                router.push(.subscription)
            }
            Divider()
            EGuardNavRow(title: "Help & Support", subtitle: "Get assistance", symbolName: "questionmark.circle.fill", tint: EGuardColors.tileTeal) {
                router.push(.helpSupport)
            }
            Divider()
            EGuardNavRow(title: "About eGuard", subtitle: version, symbolName: "info.circle.fill", tint: EGuardColors.tileGray) {
                router.push(.about)
            }
        }

        Button("Remove All Protections and Reset", role: .destructive) {
            isConfirmingReset = true
        }
        .font(EGuardTypography.label)
        .foregroundStyle(EGuardColors.danger)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(EGuardColors.surface, in: EGuardShapes.button)
        .accessibilityIdentifier("settings.reset")
    }
}

#Preview {
    NavigationStack {
        SettingsView(isRoot: true)
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
