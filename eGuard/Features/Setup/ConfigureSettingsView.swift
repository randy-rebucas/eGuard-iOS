import SwiftUI

/// 05 Configure Settings. Also reused as "Manage Protection" from the dashboard.
struct ConfigureSettingsView: View {
    let isOnboarding: Bool

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var features: [ProtectionFeature] { model.settings.enabledFeatures }

    var body: some View {
        EGuardScreen {
            if isOnboarding {
                OnboardingProgressIndicator(step: .configureSettings)
            }
            ScreenHeader(
                title: "Configure Settings",
                subtitle: "\(model.progress.completedCount(of: features)) of \(features.count) protections configured."
            )

            if !model.authorizationStatus.isAuthorized {
                authorizationCard
            }

            if model.environment.isSimulator {
                EGuardCard {
                    Label("The simulator can't enforce Screen Time protections. Test on a real device to verify shielding.", systemImage: "exclamationmark.triangle.fill")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.warning)
                }
            }

            ForEach(features) { feature in
                FeatureCard(
                    feature: feature,
                    summary: model.settings.summary(for: feature),
                    state: model.progress.state(for: feature),
                    capability: model.capability(for: feature)
                ) {
                    router.push(.featureDetail(feature))
                }
            }

            if features.isEmpty {
                EGuardCard {
                    Text("No protections are turned on. Go back to Recommended Setup to choose some.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
        } actions: {
            if isOnboarding {
                Button("Continue") {
                    router.push(.healthCheck)
                }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("configure.continue")
            } else {
                Button("Check Configuration") {
                    router.push(.healthReview)
                }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("configure.checkConfiguration")
            }
        }
        .navigationTitle(isOnboarding ? OnboardingStep.configureSettings.title : "Manage Protection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refreshAuthorization() }
    }

    private var authorizationCard: some View {
        EGuardCard {
            Label("eGuard needs your permission", systemImage: "hand.raised.fill")
                .font(EGuardTypography.headline)
            Text("Automatic settings can only be applied after you grant Family Controls authorization.")
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
            Button("Continue") {
                router.push(.authorization)
            }
            .buttonStyle(.eGuardSecondary)
            .accessibilityIdentifier("configure.authorize")
        }
    }
}

/// The shared eGuard feature card: title, value, status, and a Configure action.
struct FeatureCard: View {
    let feature: ProtectionFeature
    let summary: String
    let state: FeatureConfigurationState
    let capability: ProtectionCapability
    let onConfigure: () -> Void

    var body: some View {
        EGuardCard {
            HStack(alignment: .top) {
                Label(feature.title, systemImage: feature.symbolName)
                    .font(EGuardTypography.headline)
                Spacer()
                ModeBadge(mode: capability.mode)
            }
            Text(summary)
                .font(EGuardTypography.title)
                .foregroundStyle(EGuardColors.textPrimary)
            VStack(alignment: .leading, spacing: EGuardSpacing.xxs) {
                Text("Status")
                    .font(EGuardTypography.overline)
                    .foregroundStyle(EGuardColors.textSecondary)
                StatusIndicator(text: state.statusLabel, color: EGuardTheme.color(for: state))
            }
            Button(buttonTitle, action: onConfigure)
                .buttonStyle(state.isComplete ? AnyButtonStyle(.eGuardSecondary) : AnyButtonStyle(.eGuardPrimary))
                .accessibilityIdentifier("configure.feature.\(feature.rawValue)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("configure.card.\(feature.rawValue)")
    }

    private var buttonTitle: String {
        switch capability.mode {
        case .unsupported: "Details"
        default: state.isComplete ? "Review" : "Configure"
        }
    }
}

/// Type-erases a button style so a card can switch styles without duplicating the button.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

#Preview {
    NavigationStack {
        ConfigureSettingsView(isOnboarding: true)
    }
    .environment({
        let model = AppModel.mock(authorizationStatus: .approved)
        model.chooseProfile(.protected)
        return model
    }())
    .environment(AppRouter())
}
