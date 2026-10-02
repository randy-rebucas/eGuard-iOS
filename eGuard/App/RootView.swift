import SwiftUI

/// Hosts the splash, the update gate, and routes on the install's mode: the "Who's using this device?"
/// chooser, the parent's NavigationStack, or the child device screens.
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
            } else if model.mode == .child {
                ChildDeviceRootView()
                    .transition(.opacity)
            } else {
                navigationStack
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: isShowingSplash)
        .animation(.easeInOut(duration: 0.45), value: model.mode)
        .task {
            async let bootstrap: Void = model.bootstrap()
            if !model.skipsSplash {
                try? await Task.sleep(for: .seconds(1.4))
            }
            splashElapsed = true
            await bootstrap
            handlePendingDeepLink()
            await handlePendingPushAlert()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.bootstrapState == .ready else { return }
            if model.mode == .child {
                Task { await model.childDevice.syncNow() }
            } else if model.isSignedIn {
                // Alerts resolve and devices report while the app is in the background, so refresh on return.
                Task { await model.refreshDashboard() }
            }
        }
        .onChange(of: model.isSignedIn) { _, isSignedIn in
            // Losing the session (a 401 or sign-out) must not leave the parent on a signed-in screen.
            guard !isSignedIn else { return }
            router.show(.home)
        }
        .onChange(of: model.pendingDeepLink) { _, _ in handlePendingDeepLink() }
        .onChange(of: model.pendingPushAlert) { _, _ in Task { await handlePendingPushAlert() } }
    }

    /// A tapped alert push opens the Alerts tab (or the child's app requests when the alert is about apps).
    private func handlePendingPushAlert() async {
        guard model.bootstrapState == .ready, let alert = await model.consumePushAlert() else { return }
        if alert.category == "APPS", let childId = alert.childId {
            router.popToRoot()
            router.push(.appsManagement(childId: childId))
        } else {
            router.show(.alerts)
        }
    }

    private var navigationStack: some View {
        NavigationStack(path: $router.path) {
            Group {
                if model.mode == .unset {
                    ModeChooserView()
                } else if model.isSetupComplete {
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

    /// Email links are for parents. On a child's device the app says so instead of handling them.
    private func handlePendingDeepLink() {
        guard model.bootstrapState == .ready, let link = model.pendingDeepLink else { return }
        model.pendingDeepLink = nil
        if model.mode == .child {
            model.childDevice.deepLinkNotice = "Open this link on your parent's phone or at eguard.family."
        } else {
            router.open(link)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .welcome: WelcomeView()
        case .childSetup: ChildSetupView(startStep: .code)
        case .createAccount: CreateAccountView()
        case .signIn: SignInView()
        case .forgotPassword: ForgotPasswordView()
        case .twoFactorCode(let challenge): TwoFactorCodeView(challenge: challenge)
        case .resetPassword(let token): ResetPasswordView(token: token)
        case .verifyEmailLink(let token): VerifyEmailLinkView(token: token)
        case .acceptInvite(let token): AcceptInviteView(token: token)
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
        case .browserPolicy(let childId): BrowserPolicyView(childId: childId)
        case .alerts: AlertsView(isRoot: false)
        case .settings: SettingsView(isRoot: false)
        case .account: AccountView()
        case .changePassword: ChangePasswordView()
        case .sessions: SessionsView()
        case .twoFactor: TwoFactorView()
        case .linkedSignIns: LinkedSignInsView()
        case .deleteAccount: DeleteAccountView()
        case .family: FamilyView()
        case .organizations: OrganizationsView()
        case .setUpChildDevice: HandDownDeviceView()
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

/// Shown when the server's minimum app version is newer than this build. Used by both modes.
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

#Preview("Mode chooser") {
    RootView()
        .environment(AppModel.mock(mode: .unset))
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel.mock())
}

#Preview("Dashboard") {
    RootView()
        .environment(AppModel.preview())
}
