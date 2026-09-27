import SwiftUI

/// 15 Alerts, from `GET /alerts?filter=`, grouped by the server's day labels.
struct AlertsView: View {
    let isRoot: Bool

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var filter: AlertsFilter = .all
    @State private var includeResolved = false
    @State private var alerts: [APIAlert] = []
    @State private var nextBefore: Date?
    @State private var isLoading = true
    @State private var error: String?

    private var groups: [(DayGroup, [APIAlert])] {
        var order: [DayGroup] = []
        var buckets: [DayGroup: [APIAlert]] = [:]
        for alert in alerts {
            if buckets[alert.day] == nil { order.append(alert.day) }
            buckets[alert.day, default: []].append(alert)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        Group {
            if isRoot {
                TabScreen {
                    TabScreenHeader(title: "Alerts") {
                        EmptyView()
                    } trailing: {
                        menu
                    }
                } content: {
                    content
                }
            } else {
                EGuardScreen {
                    content
                } actions: {
                    EmptyView()
                }
                .navigationTitle("Alerts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
            }
        }
        .task(id: "\(filter.rawValue)-\(includeResolved)") { await loadAlerts(reset: true) }
        .refreshable { await loadAlerts(reset: true) }
    }

    private var menu: some View {
        Menu {
            Button("Mark all as read", systemImage: "envelope.open") {
                Task {
                    _ = try? await model.api.markAllAlertsRead()
                    model.setUnreadAlerts(0)
                    await loadAlerts(reset: true)
                }
            }
            Toggle("Show resolved", systemImage: "checkmark.circle", isOn: $includeResolved)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Alert options")
    }

    @ViewBuilder
    private var content: some View {
        PillSegmentedControl(options: AlertsFilter.allCases, selection: $filter) { $0.title }

        if isLoading {
            LoadingCard()
        } else if let error {
            ErrorCard(message: error) { Task { await loadAlerts(reset: true) } }
        } else if alerts.isEmpty {
            EmptyStateView(
                symbolName: "bell.slash",
                title: "No alerts",
                message: "eGuard adds an alert when a protection stops working, an app needs approval, or a device goes quiet."
            )
        } else {
            ForEach(groups, id: \.0.key) { day, dayAlerts in
                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: day.label)
                    EGuardCard {
                        ForEach(dayAlerts) { alert in
                            alertRow(alert)
                            if alert.id != dayAlerts.last?.id { Divider() }
                        }
                    }
                }
            }
            if nextBefore != nil {
                Button("Load more") { Task { await loadAlerts(reset: false) } }
                    .buttonStyle(.eGuardSecondary)
            }
        }
    }

    private func alertRow(_ alert: APIAlert) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
            APIAlertRow(alert: alert, action: alert.action == nil ? nil : { open(alert) })
            if !alert.body.isEmpty {
                Text(alert.body)
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
                    .padding(.leading, 48)
            }
            if let from = alert.fromValue, let to = alert.toValue {
                Text("\(from) → \(to)")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textPrimary)
                    .padding(.leading, 48)
            }
            HStack(spacing: EGuardSpacing.sm) {
                if let action = alert.action, !alert.resolved {
                    Button(action.label) { open(alert) }
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.primary)
                }
                if alert.resolved {
                    StatusPill(text: "Resolved", tint: EGuardColors.success)
                }
                if alert.dismissible {
                    Button("Dismiss") {
                        Task {
                            try? await model.api.dismissAlert(id: alert.id)
                            await loadAlerts(reset: true)
                        }
                    }
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            .padding(.leading, 48)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.row.\(alert.id)")
    }

    private func open(_ alert: APIAlert) {
        Task {
            if !alert.read, let unread = try? await model.api.markAlertRead(id: alert.id) {
                model.setUnreadAlerts(unread)
            }
        }
        if let action = alert.action { router.open(action) }
    }

    private func loadAlerts(reset: Bool) async {
        if reset { isLoading = alerts.isEmpty }
        do {
            let page = try await model.api.alerts(filter: filter, childId: nil, includeResolved: includeResolved, before: reset ? nil : nextBefore)
            alerts = reset ? page.alerts : alerts + page.alerts
            nextBefore = page.nextBefore
            model.setUnreadAlerts(page.unread)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        AlertsView(isRoot: true)
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
