import Observation
import SwiftUI

/// Edits one protection: `PUT /children/{id}/protections/{KEY}`, then follows the batch to verification.
@Observable
final class ProtectionEditorViewModel {
    let childId: String
    let key: String
    let poller = BatchPoller()

    var state: LoadState<Protection> = .loading
    var config: JSONValue = .object([:])
    var isSaving = false
    var errorMessage: String?
    var guideItem: BatchItem?

    init(childId: String, key: String) {
        self.childId = childId
        self.key = key
    }

    var protection: Protection? { state.value }
    var hasChanges: Bool { protection.map { $0.policy.removing("key") != config.removing("key") } ?? false }

    func load(api: EGuardAPIService) async {
        state = .loading
        state = await MyApp.load {
            guard let protection = try await api.protections(childId: childId).first(where: { $0.key == key }) else {
                throw APIError.server(status: 404, code: "not_found", message: "That protection couldn't be found.")
            }
            return protection
        }
        if let protection {
            config = protection.policy
            // A change may still be in progress from earlier; resume following it.
            if let open = protection.openBatchId {
                poller.start(batchId: open, api: api)
            }
        }
    }

    func save(api: EGuardAPIService) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let batch = try await api.updateProtection(childId: childId, key: key, config: config)
            errorMessage = nil
            poller.start(batchId: batch.batchId, api: api, initial: batch)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirm(api: EGuardAPIService) async {
        do {
            try await poller.confirm(api: api)
            guideItem = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel(api: EGuardAPIService) async {
        do {
            try await poller.cancel(api: api)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var item: BatchItem? { poller.batch?.items.first { $0.key == key } }
}

struct ProtectionEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel: ProtectionEditorViewModel

    init(childId: String, key: String) {
        _viewModel = State(initialValue: ProtectionEditorViewModel(childId: childId, key: key))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            switch viewModel.state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await viewModel.load(api: model.api) } }
            case .loaded(let protection):
                header(protection)
                progressCard
                if protection.isUnsupportedEverywhere {
                    EGuardCard {
                        Label("Not supported on \(protection.devices.map(\.deviceName).joined(separator: ", "))", systemImage: "minus.circle.fill")
                            .font(EGuardTypography.headline)
                            .foregroundStyle(EGuardColors.neutral)
                        Text("This protection never counts against Configuration Health.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                } else {
                    Form {
                        ProtectionConfigEditor(key: viewModel.key, config: $viewModel.config)
                    }
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: formHeight)
                    .clipShape(EGuardShapes.card)
                }
                devicesCard(protection)
            }
            InlineError(message: viewModel.errorMessage)
        } actions: {
            if let item = viewModel.item, item.status == .awaitingParent {
                Button("Show steps & verify") { viewModel.guideItem = item }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("feature.openSettings")
                Button("Cancel change") { Task { await viewModel.cancel(api: model.api) } }
                    .buttonStyle(.eGuardText)
            } else if viewModel.poller.phase == .polling {
                Button("Verifying…") {}
                    .buttonStyle(.eGuardPrimary)
                    .disabled(true)
            } else {
                Button(viewModel.isSaving ? "Saving…" : "Save & Verify") { Task { await viewModel.save(api: model.api) } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(viewModel.isSaving || viewModel.protection == nil || viewModel.protection?.isUnsupportedEverywhere == true)
                    .accessibilityIdentifier("feature.configure")
            }
        }
        .navigationTitle(ProtectionKey.name(viewModel.key))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(api: model.api) }
        .onDisappear { viewModel.poller.stop() }
        .sheet(item: $viewModel.guideItem) { item in
            GuidedStepsSheet(item: item) { Task { await viewModel.confirm(api: model.api) } }
                .presentationDetents([.medium, .large])
        }
    }

    private var formHeight: CGFloat {
        switch viewModel.key {
        case "BEDTIME": 300
        case "SCREEN_TIME": 200
        case "WEB": 220
        default: 150
        }
    }

    private func header(_ protection: Protection) -> some View {
        EGuardCard {
            HStack(alignment: .top) {
                Label(ProtectionKey.name(protection.key), systemImage: LucideIcon.symbol(for: protection.icon, fallback: ProtectionKey.symbol(protection.key)))
                    .font(EGuardTypography.headline)
                Spacer()
                HealthStatusBadge(status: protection.status.healthStatus)
            }
            Text(ProtectionConfigFormatter.label(key: protection.key, config: viewModel.config))
                .font(EGuardTypography.title)
                .accessibilityIdentifier("feature.summary")
            Text(ProtectionKey.explanation(protection.key))
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textSecondary)
        }
    }

    @ViewBuilder
    private var progressCard: some View {
        if let item = viewModel.item {
            EGuardCard {
                HStack {
                    Label(statusTitle(item), systemImage: statusSymbol(item))
                        .font(EGuardTypography.headline)
                        .foregroundStyle(statusColor(item))
                    Spacer()
                    if viewModel.poller.phase == .polling { ProgressView() }
                }
                ForEach(item.devices) { device in
                    HStack {
                        Text(device.deviceName).font(EGuardTypography.callout)
                        Spacer()
                        Text(device.offline && !device.status.isFinished ? "Waiting for device to come online" : (device.failureReason ?? device.status.title))
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                }
                if viewModel.poller.phase == .waitingForDevice {
                    Text("Still waiting. You can leave and come back; the change keeps its state.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feature.result")
        }
    }

    private func statusTitle(_ item: BatchItem) -> String {
        switch item.status {
        case .verified: "Saved and verified"
        case .failed: "Setting not verified"
        case .awaitingParent: "Finish on the device"
        case .cancelled: "Change cancelled"
        default: "Waiting for the device…"
        }
    }

    private func statusSymbol(_ item: BatchItem) -> String {
        switch item.status {
        case .verified: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .awaitingParent: "hand.raised.fill"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private func statusColor(_ item: BatchItem) -> Color {
        switch item.status {
        case .verified: EGuardColors.success
        case .failed: EGuardColors.danger
        case .awaitingParent: EGuardColors.warning
        default: EGuardColors.primary
        }
    }

    private func devicesCard(_ protection: Protection) -> some View {
        EGuardCard {
            SectionHeader(title: "What devices report")
            if protection.devices.isEmpty {
                Text("No device is paired yet. The setting is saved and applied on pairing.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            ForEach(protection.devices) { device in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(device.deviceName).font(EGuardTypography.label)
                        Spacer()
                        ModeBadge(mode: device.capability.mode)
                    }
                    Text(device.message ?? device.reportedLabel ?? device.status.title)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                    if let verified = device.lastVerifiedAt {
                        Text("Last verified \(verified.verifiedDescription())")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                }
                .padding(.vertical, EGuardSpacing.xxs)
                if device.id != protection.devices.last?.id { Divider() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProtectionEditorView(childId: "child_1", key: "BEDTIME")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
