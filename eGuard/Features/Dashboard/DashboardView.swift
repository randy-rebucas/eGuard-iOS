import DeviceActivity
import FamilyControls
import ManagedSettings
import Observation
import SwiftUI

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

    /// One line describing how the family is doing, based on the verified report.
    func statusLine(model: AppModel) -> String {
        guard let report = model.lastHealthReport, report.evaluatedCount > 0 else {
            return "Finish setting up protections to see your family's status."
        }
        switch report.protectionState {
        case .active: return "Your family's digital safety looks good today."
        case .needsAttention: return report.hasDrift
            ? "A protection stopped working and needs your attention."
            : "A few settings still need to be configured."
        case .notConfigured: return "No protections are active yet."
        }
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

/// 10 Dashboard: the parent's home tab after setup.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = DashboardViewModel()

    private var report: ConfigurationHealthReport? { model.lastHealthReport }

    var body: some View {
        TabScreen {
            header
        } content: {
            if !model.isOnline {
                OfflineBanner(lastVerified: report?.generatedAt)
            }

            if let report, report.hasDrift {
                driftCard
            }

            familyProtectionCard
            childrenSection
            todayCard
            alertsSection
        }
        .background(EGuardColors.heroGradient.ignoresSafeArea())
        .onAppear { model.performHealthCheck() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            HStack(alignment: .top) {
                EGuardWordmark(markSize: 30, showsTagline: true)
                Spacer()
                Button {
                    router.push(.settings)
                } label: {
                    AvatarView(name: model.account?.fullName ?? "Parent", size: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("dashboard.settings")
            }
            Text(model.account?.firstName ?? viewModel.greeting())
                .font(EGuardTypography.display)
                .foregroundStyle(EGuardColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.statusLine(model: model))
                .font(EGuardTypography.body)
                .foregroundStyle(EGuardColors.textSecondary)
        }
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

    private var familyProtectionCard: some View {
        let tint = EGuardTheme.color(for: report?.protectionState ?? .notConfigured)
        return EGuardCard {
            Button {
                router.push(.healthReview)
            } label: {
                HStack(spacing: EGuardSpacing.md) {
                    IconTile(symbolName: "shield.fill", tint: EGuardColors.primary, size: 56, filled: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Family Protection")
                            .font(EGuardTypography.label)
                            .foregroundStyle(EGuardColors.textSecondary)
                        Text(report?.scoreText ?? "—")
                            .font(EGuardTypography.metric)
                            .foregroundStyle(EGuardColors.textPrimary)
                            .accessibilityIdentifier("dashboard.healthScore")
                        Text(EGuardTheme.grade(passed: report?.passedCount ?? 0, total: report?.evaluatedCount ?? 0))
                            .font(EGuardTypography.label)
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(EGuardColors.neutral)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.viewHealth")

            HStack(spacing: EGuardSpacing.xs) {
                Button("Manage Protection") { router.push(.manageProtection) }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("dashboard.manageProtection")
                Button("Health Check") { router.push(.healthReview) }
                    .buttonStyle(.eGuardSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.protection")
    }

    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Your Children", actionTitle: "View All") {
                router.show(.children)
            }
            HStack(alignment: .top, spacing: EGuardSpacing.lg) {
                if let child = model.childProfile {
                    Button {
                        router.push(.childProfile)
                    } label: {
                        VStack(spacing: EGuardSpacing.xs) {
                            AvatarView(name: child.trimmedName, imageData: child.photoData, size: 64)
                            Text(child.trimmedName)
                                .font(EGuardTypography.label)
                                .foregroundStyle(EGuardColors.textPrimary)
                            childStatusPill
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.child")
                }
                Button {
                    router.push(.childDevice)
                } label: {
                    VStack(spacing: EGuardSpacing.xs) {
                        Image(systemName: model.childProfile == nil ? "plus" : "pencil")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(EGuardColors.primary)
                            .frame(width: 64, height: 64)
                            .background(EGuardColors.primarySoft, in: Circle())
                        Text(model.childProfile == nil ? "Add child" : "Edit")
                            .font(EGuardTypography.label)
                            .foregroundStyle(EGuardColors.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    private var childStatusPill: some View {
        let state = report?.protectionState ?? .notConfigured
        return StatusPill(
            text: state == .active ? "Protected" : (state == .needsAttention ? "Attention" : "Not set up"),
            tint: EGuardTheme.color(for: state)
        )
    }

    private var todayCard: some View {
        EGuardCard {
            SectionHeader(title: "Today's Protection", actionTitle: "Details") {
                router.push(.screenTime)
            }

            if viewModel.canShowActivityReports(model: model) {
                activityRow(label: "Screen Time", symbol: "clock.fill", tint: EGuardColors.primary, limit: nil, filter: viewModel.todayFilter())
                if let minutes = model.settings.gamingLimitMinutes,
                   let selection = ActivitySelectionCodec.selection(from: model.selections.gaming) {
                    Divider()
                    activityRow(
                        label: "Gaming",
                        symbol: ProtectionFeature.gaming.symbolName,
                        tint: EGuardTheme.tint(for: .gaming),
                        limit: ProtectionSettings.formatDailyAllowance(minutes),
                        filter: viewModel.todayFilter(applications: selection.applicationTokens, categories: selection.categoryTokens)
                    )
                }
                if let minutes = model.settings.socialAppsLimitMinutes,
                   let selection = ActivitySelectionCodec.selection(from: model.selections.socialApps) {
                    Divider()
                    activityRow(
                        label: "Social Apps",
                        symbol: ProtectionFeature.socialApps.symbolName,
                        tint: EGuardTheme.tint(for: .socialApps),
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
            EGuardNavRow(
                title: "Bedtime",
                subtitle: model.settings.downtime?.formatted ?? "Off",
                symbolName: ProtectionFeature.downtime.symbolName,
                tint: EGuardTheme.tint(for: .downtime)
            ) {
                router.push(.featureDetail(.downtime))
            }
        }
    }

    private func activityRow(label: String, symbol: String, tint: Color, limit: String?, filter: DeviceActivityFilter) -> some View {
        HStack(spacing: EGuardSpacing.sm) {
            IconTile(symbolName: symbol, tint: tint)
            Text(label)
                .font(EGuardTypography.label)
                .foregroundStyle(EGuardColors.textPrimary)
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
        .padding(.vertical, EGuardSpacing.xxs)
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Recent Alerts", actionTitle: "View All") {
                router.show(.alerts)
            }
            EGuardCard {
                if model.alerts.isEmpty {
                    Text("No alerts yet. eGuard will tell you when a protection needs attention.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                } else {
                    ForEach(Array(model.alerts.prefix(3))) { alert in
                        AlertRow(alert: alert) {
                            if let feature = alert.feature {
                                router.push(.featureDetail(feature))
                            } else {
                                router.show(.alerts)
                            }
                        }
                        if alert.id != model.alerts.prefix(3).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

/// One alert line: tinted icon, title, detail, and relative time.
struct AlertRow: View {
    let alert: ProtectionAlert
    var action: (() -> Void)? = nil

    var body: some View {
        EGuardNavRow(
            title: alert.title,
            subtitle: "\(alert.detail) · \(alert.date.relativeDescription())",
            symbolName: alert.symbolName,
            tint: tint,
            showsChevron: action != nil,
            action: action
        ) {
            if !alert.isRead {
                Circle()
                    .fill(EGuardColors.primary)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
    }

    private var tint: Color {
        if let feature = alert.feature { return EGuardTheme.tint(for: feature) }
        switch alert.category {
        case .protection: return EGuardColors.primary
        case .apps: return EGuardColors.tilePurple
        case .location: return EGuardColors.success
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
