import SwiftUI

/// The tabbed main app: Home, Children, Devices, Alerts, Settings.
/// The tabs live inside the root NavigationStack, so pushed screens cover the tab bar.
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab(MainTab.home.title, systemImage: MainTab.home.symbolName, value: .home) {
                DashboardView()
            }
            Tab(MainTab.children.title, systemImage: MainTab.children.symbolName, value: .children) {
                ChildrenView()
            }
            Tab(MainTab.devices.title, systemImage: MainTab.devices.symbolName, value: .devices) {
                DevicesView()
            }
            Tab(MainTab.alerts.title, systemImage: MainTab.alerts.symbolName, value: .alerts) {
                AlertsView(isRoot: true)
            }
            .badge(model.unreadAlerts)
            Tab(MainTab.settings.title, systemImage: MainTab.settings.symbolName, value: .settings) {
                SettingsView(isRoot: true)
            }
        }
        .tint(EGuardColors.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.refreshUnreadCount() }
    }
}

#Preview {
    NavigationStack {
        MainTabView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
