import SwiftUI

/// Hosts the splash and the single NavigationStack.
/// A signed-in parent with a finished setup starts in the tabbed app; everyone else starts at Welcome.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            if isShowingSplash && !model.skipsSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                navigationStack
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: isShowingSplash)
        .task {
            guard !model.skipsSplash else {
                isShowingSplash = false
                return
            }
            try? await Task.sleep(for: .seconds(1.6))
            isShowingSplash = false
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Authorization and settings can change outside the app, so verify on every return.
            model.refreshAuthorization()
            if model.isSetupComplete {
                model.performHealthCheck()
            }
        }
    }

    private var navigationStack: some View {
        NavigationStack(path: $router.path) {
            Group {
                if model.isSetupComplete && model.isSignedIn {
                    MainTabView()
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
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .createAccount: CreateAccountView()
        case .signIn: SignInView()
        case .childDevice: ChildDeviceView()
        case .protectionProfile: ProtectionProfileView()
        case .recommendedSetup: RecommendedSetupView()
        case .configureSettings: ConfigureSettingsView(isOnboarding: true)
        case .healthCheck: HealthCheckView(isOnboarding: true)
        case .complete: CompleteView()
        case .manageProtection: ConfigureSettingsView(isOnboarding: false)
        case .healthReview: HealthCheckView(isOnboarding: false)
        case .authorization: AuthorizationView()
        case .featureDetail(let feature): FeatureConfigurationView(feature: feature)
        case .childProfile: ChildProfileView()
        case .screenTime: ScreenTimeView()
        case .appsManagement: AppsManagementView()
        case .location: LocationView()
        case .alerts: AlertsView(isRoot: false)
        case .settings: SettingsView(isRoot: false)
        case .account: AccountView()
        case .notifications: NotificationsView()
        case .privacy: PrivacyView()
        case .about: AboutView()
        case .subscription: SubscriptionView()
        case .helpSupport: HelpSupportView()
        }
    }
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel.mock())
}

#Preview("Dashboard") {
    RootView()
        .environment(AppModel.preview())
}
