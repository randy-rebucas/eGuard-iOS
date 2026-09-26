import SwiftUI

/// Hosts the single NavigationStack. Onboarding starts at Welcome; a finished setup starts at the dashboard.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            Group {
                if model.isSetupComplete {
                    DashboardView()
                } else {
                    WelcomeView()
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        .environment(router)
        .tint(EGuardColors.primary)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Authorization and settings can change outside the app, so verify on every return.
            model.refreshAuthorization()
            if model.isSetupComplete {
                model.performHealthCheck()
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .childDevice: ChildDeviceView()
        case .protectionProfile: ProtectionProfileView()
        case .recommendedSetup: RecommendedSetupView()
        case .configureSettings: ConfigureSettingsView(isOnboarding: true)
        case .healthCheck: HealthCheckView(isOnboarding: true)
        case .complete: CompleteView()
        case .manageProtection: ConfigureSettingsView(isOnboarding: false)
        case .healthReview: HealthCheckView(isOnboarding: false)
        case .settings: SettingsView()
        case .authorization: AuthorizationView()
        case .featureDetail(let feature): FeatureConfigurationView(feature: feature)
        }
    }
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel.mock())
}

#Preview("Dashboard") {
    RootView()
        .environment(AppModel.make(arguments: ["-uiTesting", "-setupComplete"]))
}
