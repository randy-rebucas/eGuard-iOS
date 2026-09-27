import SwiftUI

/// Hosts the splash, the update gate, and the single NavigationStack.
/// A signed-in parent with at least one child starts in the tabbed app; everyone else starts at Welcome.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    @State private var splashElapsed = false

    private var isShowingSplash: Bool {
        (!splashElapsed && !model.skipsSplash) || model.bootstrapState == .loading || model.bootstrapState == .idle
    }

    var body: some View {
        ZStack {
            if case .updateRequired(let minimum) = model.bootstrapState {
                UpdateRequiredView(minimumVersion: minimum)
                    .transition(.opacity)
            } else if isShowingSplash {
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
            async let bootstrap: Void = model.bootstrap()
            if !model.skipsSplash {
                try? await Task.sleep(for: .seconds(1.4))
            }
            splashElapsed = true
            await bootstrap
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.bootstrapState == .ready, model.isSignedIn else { return }
            // Alerts resolve and devices report while the app is in the background, so refresh on return.
            Task {
                await model.refreshDashboard()
            }
        }
    }

    private var navigationStack: some View {
        NavigationStack(path: $router.path) {
            Group {
                if model.isSetupComplete {
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
        case .addChild: AddChildView(childId: nil)
        case .editChild(let childId): AddChildView(childId: childId)
        case .protectionProfile(let childId): ProtectionProfileView(childId: childId)
        case .recommendedSetup(let childId, let profile): RecommendedSetupView(childId: childId, profile: profile)
        case .setupProgress(let childId, let profile, let overrides): SetupProgressView(childId: childId, profile: profile, overrides: overrides)
        case .healthCheck(let childId, let isOnboarding): HealthCheckView(childId: childId, isOnboarding: isOnboarding)
        case .complete(let childId, let batchId): CompleteView(childId: childId, batchId: batchId)
        case .protections(let childId): ProtectionsView(childId: childId)
        case .protectionEditor(let childId, let key): ProtectionEditorView(childId: childId, key: key)
        case .childProfile(let childId): ChildProfileView(childId: childId)
        case .screenTime(let childId): ScreenTimeView(childId: childId)
        case .appsManagement(let childId): AppsManagementView(childId: childId)
        case .location(let childId): LocationView(childId: childId)
        case .deviceDetail(let deviceId): DeviceDetailView(deviceId: deviceId)
        case .alerts: AlertsView(isRoot: false)
        case .settings: SettingsView(isRoot: false)
        case .account: AccountView()
        case .changePassword: ChangePasswordView()
        case .sessions: SessionsView()
        case .family: FamilyView()
        case .notifications: NotificationsView()
        case .privacy: PrivacyView()
        case .about: AboutView()
        case .subscription: SubscriptionView()
        case .helpSupport: HelpSupportView()
        case .helpArticle(let slug): HelpArticleView(slug: slug)
        case .supportTicket: SupportTicketView()
        }
    }
}

/// Shown when the server's minimum app version is newer than this build.
struct UpdateRequiredView: View {
    let minimumVersion: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            EGuardColors.heroGradient.ignoresSafeArea()
            VStack(spacing: EGuardSpacing.lg) {
                EGuardLogoMark(size: 96)
                Text("Please update eGuard")
                    .font(EGuardTypography.display)
                Text("This version is no longer supported. Update to version \(minimumVersion) or later to keep protecting your family.")
                    .font(EGuardTypography.body)
                    .foregroundStyle(EGuardColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Open the App Store") {
                    if let url = URL(string: "https://apps.apple.com") { openURL(url) }
                }
                .buttonStyle(.eGuardPrimary)
            }
            .padding(EGuardSpacing.xl)
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
