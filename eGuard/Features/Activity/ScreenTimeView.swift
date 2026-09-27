import DeviceActivity
import SwiftUI

/// 12 Screen Time. Apple renders the usage ring, chart, and app list inside the sandboxed
/// report extension, so no usage data ever reaches eGuard itself.
struct ScreenTimeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var range: ScreenTimeRange = .today

    private var canShowReports: Bool {
        model.authorizationStatus.isAuthorized && !model.environment.isSimulator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
                PillSegmentedControl(options: ScreenTimeRange.allCases, selection: $range) { $0.title }

                if canShowReports {
                    DeviceActivityReport(.eGuardScreenTime, filter: filter)
                        .frame(minHeight: 520)
                        .id(range)
                } else {
                    unavailableCard
                }

                allowancesCard
            }
            .padding(.horizontal, EGuardSpacing.md)
            .padding(.vertical, EGuardSpacing.md)
        }
        .background(EGuardColors.background)
        .navigationTitle("Screen Time")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filter: DeviceActivityFilter {
        DeviceActivityFilter(segment: range.segment(), devices: nil, applications: [], categories: [], webDomains: [])
    }

    private var unavailableCard: some View {
        EGuardCard {
            RingGauge(progress: 0, tint: EGuardColors.primary, lineWidth: 14, size: 160) {
                VStack(spacing: 2) {
                    Text("—")
                        .font(EGuardTypography.metric)
                    Text(totalAllowanceText.map { "of \($0)" } ?? "No limit")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            Text(model.authorizationStatus.isAuthorized
                 ? "Screen time reports are rendered by Apple on a real device. The simulator has no usage data."
                 : "Grant Family Controls authorization so Apple can show screen time for this device.")
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if !model.authorizationStatus.isAuthorized {
                Button("Grant Authorization") { router.push(.authorization) }
                    .buttonStyle(.eGuardSecondary)
            }
        }
    }

    private var allowancesCard: some View {
        EGuardCard {
            SectionHeader(title: "Daily allowances")
            EGuardNavRow(
                title: "Gaming",
                subtitle: model.settings.gamingLimitMinutes.map(ProtectionSettings.formatDailyAllowance) ?? "No limit",
                symbolName: ProtectionFeature.gaming.symbolName,
                tint: EGuardTheme.tint(for: .gaming)
            ) { router.push(.featureDetail(.gaming)) }
            Divider()
            EGuardNavRow(
                title: "Social apps",
                subtitle: model.settings.socialAppsLimitMinutes.map(ProtectionSettings.formatDailyAllowance) ?? "No limit",
                symbolName: ProtectionFeature.socialApps.symbolName,
                tint: EGuardTheme.tint(for: .socialApps)
            ) { router.push(.featureDetail(.socialApps)) }
            Divider()
            EGuardNavRow(
                title: "Bedtime",
                subtitle: model.settings.downtime?.formatted ?? "Off",
                symbolName: ProtectionFeature.downtime.symbolName,
                tint: EGuardTheme.tint(for: .downtime)
            ) { router.push(.featureDetail(.downtime)) }
        }
    }

    private var totalAllowanceText: String? {
        let total = (model.settings.gamingLimitMinutes ?? 0) + (model.settings.socialAppsLimitMinutes ?? 0)
        guard total > 0 else { return nil }
        return ProtectionSettings.formatDailyAllowance(total).replacingOccurrences(of: " / day", with: "")
    }
}

#Preview {
    NavigationStack {
        ScreenTimeView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
