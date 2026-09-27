import SwiftUI

/// Children tab. eGuard protects the child who uses this device, so the list holds one profile.
struct ChildrenView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var state: ProtectionState { model.lastHealthReport?.protectionState ?? .notConfigured }

    var body: some View {
        TabScreen {
            TabScreenHeader(title: "Children") {
                EmptyView()
            } trailing: {
                Button {
                    router.push(.childDevice)
                } label: {
                    Image(systemName: model.childProfile == nil ? "plus" : "pencil")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(model.childProfile == nil ? "Add child" : "Edit child")
            }
        } content: {
            if let child = model.childProfile {
                Button {
                    router.push(.childProfile)
                } label: {
                    EGuardCard {
                        HStack(spacing: EGuardSpacing.md) {
                            AvatarView(name: child.trimmedName, imageData: child.photoData, size: 64)
                            VStack(alignment: .leading, spacing: EGuardSpacing.xxs) {
                                Text(child.trimmedName)
                                    .font(EGuardTypography.title3)
                                    .foregroundStyle(EGuardColors.textPrimary)
                                Text("\(child.ageDescription) · \(child.deviceName)")
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                                StatusPill(
                                    text: state == .active ? "Protected" : (state == .needsAttention ? "Attention" : "Not set up"),
                                    tint: EGuardTheme.color(for: state)
                                )
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(EGuardColors.neutral)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("children.child")

                EGuardCard {
                    SectionHeader(title: "Quick actions")
                    EGuardNavRow(title: "Screen Time", subtitle: "Usage and daily allowances", symbolName: "clock.fill") {
                        router.push(.screenTime)
                    }
                    Divider()
                    EGuardNavRow(title: "App Management", subtitle: "Managed and blocked apps", symbolName: "square.grid.2x2.fill", tint: EGuardColors.tilePurple) {
                        router.push(.appsManagement)
                    }
                    Divider()
                    EGuardNavRow(title: "Location", subtitle: model.preferences.isLocationSharingEnabled ? "Sharing enabled" : "Sharing off", symbolName: "location.fill", tint: EGuardColors.success) {
                        router.push(.location)
                    }
                }
            } else {
                EmptyStateView(
                    symbolName: "person.crop.circle.badge.plus",
                    title: "No child added yet",
                    message: "Add the child who uses this device to start protecting them."
                )
                Button("Add Child") { router.push(.childDevice) }
                    .buttonStyle(.eGuardPrimary)
            }

            EGuardCard {
                Label("Apple's Screen Time controls apply to the device eGuard is installed on. Install eGuard on each child's device to protect more children.", systemImage: "info.circle.fill")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChildrenView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
