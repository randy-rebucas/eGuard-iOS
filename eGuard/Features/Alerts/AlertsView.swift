import SwiftUI

/// 15 Alerts, grouped by day with All / Protection / Apps filters.
struct AlertsView: View {
    let isRoot: Bool

    private enum Filter: Hashable {
        case all
        case category(AlertCategory)

        var title: String {
            switch self {
            case .all: "All"
            case .category(let category): category.title
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var filter: Filter = .all

    private var filters: [Filter] {
        [.all, .category(.protection), .category(.apps), .category(.location)]
    }

    private var filtered: [ProtectionAlert] {
        switch filter {
        case .all: model.alerts
        case .category(let category): model.alerts.filter { $0.category == category }
        }
    }

    /// Alerts grouped by calendar day, newest first.
    private var groups: [(title: String, alerts: [ProtectionAlert])] {
        var order: [String] = []
        var buckets: [String: [ProtectionAlert]] = [:]
        for alert in filtered {
            let title = alert.date.dayGroupTitle()
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(alert)
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
            }
        }
        .onAppear { model.markAllAlertsRead() }
    }

    private var menu: some View {
        Menu {
            Button("Clear all alerts", systemImage: "trash", role: .destructive) { model.clearAlerts() }
                .disabled(model.alerts.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Alert options")
    }

    @ViewBuilder
    private var content: some View {
        PillSegmentedControl(options: filters, selection: $filter) { $0.title }

        if groups.isEmpty {
            EmptyStateView(
                symbolName: "bell.slash",
                title: "No alerts",
                message: "eGuard adds an alert when a protection stops working, needs apps chosen, or hasn't been configured."
            )
        } else {
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: group.title)
                    EGuardCard {
                        ForEach(group.alerts) { alert in
                            AlertRow(alert: alert, action: alert.feature == nil ? nil : {
                                if let feature = alert.feature { router.push(.featureDetail(feature)) }
                            })
                            if alert.id != group.alerts.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AlertsView(isRoot: true)
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
