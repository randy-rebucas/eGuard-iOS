import DeviceActivity
import FamilyControls
import ManagedSettings
import Observation
import SwiftUI

extension DeviceActivityReport.Context {
    /// Rendered by the eGuardActivityReport extension. The string must match the extension's copy.
    static let eGuardToday = Self("eGuard Today")
}

/// Derives dashboard values from the shared app state.
@Observable
final class DashboardViewModel {
    func greeting(now: Date = .now) -> String {
        "\(now.greeting()), Parent"
    }

    func protectionTitle(model: AppModel) -> String {
        if let child = model.childProfile {
            return "\(child.trimmedName)'s Protection"
        }
        return "Protection"
    }

    func appsNeedingReview(model: AppModel) -> Int {
        model.lastHealthReport?.attentionChecks.count ?? 0
    }

    /// Reports only exist for the current user on a real, authorized device.
    func canShowActivityReports(model: AppModel) -> Bool {
        model.authorizationStatus.isAuthorized && !model.environment.isSimulator
    }

    func todayFilter(applications: Set<ApplicationToken> = [], categories: Set<ActivityCategoryToken> = []) -> DeviceActivityFilter {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .day, for: .now)
            ?? DateInterval(start: calendar.startOfDay(for: .now), duration: 24 * 60 * 60)
        return DeviceActivityFilter(
            segment: .daily(during: interval),
            devices: nil,
            applications: applications,
            categories: categories,
            webDomains: []
        )
    }
}

/// The parent's home screen after setup.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = DashboardViewModel()

    private var report: ConfigurationHealthReport? { model.lastHealthReport }

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: viewModel.greeting())

            if !model.isOnline {
                OfflineBanner(lastVerified: report?.generatedAt)
            }

            if let report, report.hasDrift {
                driftCard
            }

            protectionCard
            healthCard
            todayCard
            statusCard
        } actions: {
            Button("Manage Protection") { router.push(.manageProtection) }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("dashboard.manageProtection")
        }
        .navigationTitle("eGuard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("dashboard.settings")
            }
        }
        .onAppear { model.performHealthCheck() }
    }

    // MARK: Cards

    private var driftCard: some View {
        EGuardCard {
            Label("Protection Needs Attention", systemImage: "exclamationmark.triangle.fill")
                .font(EGuardTypography.headline)
                .foregroundStyle(EGuardColors.warning)
            Text("One or more settings may need to be reviewed.")
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
            Button("Review Settings") { router.push(.healthReview) }
                .buttonStyle(.eGuardSecondary)
                .accessibilityIdentifier("dashboard.reviewSettings")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.drift")
    }

    private var protectionCard: some View {
        EGuardCard {
            Text(viewModel.protectionTitle(model: model))
                .font(EGuardTypography.overline)
                .foregroundStyle(EGuardColors.textSecondary)
            StatusIndicator(
                text: model.settings.profile.title,
                color: EGuardTheme.color(for: report?.protectionState ?? .notConfigured)
            )
            .font(EGuardTypography.title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.protection")
    }

    private var healthCard: some View {
        EGuardCard {
            Text("Configuration Health")
                .font(EGuardTypography.overline)
                .foregroundStyle(EGuardColors.textSecondary)
            Text(report?.scoreText ?? "—")
                .font(EGuardTypography.metric)
                .foregroundStyle(EGuardTheme.color(for: report?.protectionState ?? .notConfigured))
                .accessibilityIdentifier("dashboard.healthScore")
            if let report {
                EGuardValueRow(label: "Last verified", value: report.generatedAt.verifiedDescription())
            }
            Button("View Health Check") { router.push(.healthReview) }
                .buttonStyle(.eGuardSecondary)
                .accessibilityIdentifier("dashboard.viewHealth")
        }
    }

    private var todayCard: some View {
        EGuardCard {
            Text("Today's Protection")
                .font(EGuardTypography.overline)
                .foregroundStyle(EGuardColors.textSecondary)

            if viewModel.canShowActivityReports(model: model) {
                activityRow(label: "Screen Time", limit: nil, filter: viewModel.todayFilter())
                if let minutes = model.settings.gamingLimitMinutes,
                   let selection = ActivitySelectionCodec.selection(from: model.selections.gaming) {
                    Divider()
                    activityRow(
                        label: "Gaming",
                        limit: ProtectionSettings.formatDailyAllowance(minutes),
                        filter: viewModel.todayFilter(applications: selection.applicationTokens, categories: selection.categoryTokens)
                    )
                }
                if let minutes = model.settings.socialAppsLimitMinutes,
                   let selection = ActivitySelectionCodec.selection(from: model.selections.socialApps) {
                    Divider()
                    activityRow(
                        label: "Social Apps",
                        limit: ProtectionSettings.formatDailyAllowance(minutes),
                        filter: viewModel.todayFilter(applications: selection.applicationTokens, categories: selection.categoryTokens)
                    )
                }
            } else {
                Text(model.authorizationStatus.isAuthorized
                     ? "Activity summaries are available on a real device."
                     : "Grant Family Controls authorization to see today's activity summary.")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
            }

            Divider()
            EGuardValueRow(label: "Downtime", value: model.settings.downtime?.start.formatted ?? "Off")
        }
    }

    private func activityRow(label: String, limit: String?, filter: DeviceActivityFilter) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(EGuardTypography.body)
                .foregroundStyle(EGuardColors.textSecondary)
            Spacer()
            // Apple renders the duration inside the sandboxed report extension.
            DeviceActivityReport(.eGuardToday, filter: filter)
                .frame(height: 24)
            if let limit {
                Text("/ \(limit.replacingOccurrences(of: " / day", with: ""))")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }

    private var statusCard: some View {
        EGuardCard {
            EGuardValueRow(label: "Protection", value: (report?.protectionState ?? .notConfigured).title)
            Divider()
            let count = viewModel.appsNeedingReview(model: model)
            EGuardValueRow(label: "Settings", value: count == 0 ? "All reviewed" : (count == 1 ? "1 needs review" : "\(count) need review"))
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .environment(AppModel.make(arguments: ["-uiTesting", "-setupComplete"]))
    .environment(AppRouter())
}
