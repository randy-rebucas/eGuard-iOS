import SwiftUI

/// 10 Dashboard: one `GET /dashboard` for the whole Home tab.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var dashboard: Dashboard? { model.dashboard }

    var body: some View {
        TabScreen {
            header
        } content: {
            if !model.isOnline {
                OfflineBanner(lastVerified: nil)
            }
            VerifyEmailBanner()

            if let error = model.refreshError {
                ErrorCard(message: error) { Task { await model.refreshDashboard() } }
            }

            if let dashboard {
                familyProtectionCard(dashboard)
                childrenSection(dashboard)
                alertsSection(dashboard)
            } else {
                LoadingCard()
            }
        }
        .background(EGuardColors.heroGradient.ignoresSafeArea())
        .refreshable { await model.refreshDashboard() }
        .task { await model.refreshDashboard() }
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
                    AvatarView(name: model.user?.name ?? "Parent", size: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("dashboard.settings")
            }
            Text(model.user?.firstName ?? dashboard?.greeting ?? "Welcome")
                .font(EGuardTypography.display)
                .foregroundStyle(EGuardColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(dashboard?.summary ?? "Loading your family's status…")
                .font(EGuardTypography.body)
                .foregroundStyle(EGuardColors.textSecondary)
        }
    }

    // MARK: Cards

    private func familyProtectionCard(_ dashboard: Dashboard) -> some View {
        let health = dashboard.health
        let tint: Color = health.score >= health.total ? EGuardColors.success : (health.score >= 5 ? EGuardColors.tileYellow : EGuardColors.danger)
        return EGuardCard {
            Button {
                router.push(.healthCheck(childId: nil, isOnboarding: false))
            } label: {
                HStack(spacing: EGuardSpacing.md) {
                    IconTile(symbolName: "shield.fill", tint: EGuardColors.primary, size: 56, filled: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Family Protection")
                            .font(EGuardTypography.label)
                            .foregroundStyle(EGuardColors.textSecondary)
                        Text(health.text)
                            .font(EGuardTypography.metric)
                            .foregroundStyle(EGuardColors.textPrimary)
                            .accessibilityIdentifier("dashboard.healthScore")
                        Text(health.grade)
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
                Button("Manage Protection") {
                    if let first = dashboard.children.first {
                        router.push(dashboard.children.count == 1 ? .protections(childId: first.id) : .childProfile(childId: first.id))
                    }
                }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("dashboard.manageProtection")
                Button("Health Check") { router.push(.healthCheck(childId: nil, isOnboarding: false)) }
                    .buttonStyle(.eGuardSecondary)
            }
            EGuardValueRow(label: "Devices", value: "\(dashboard.deviceCount)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.protection")
    }

    private func childrenSection(_ dashboard: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Your Children", actionTitle: "View All") {
                router.show(.children)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: EGuardSpacing.lg) {
                    ForEach(dashboard.children) { child in
                        Button {
                            router.push(.childProfile(childId: child.id))
                        } label: {
                            VStack(spacing: EGuardSpacing.xs) {
                                ChildAvatar(child: child, size: 64)
                                Text(child.name)
                                    .font(EGuardTypography.label)
                                    .foregroundStyle(EGuardColors.textPrimary)
                                StatusPill(text: child.status.title, tint: statusTint(child.status))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dashboard.child.\(child.id)")
                    }
                    Button {
                        router.push(.addChild)
                    } label: {
                        VStack(spacing: EGuardSpacing.xs) {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(EGuardColors.primary)
                                .frame(width: 64, height: 64)
                                .background(EGuardColors.primarySoft, in: Circle())
                            Text("Add child")
                                .font(EGuardTypography.label)
                                .foregroundStyle(EGuardColors.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.addChild")
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func alertsSection(_ dashboard: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Recent Alerts", actionTitle: "View All") {
                router.show(.alerts)
            }
            EGuardCard {
                if dashboard.recentAlerts.isEmpty {
                    Text("No alerts. eGuard will tell you when a protection needs attention.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                } else {
                    ForEach(dashboard.recentAlerts) { alert in
                        APIAlertRow(alert: alert) {
                            Task { _ = try? await model.api.markAlertRead(id: alert.id) }
                            if let action = alert.action { router.open(action) } else { router.show(.alerts) }
                        }
                        if alert.id != dashboard.recentAlerts.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

func statusTint(_ status: ChildStatus) -> Color {
    switch status {
    case .protected: EGuardColors.success
    case .attention: EGuardColors.warning
    case .notconfigured: EGuardColors.neutral
    }
}

/// One server alert: icon tile by category, title, subject, and time.
struct APIAlertRow: View {
    let alert: APIAlert
    var action: (() -> Void)? = nil

    var body: some View {
        EGuardNavRow(
            title: alert.title,
            subtitle: [alert.subject, alert.timeLabel ?? alert.createdAt.relativeDescription()].compactMap { $0 }.joined(separator: " · "),
            symbolName: LucideIcon.symbol(for: alert.icon, fallback: fallbackSymbol),
            tint: tint,
            showsChevron: action != nil,
            action: action
        ) {
            if !alert.read {
                Circle()
                    .fill(EGuardColors.primary)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
    }

    private var fallbackSymbol: String {
        switch alert.category {
        case .protection: "shield.lefthalf.filled"
        case .apps: "square.grid.2x2.fill"
        case .location: "location.fill"
        case .devices: "iphone"
        case .screenTime: "hourglass"
        case .system: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch alert.severity {
        case .critical, .actionRequired: return EGuardColors.danger
        case .attention: return EGuardColors.warning
        case .info:
            switch alert.category {
            case .apps: return EGuardColors.tilePurple
            case .location: return EGuardColors.success
            default: return EGuardColors.primary
            }
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
