import Observation
import SwiftUI

/// Drives the apply / guided flow for a single feature.
@Observable
final class FeatureConfigurationViewModel {
    enum Phase: Equatable {
        case idle
        case applying
        case succeeded(Date)
        case failed(String)
    }

    let feature: ProtectionFeature
    private(set) var phase: Phase = .idle
    var isShowingSelection = false
    var isConfirmingGuidedStep = false

    init(feature: ProtectionFeature) {
        self.feature = feature
    }

    func configure(using model: AppModel) {
        phase = .applying
        let result = model.configure(feature)
        switch result {
        case .configured(let date):
            phase = .succeeded(date)
        case .failed(let message):
            phase = .failed(message)
        default:
            phase = .failed("eGuard could not confirm the change.")
        }
    }

    func openSettings(using model: AppModel, openURL: OpenURLAction) {
        model.markGuidedStepOpened(feature)
        if let url = model.systemSettings.settingsURL {
            openURL(url)
        }
    }

    func confirmGuided(using model: AppModel) {
        model.confirmGuidedStep(feature)
        phase = .succeeded(.now)
    }

    func skip(using model: AppModel) {
        model.skip(feature)
    }

    func needsSelection(model: AppModel) -> Bool {
        guard let purpose = feature.selectionPurpose else { return false }
        return model.selections[purpose].isEmpty
    }
}

/// Automatic, guided, and unsupported configuration for one feature.
struct FeatureConfigurationView: View {
    let feature: ProtectionFeature

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var viewModel: FeatureConfigurationViewModel

    init(feature: ProtectionFeature) {
        self.feature = feature
        _viewModel = State(initialValue: FeatureConfigurationViewModel(feature: feature))
    }

    private var capability: ProtectionCapability { model.capability(for: feature) }
    private var state: FeatureConfigurationState { model.progress.state(for: feature) }

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            headerCard

            switch capability.mode {
            case .automatic:
                automaticSection
            case .guided, .verificationOnly:
                guidedSection
            case .unsupported:
                unsupportedSection
            }
        } actions: {
            actions
        }
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.isShowingSelection) {
            if let purpose = feature.selectionPurpose {
                AppSelectionView(purpose: purpose)
            }
        }
        .confirmationDialog(
            "Did you finish this setting in Settings?",
            isPresented: $viewModel.isConfirmingGuidedStep,
            titleVisibility: .visible
        ) {
            Button("Yes, it's done") { viewModel.confirmGuided(using: model) }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Apple does not let eGuard verify this setting, so your confirmation is recorded instead.")
        }
    }

    // MARK: Sections

    private var headerCard: some View {
        EGuardCard {
            HStack(alignment: .top) {
                Label(feature.title, systemImage: feature.symbolName)
                    .font(EGuardTypography.headline)
                Spacer()
                ModeBadge(mode: capability.mode)
            }
            Text(model.settings.summary(for: feature))
                .font(EGuardTypography.title)
            Text("Status")
                .font(EGuardTypography.overline)
                .foregroundStyle(EGuardColors.textSecondary)
            StatusIndicator(text: state.statusLabel, color: EGuardTheme.color(for: state))
            Text(capability.explanation)
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
        }
    }

    @ViewBuilder
    private var automaticSection: some View {
        if !model.authorizationStatus.isAuthorized {
            EGuardCard {
                Label("eGuard needs your permission", systemImage: "hand.raised.fill")
                    .font(EGuardTypography.headline)
                Text("This setting is applied with Apple's Screen Time frameworks, which require Family Controls authorization first.")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
                Button("Continue") { router.push(.authorization) }
                    .buttonStyle(.eGuardSecondary)
                    .accessibilityIdentifier("feature.authorize")
            }
        }

        if let purpose = feature.selectionPurpose {
            EGuardCard {
                Text(purpose.title)
                    .font(EGuardTypography.headline)
                Text(purpose.instruction)
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
                EGuardValueRow(label: "Selected", value: model.selections[purpose].summary)
                Button(model.selections[purpose].isEmpty ? "Choose Apps" : "Change Apps") {
                    viewModel.isShowingSelection = true
                }
                .buttonStyle(.eGuardSecondary)
                .accessibilityIdentifier("feature.chooseApps")
            }
        }

        switch viewModel.phase {
        case .succeeded:
            resultCard(
                symbol: "checkmark.circle.fill",
                tint: EGuardColors.success,
                title: "Setting configured",
                message: "\(feature.title) is now \(model.settings.summary(for: feature))."
            )
        case .failed(let message):
            resultCard(
                symbol: "xmark.octagon.fill",
                tint: EGuardColors.danger,
                title: "Setting not configured",
                message: message
            )
        case .idle, .applying:
            if let failure = state.failureMessage {
                resultCard(
                    symbol: "xmark.octagon.fill",
                    tint: EGuardColors.danger,
                    title: "Last attempt failed",
                    message: failure
                )
            }
        }
    }

    @ViewBuilder
    private var guidedSection: some View {
        let instructions = model.systemSettings.instructions(for: feature)

        EGuardCard {
            Text("Let's finish this setting")
                .font(EGuardTypography.headline)
            Text("Apple requires this setting to be completed from your device settings.")
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
            EGuardValueRow(label: "Where", value: instructions.settingsPath)
            ForEach(Array(instructions.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: EGuardSpacing.xs) {
                    Text("\(index + 1).")
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.primary)
                    Text(step)
                        .font(EGuardTypography.body)
                }
            }
        }

        if case .awaitingReturn = state {
            EGuardCard {
                Text("Check Configuration")
                    .font(EGuardTypography.headline)
                Text(instructions.cannotVerifyNote)
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
                Button("Check Again") { viewModel.isConfirmingGuidedStep = true }
                    .buttonStyle(.eGuardSecondary)
                    .accessibilityIdentifier("feature.checkAgain")
            }
        }

        if case .succeeded = viewModel.phase {
            resultCard(
                symbol: "checkmark.circle.fill",
                tint: EGuardColors.success,
                title: "Marked complete",
                message: "You confirmed this setting. It appears in Configuration Health with the date you confirmed it."
            )
        }
    }

    private var unsupportedSection: some View {
        EGuardCard {
            Label("Not supported here", systemImage: "minus.circle.fill")
                .font(EGuardTypography.headline)
                .foregroundStyle(EGuardColors.neutral)
            Text(capability.explanation)
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
            Text("eGuard will not pretend this protection is active.")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        }
    }

    private func resultCard(symbol: String, tint: Color, title: String, message: String) -> some View {
        EGuardCard {
            Label(title, systemImage: symbol)
                .font(EGuardTypography.headline)
                .foregroundStyle(tint)
            Text(message)
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feature.result")
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch capability.mode {
        case .automatic:
            if case .succeeded = viewModel.phase {
                Button("Continue") { router.pop() }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("feature.continue")
            } else {
                Button(viewModel.phase == .applying ? "Configuring…" : (state.failureMessage == nil ? "Configure" : "Try Again")) {
                    viewModel.configure(using: model)
                }
                .buttonStyle(.eGuardPrimary)
                .disabled(!model.authorizationStatus.isAuthorized || viewModel.needsSelection(model: model) || viewModel.phase == .applying)
                .accessibilityIdentifier("feature.configure")
            }

        case .guided, .verificationOnly:
            if case .succeeded = viewModel.phase {
                Button("Continue") { router.pop() }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("feature.continue")
            } else {
                Button("Open Settings") { viewModel.openSettings(using: model, openURL: openURL) }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("feature.openSettings")
                Button("I'll Do This Later") {
                    viewModel.skip(using: model)
                    router.pop()
                }
                .buttonStyle(.eGuardText)
                .accessibilityIdentifier("feature.later")
            }

        case .unsupported:
            Button("Continue") { router.pop() }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("feature.continue")
        }
    }
}

#Preview("Automatic") {
    NavigationStack {
        FeatureConfigurationView(feature: .webContent)
    }
    .environment({
        let model = AppModel.mock(authorizationStatus: .approved)
        model.chooseProfile(.balanced)
        return model
    }())
    .environment(AppRouter())
}

#Preview("Guided") {
    NavigationStack {
        FeatureConfigurationView(feature: .screenTimePasscode)
    }
    .environment({
        let model = AppModel.mock(authorizationStatus: .approved)
        model.chooseProfile(.balanced)
        return model
    }())
    .environment(AppRouter())
}
