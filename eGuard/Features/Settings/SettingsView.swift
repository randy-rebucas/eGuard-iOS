import SwiftUI

/// 16 Settings: the menu of app sections, from `/me` plus links to each server-backed screen.
struct SettingsView: View {
    let isRoot: Bool

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var isConfirmingSignOut = false

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
        .confirmationDialog("Sign out of eGuard?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await model.signOut()
                    router.popToRoot()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Protections stay active on your children's devices. Sign back in to manage them.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let user = model.user {
            Button {
                router.push(.account)
            } label: {
                EGuardCard {
                    HStack(spacing: EGuardSpacing.sm) {
                        AvatarView(name: user.name, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(EGuardTypography.headline)
                                .foregroundStyle(EGuardColors.textPrimary)
                            Text("\(user.email) · \(user.role.title)")
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

        VerifyEmailBanner()

        EGuardCard {
            EGuardNavRow(title: "Family", subtitle: model.user.map { "\($0.family.name) · manage parents and children" } ?? "Manage children and devices", symbolName: "person.2.fill") {
                router.push(.family)
            }
            Divider()
            EGuardNavRow(title: "Protection & Controls", subtitle: "Screen time, apps, content", symbolName: "shield.lefthalf.filled", tint: EGuardColors.tileTeal) {
                if let first = model.children.first, model.children.count == 1 {
                    router.push(.protections(childId: first.id))
                } else {
                    router.show(.children)
                }
            }
            Divider()
            EGuardNavRow(title: "Notifications", subtitle: "Alert preferences", symbolName: "bell.fill", tint: EGuardColors.tileOrange) {
                router.push(.notifications)
            }
            Divider()
            EGuardNavRow(title: "Privacy", subtitle: "Location history and analytics", symbolName: "lock.fill", tint: EGuardColors.tilePurple) {
                router.push(.privacy)
            }
            Divider()
            EGuardNavRow(title: "Account", subtitle: "Profile, password, sessions", symbolName: "person.crop.circle.fill", tint: EGuardColors.primary) {
                router.push(.account)
            }
            Divider()
            EGuardNavRow(title: "Your plan", subtitle: "View your plan and usage", symbolName: "rosette", tint: EGuardColors.tileYellow) {
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

        Button("Sign Out") { isConfirmingSignOut = true }
            .font(EGuardTypography.label)
            .foregroundStyle(EGuardColors.danger)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(EGuardColors.surface, in: EGuardShapes.button)
            .accessibilityIdentifier("settings.signOut")
    }
}

#Preview {
    NavigationStack {
        SettingsView(isRoot: true)
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
