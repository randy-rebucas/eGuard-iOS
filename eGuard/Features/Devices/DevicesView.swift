import SwiftUI

/// Devices tab: the child's device eGuard runs on, with its protection state and shortcuts.
struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var report: ConfigurationHealthReport? { model.lastHealthReport }
    private var state: ProtectionState { report?.protectionState ?? .notConfigured }

    var body: some View {
        TabScreen {
            TabScreenHeader(title: "Devices")
        } content: {
            deviceCard

            EGuardCard {
                SectionHeader(title: "On this device")
                EGuardNavRow(title: "Protection & Controls", subtitle: "\(model.progress.completedCount(of: model.settings.enabledFeatures)) of \(model.settings.enabledFeatures.count) configured", symbolName: "shield.lefthalf.filled") {
                    router.push(.manageProtection)
                }
                Divider()
                EGuardNavRow(title: "Configuration Health", subtitle: report?.summary ?? "Not checked yet", symbolName: "heart.text.square.fill", tint: EGuardTheme.color(for: state)) {
                    router.push(.healthReview)
                }
                Divider()
                EGuardNavRow(title: "Screen Time", subtitle: "Usage and allowances", symbolName: "clock.fill", tint: EGuardColors.tileOrange) {
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

            EGuardCard {
                SectionHeader(title: "Apple parental controls")
                EGuardNavRow(
                    title: "Family Controls",
                    subtitle: model.authorizationStatus.title,
                    symbolName: "hand.raised.fill",
                    tint: model.authorizationStatus.isAuthorized ? EGuardColors.success : EGuardColors.warning
                ) {
                    router.push(.authorization)
                }
                if model.environment.isSimulator {
                    Divider()
                    Label("The simulator can't enforce Screen Time protections.", systemImage: "exclamationmark.triangle.fill")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.warning)
                }
            }
        }
    }

    private var deviceCard: some View {
        EGuardCard {
            HStack(spacing: EGuardSpacing.md) {
                IconTile(symbolName: model.childProfile?.device.symbolName ?? "iphone", tint: EGuardColors.primary, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.childProfile?.deviceName ?? "This device")
                        .font(EGuardTypography.title3)
                    Text("\(model.childProfile?.device.operatingSystemName ?? "iOS") · \(model.childProfile.map { "\($0.trimmedName), \($0.ageDescription)" } ?? "No child added")")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                    StatusPill(
                        text: state == .active ? "Protected" : (state == .needsAttention ? "Attention" : "Not set up"),
                        tint: EGuardTheme.color(for: state)
                    )
                }
                Spacer()
            }
            if let report {
                Divider()
                EGuardValueRow(label: "Health", value: "\(report.scoreText) · \(EGuardTheme.grade(passed: report.passedCount, total: report.evaluatedCount))")
                EGuardValueRow(label: "Last verified", value: report.generatedAt.verifiedDescription())
            }
        }
    }
}

#Preview {
    NavigationStack {
        DevicesView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
