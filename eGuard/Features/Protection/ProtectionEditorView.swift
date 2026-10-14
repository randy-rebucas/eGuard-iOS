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
    /// "Saved. It applies when … is paired" for a child with no device yet.
    var notice: String?
    var guideItem: BatchItem?

    init(childId: String, key: String) {
        self.childId = childId
        self.key = key
    }

    var protection: Protection? { state.value }
    var hasChanges: Bool { protection.map { $0.policy.removing("key") != config.removing("key") } ?? false }

    func load(api: EGuardAPIService) async {
        state = .loading
        state = await eGuard.load {
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

    /// Reloads the protection without the loading state: after a change finishes or is refused, so the next save
    /// sends the current `version` and the form shows what's stored now.
    func refresh(api: EGuardAPIService) async {
        guard let latest = try? await api.protections(childId: childId).first(where: { $0.key == key }) else { return }
        state = .loaded(latest)
        config = latest.policy
    }

    func save(api: EGuardAPIService) async {
        if let problem = ProtectionConfigEditor.problem(key: key, config: config) {
            errorMessage = problem
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            // The version the parent saw: another parent's change since then is refused, not silently undone
            let result = try await api.updateProtection(childId: childId, key: key, config: config, baseVersion: protection?.version)
            errorMessage = nil
            switch result {
            case .queued(let batch):
                notice = nil
                poller.start(batchId: batch.batchId, api: api, initial: batch)
            case .savedForPairing:
                notice = "Saved. It applies when a device is paired."
                await refresh(api: api)
            }
        } catch {
            errorMessage = error.localizedDescription
            // Changed elsewhere, or no device supports it: show what's there now
            if case APIError.server(_, let code, _) = error, code == "stale" || code == "unsupported" {
                await refresh(api: api)
            }
        }
    }

    func confirm(api: EGuardAPIService) async {
        do {
            try await poller.confirm(api: api, key: key)
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

    /// A change (maybe another parent's) still waiting for the device. The form shows the stored value, which the
    /// server keeps until the device verifies, so saving would replace that change: the parent confirms first.
    var waitingChange: BatchItem? { item.flatMap { $0.status.isFinished ? nil : $0 } }
}

struct ProtectionEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel: ProtectionEditorViewModel
    @State private var isConfirmingReplace = false

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
            if let notice = viewModel.notice {
                Text(notice)
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.success)
            }
            // A poll that stopped on an error would otherwise leave "Waiting for the device…" with no reason
            if case .failed(let message) = viewModel.poller.phase {
                InlineError(message: message)
            }
            InlineError(message: viewModel.errorMessage)
        } actions: {
            if let item = viewModel.item, item.status == .awaitingParent {
                Button("Show steps & verify") { viewModel.guideItem = item }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("feature.openSettings")
                // Cancelling is per batch: only offered when this protection is all of it (not a whole setup)
                if viewModel.poller.batch?.items.count == 1 {
                    Button("Cancel change") { Task { await viewModel.cancel(api: model.api) } }
                        .buttonStyle(.eGuardText)
                }
            } else if viewModel.poller.phase == .polling {
                Button("Verifying…") {}
                    .buttonStyle(.eGuardPrimary)
                    .disabled(true)
            } else {
                // With no device there's nothing to verify yet: it's saved and applied on pairing
                Button(viewModel.isSaving ? "Saving…" : (viewModel.protection?.devices.isEmpty == true ? "Save" : "Save & Verify")) {
                    if viewModel.waitingChange != nil {
                        isConfirmingReplace = true
                    } else {
                        Task { await viewModel.save(api: model.api) }
                    }
                }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(viewModel.isSaving || viewModel.protection == nil || viewModel.protection?.isUnsupportedEverywhere == true
                              || ProtectionConfigEditor.problem(key: viewModel.key, config: viewModel.config) != nil)
                    .accessibilityIdentifier("feature.configure")
            }
        }
        .navigationTitle(ProtectionKey.name(viewModel.key))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(api: model.api) }
        .refreshable { await viewModel.refresh(api: model.api) }
        // Finished (verified, failed or cancelled): reload so the status, reports and version are current
        .onChange(of: viewModel.poller.phase) { _, phase in
            if phase == .done { Task { await viewModel.refresh(api: model.api) } }
        }
        .onDisappear { viewModel.poller.stop() }
        .confirmationDialog(
            "Replace the waiting change?",
            isPresented: $isConfirmingReplace,
            titleVisibility: .visible
        ) {
            Button("Replace it", role: .destructive) { Task { await viewModel.save(api: model.api) } }
            Button("Keep waiting", role: .cancel) {}
        } message: {
            Text(viewModel.waitingChange?.to.map { "A change to \($0) hasn't reached the device yet. Saving replaces it with yours." }
                 ?? "A change hasn't reached the device yet. Saving replaces it with yours.")
        }
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
                HealthStatusBadge(status: protection.displayStatus)
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
                // The form above shows what's stored until the device verifies: say what it's changing to
                if let to = item.to, !item.status.isFinished {
                    Text("Changing to \(to)")
                        .font(EGuardTypography.callout)
                        .accessibilityIdentifier("feature.changingTo")
                }
                ForEach(item.devices) { device in
                    HStack {
                        Text(device.deviceName).font(EGuardTypography.callout)
                        Spacer()
                        Text(device.offline && !device.status.isFinished ? "Waiting for device to come online" : (device.failureReason ?? device.statusTitle))
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
        // The parent's word for a PARENT_SET step: saved, never "verified"
        case .verified: item.isParentSetOnly ? "Set by you, not verified" : "Saved and verified"
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
                Text("No device is paired yet. Saving keeps the setting, and it applies when a device is paired.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            ForEach(protection.devices) { device in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(device.deviceName).font(EGuardTypography.label)
                        Spacer()
                        if device.capability == .parentSet {
                            StatusPill(text: device.statusTitle, tint: EGuardTheme.color(for: device.displayStatus))
                        } else {
                            ModeBadge(mode: device.capability.mode)
                        }
                    }
                    Text(device.message ?? device.reportedLabel ?? device.statusTitle)
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

#if DEBUG
#Preview {
    NavigationStack {
        ProtectionEditorView(childId: "child_1", key: "BEDTIME")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
#endif
