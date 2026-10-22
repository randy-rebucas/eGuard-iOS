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
    /// A failed action (load more, mark read, dismiss): shown above the list, which stays.
    @State private var actionError: String?
    @State private var isLoadingMore = false

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
                    do {
                        model.setUnreadAlerts(try await model.api.markAllAlertsRead())
                        actionError = nil
                    } catch {
                        actionError = error.localizedDescription
                    }
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

        InlineError(message: actionError)

        if isLoading {
            LoadingCard()
        } else if let error, alerts.isEmpty {
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
                Button(isLoadingMore ? "Loading…" : "Load more") { Task { await loadAlerts(reset: false) } }
                    .buttonStyle(.eGuardSecondary)
                    .disabled(isLoadingMore)
            }
        }
    }

    private func alertRow(_ alert: APIAlert) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
            APIAlertRow(alert: alert, action: alert.routableAction == nil ? nil : { open(alert) })
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
                // No button for an action type this build doesn't know; new ones are added over time.
                if let action = alert.routableAction, !alert.resolved {
                    Button(action.displayLabel) { open(alert) }
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.primary)
                }
                if alert.resolved {
                    StatusPill(text: "Resolved", tint: EGuardColors.success)
                }
                if alert.dismissible {
                    Button("Dismiss") {
                        Task {
                            do {
                                try await model.api.dismissAlert(id: alert.id)
                                actionError = nil
                            } catch {
                                // e.g. a critical alert that stays until it's resolved
                                actionError = error.localizedDescription
                            }
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
        if let action = alert.routableAction { router.open(action) }
    }

    private func loadAlerts(reset: Bool) async {
        if !reset {
            // A second tap while a page loads would append it twice
            guard !isLoadingMore else { return }
            isLoadingMore = true
        }
        defer { isLoadingMore = false }
        if reset { isLoading = alerts.isEmpty }
        do {
            let page = try await model.api.alerts(filter: filter, childId: nil, includeResolved: includeResolved, before: reset ? nil : nextBefore)
            if reset {
                alerts = page.alerts
            } else {
                let known = Set(alerts.map(\.id))
                alerts += page.alerts.filter { !known.contains($0.id) }
            }
            nextBefore = page.nextBefore
            model.setUnreadAlerts(page.unread)
            error = nil
        } catch {
            // Nothing shown yet: the error card with Retry. Otherwise keep the list and say what failed
            if reset && alerts.isEmpty { self.error = error.localizedDescription } else { actionError = error.localizedDescription }
        }
        isLoading = false
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AlertsView(isRoot: true)
    }
    .environment(AppModel.live())
    .environment(AppRouter())
}
#endif
