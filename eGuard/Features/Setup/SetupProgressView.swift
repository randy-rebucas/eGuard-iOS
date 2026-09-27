import Observation
import SwiftUI

/// Drives step 7: pair a device, send the profile as one batch, and follow it to verification.
@Observable
final class SetupProgressViewModel {
    enum Stage: Equatable {
        case loadingChild
        case needsDevice
        case sending
        case saved([String])
        case tracking
        case failed(String)
    }

    let childId: String
    let profile: String
    let overrides: [JSONValue]
    let poller = BatchPoller()

    private(set) var stage: Stage = .loadingChild
    private(set) var child: ChildDetail?
    private(set) var setup: SetupResponse?
    var isShowingPairing = false
    var guideItem: BatchItem?
    var errorMessage: String?

    init(childId: String, profile: String, overrides: [JSONValue]) {
        self.childId = childId
        self.profile = profile
        self.overrides = overrides
    }

    var hasDevice: Bool { (child?.devices.isEmpty == false) }
    var batchId: String? { poller.batch?.batchId ?? setup?.batchId }

    func start(api: EGuardAPIService) async {
        stage = .loadingChild
        do {
            child = try await api.child(id: childId)
        } catch {
            stage = .failed(error.localizedDescription)
            return
        }
        if hasDevice {
            await send(api: api)
        } else {
            stage = .needsDevice
        }
    }

    /// Called after pairing; refreshes the child and sends the setup once a device exists.
    func refreshChild(api: EGuardAPIService) async {
        child = try? await api.child(id: childId)
        if hasDevice, stage == .needsDevice {
            await send(api: api)
        }
    }

    func send(api: EGuardAPIService) async {
        stage = .sending
        do {
            let response = try await api.setup(childId: childId, profile: profile, overrides: overrides)
            setup = response
            if let batchId = response.batchId {
                stage = .tracking
                poller.start(batchId: batchId, api: api, initial: response.progress)
            } else {
                stage = .saved(response.saved)
            }
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// "Skip for now": save the settings without a device; they apply on pairing.
    func skipPairing(api: EGuardAPIService) async {
        await send(api: api)
    }

    func confirmGuided(api: EGuardAPIService) async {
        do {
            try await poller.confirm(api: api)
            guideItem = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var canContinue: Bool {
        switch stage {
        case .saved: true
        case .tracking: poller.phase != .polling || poller.batch?.summary.awaitingParent ?? 0 > 0
        default: false
        }
    }
}

/// 07 Setup Progress
struct SetupProgressView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel: SetupProgressViewModel

    init(childId: String, profile: String, overrides: [JSONValue]) {
        _viewModel = State(initialValue: SetupProgressViewModel(childId: childId, profile: profile, overrides: overrides))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            OnboardingProgressIndicator(step: .configureSettings)
            ScreenHeader(
                title: "Configure settings",
                subtitle: "We'll guide you step-by-step and verify each setting."
            )

            VerifyEmailBanner()

            supervisionStep

            switch viewModel.stage {
            case .loadingChild, .sending:
                LoadingCard(message: viewModel.stage == .sending ? "Sending settings to the device…" : "Loading…")
            case .needsDevice:
                EGuardCard {
                    Text("Pair \(viewModel.child?.child.name ?? "your child")'s device to apply and verify each protection. You can also skip for now: the settings are saved and applied when a device is paired.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            case .saved(let keys):
                EGuardCard {
                    Label("Settings saved", systemImage: "checkmark.circle.fill")
                        .font(EGuardTypography.headline)
                        .foregroundStyle(EGuardColors.success)
                    Text("We'll apply these \(keys.count) protections when you add a device.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                .accessibilityIdentifier("setup.saved")
            case .tracking:
                if let batch = viewModel.poller.batch {
                    batchSteps(batch)
                }
                pollerStatus
            case .failed(let message):
                ErrorCard(message: message) { Task { await viewModel.start(api: model.api) } }
            }

            InlineError(message: viewModel.errorMessage)
        } actions: {
            switch viewModel.stage {
            case .needsDevice:
                Button("Set Up Supervision") { viewModel.isShowingPairing = true }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("setup.pair")
                Button("Skip for now") { Task { await viewModel.skipPairing(api: model.api) } }
                    .buttonStyle(.eGuardText)
                    .accessibilityIdentifier("setup.skip")
            default:
                Button("Continue") {
                    router.push(.healthCheck(childId: viewModel.childId, isOnboarding: true))
                }
                .buttonStyle(.eGuardPrimary)
                .disabled(!viewModel.canContinue)
                .accessibilityIdentifier("configure.continue")
            }
        }
        .brandNavigationTitle()
        .task { await viewModel.start(api: model.api) }
        .onDisappear { viewModel.poller.stop() }
        .sheet(isPresented: $viewModel.isShowingPairing, onDismiss: {
            Task { await viewModel.refreshChild(api: model.api) }
        }) {
            PairingCodeView(childId: viewModel.childId)
        }
        .sheet(item: $viewModel.guideItem) { item in
            GuidedStepsSheet(item: item) {
                Task { await viewModel.confirmGuided(api: model.api) }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Steps

    private var supervisionStep: some View {
        let paired = viewModel.hasDevice
        return Button {
            if !paired { viewModel.isShowingPairing = true }
        } label: {
            HStack(spacing: EGuardSpacing.sm) {
                StepNumber(number: 1, symbol: paired ? nil : "hand.raised.fill", isCurrent: !paired, isDone: paired)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up supervision")
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.textPrimary)
                    Text(paired
                         ? "\(viewModel.child?.devices.first?.name ?? "Device") paired"
                         : "Pair your child's device with a code")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                Spacer()
                if !paired {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(EGuardColors.neutral)
                }
            }
            .padding(EGuardSpacing.sm)
            .background(paired ? EGuardColors.surface : EGuardColors.primarySoft, in: EGuardShapes.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("configure.authorize")
    }

    private func batchSteps(_ batch: Batch) -> some View {
        VStack(spacing: EGuardSpacing.xs) {
            ForEach(Array(batch.items.enumerated()), id: \.element.id) { index, item in
                BatchItemRow(number: index + 2, item: item, isCurrent: item.status == .awaitingParent || item.status == .failed) {
                    if item.status == .awaitingParent {
                        viewModel.guideItem = item
                    } else {
                        router.push(.protectionEditor(childId: viewModel.childId, key: item.key))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pollerStatus: some View {
        switch viewModel.poller.phase {
        case .polling:
            HStack(spacing: EGuardSpacing.xs) {
                ProgressView()
                Text("Waiting for the device to verify…")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        case .waitingForDevice:
            EGuardCard {
                Label("Waiting for the device to come online", systemImage: "wifi.exclamationmark")
                    .font(EGuardTypography.headline)
                    .foregroundStyle(EGuardColors.warning)
                Text("You can continue now. eGuard finishes verifying when the device reconnects.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        case .done:
            if let health = viewModel.poller.batch?.health {
                Label("Configuration Health updated: \(health.text)", systemImage: "heart.text.square.fill")
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.success)
                    .accessibilityIdentifier("setup.done")
            }
        case .failed(let message):
            ErrorCard(message: message) {
                if let id = viewModel.batchId { viewModel.poller.start(batchId: id, api: model.api) }
            }
        case .idle:
            EmptyView()
        }
    }
}

/// One protection in a batch, styled as a numbered step.
struct BatchItemRow: View {
    let number: Int
    let item: BatchItem
    let isCurrent: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: EGuardSpacing.sm) {
                StepNumber(number: number, symbol: symbol, isCurrent: isCurrent, isDone: item.status == .verified)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ProtectionKey.name(item.key))
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.textPrimary)
                    Text(detail)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(detailColor)
                        .lineLimit(2)
                }
                Spacer(minLength: EGuardSpacing.xs)
                if item.status == .awaitingParent {
                    StatusPill(text: "Guided", tint: EGuardColors.accent)
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
        .accessibilityValue(item.status.title)
        .accessibilityIdentifier("configure.feature.\(item.key.lowercased())")
    }

    private var symbol: String? {
        switch item.status {
        case .failed: "exclamationmark"
        case .pending, .delivered: "arrow.triangle.2.circlepath"
        default: nil
        }
    }

    private var detail: String {
        if item.isOffline { return "Waiting for the device to come online" }
        switch item.status {
        case .verified: return item.to ?? "Verified"
        case .failed: return item.failureReason ?? "Failed – tap to try again"
        case .awaitingParent: return "Finish on the device, then verify"
        case .pending: return "Sending to the device…"
        case .delivered: return "Waiting for verification…"
        case .cancelled: return "Cancelled"
        }
    }

    private var detailColor: Color {
        switch item.status {
        case .failed: EGuardColors.danger
        case .awaitingParent: EGuardColors.warning
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
                    .foregroundStyle(isCurrent ? .white : EGuardColors.primary)
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

/// Guided setup: the steps to perform on the child's device, then "I've done this, verify now".
struct GuidedStepsSheet: View {
    let item: BatchItem
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EGuardScreen {
                if let device = item.devices.first(where: { $0.guide != nil }) {
                    ScreenHeader(
                        title: "Finish on \(device.deviceName)",
                        subtitle: "Apple requires this setting to be changed on the child's device. Follow these steps, then verify."
                    )
                    EGuardCard {
                        ForEach(Array((device.guide ?? []).enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: EGuardSpacing.xs) {
                                Text("\(index + 1).")
                                    .font(EGuardTypography.label)
                                    .foregroundStyle(EGuardColors.primary)
                                Text(step)
                                    .font(EGuardTypography.body)
                            }
                        }
                    }
                    if let to = item.to {
                        EGuardValueRow(label: "Expected", value: to)
                    }
                }
            } actions: {
                Button("I've done this, verify now") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("guide.confirm")
                Button("Not yet") { dismiss() }
                    .buttonStyle(.eGuardText)
            }
            .navigationTitle(ProtectionKey.name(item.key))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        SetupProgressView(childId: "child_1", profile: "PROTECTED", overrides: [])
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
