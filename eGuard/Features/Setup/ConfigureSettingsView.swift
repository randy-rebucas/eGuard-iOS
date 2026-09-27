import SwiftUI

/// 07 Configure Settings, shown as a numbered step list. Also reused as "Manage Protection".
struct ConfigureSettingsView: View {
    let isOnboarding: Bool

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var features: [ProtectionFeature] { model.settings.enabledFeatures }

    /// The first step that is not finished is highlighted as the current one.
    private var currentFeature: ProtectionFeature? {
        features.first { !model.progress.state(for: $0).isComplete }
    }

    var body: some View {
        EGuardScreen {
            if isOnboarding {
                OnboardingProgressIndicator(step: .configureSettings)
            }
            ScreenHeader(
                title: isOnboarding ? "Configure settings" : "Protection & Controls",
                subtitle: isOnboarding
                    ? "We'll guide you step-by-step and verify each setting."
                    : "\(model.progress.completedCount(of: features)) of \(features.count) protections configured."
            )

            if !model.authorizationStatus.isAuthorized {
                authorizationStep
            }

            if model.environment.isSimulator {
                EGuardCard {
                    Label("The simulator can't enforce Screen Time protections. Test on a real device to verify shielding.", systemImage: "exclamationmark.triangle.fill")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.warning)
                }
            }

            if features.isEmpty {
                EGuardCard {
                    Text("No protections are turned on. Go back to Recommended Setup to choose some.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            } else {
                VStack(spacing: EGuardSpacing.xs) {
                    ForEach(Array(features.enumerated()), id: \.element) { index, feature in
                        SetupStepRow(
                            number: index + 1,
                            feature: feature,
                            summary: model.settings.summary(for: feature),
                            state: model.progress.state(for: feature),
                            capability: model.capability(for: feature),
                            isCurrent: feature == currentFeature
                        ) {
                            router.push(.featureDetail(feature))
                        }
                    }
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
                Button("Change recommended values") {
                    router.push(.recommendedSetup)
                }
                .buttonStyle(.eGuardText)
            }
        }
        .modifier(ConfigureTitle(isOnboarding: isOnboarding))
        .onAppear { model.refreshAuthorization() }
    }

    private var authorizationStep: some View {
        Button {
            router.push(.authorization)
        } label: {
            HStack(spacing: EGuardSpacing.sm) {
                StepNumber(number: 0, symbol: "hand.raised.fill", isCurrent: true, isDone: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up supervision")
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.textPrimary)
                    Text("Grant Family Controls authorization")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(EGuardColors.neutral)
            }
            .padding(EGuardSpacing.sm)
            .background(EGuardColors.primarySoft, in: EGuardShapes.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("configure.authorize")
    }
}

private struct ConfigureTitle: ViewModifier {
    let isOnboarding: Bool

    func body(content: Content) -> some View {
        if isOnboarding {
            content.brandNavigationTitle()
        } else {
            content
                .navigationTitle("Manage Protection")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// One numbered step in the configuration list.
struct SetupStepRow: View {
    let number: Int
    let feature: ProtectionFeature
    let summary: String
    let state: FeatureConfigurationState
    let capability: ProtectionCapability
    let isCurrent: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: EGuardSpacing.sm) {
                StepNumber(number: number, symbol: nil, isCurrent: isCurrent, isDone: state.isComplete)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.textPrimary)
                    Text(detail)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(detailColor)
                }
                Spacer(minLength: EGuardSpacing.xs)
                if capability.mode != .automatic {
                    ModeBadge(mode: capability.mode)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(EGuardColors.neutral)
            }
            .padding(EGuardSpacing.sm)
            .background(isCurrent ? EGuardColors.primarySoft : EGuardColors.surface, in: EGuardShapes.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.statusLabel)
        .accessibilityIdentifier("configure.feature.\(feature.rawValue)")
    }

    private var detail: String {
        switch state {
        case .configured, .confirmedByParent: summary
        case .failed: "Could not configure – tap to retry"
        case .awaitingReturn: "Finish in Settings, then confirm"
        case .skipped: "Skipped for now"
        case .notConfigured: isCurrent ? "Set \(summary.lowercased())" : summary
        }
    }

    private var detailColor: Color {
        switch state {
        case .failed: EGuardColors.danger
        case .awaitingReturn: EGuardColors.warning
        default: EGuardColors.textSecondary
        }
    }
}

/// The numbered circle at the start of a step row.
struct StepNumber: View {
    let number: Int
    let symbol: String?
    let isCurrent: Bool
    let isDone: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone || isCurrent ? EGuardColors.primary : EGuardColors.primary.opacity(0.12))
            if isDone {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(number)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(isCurrent ? .white : EGuardColors.primary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
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
        }
        .accessibilityElement(children: .contain)
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
