import SwiftUI

/// Devices tab, from `GET /devices` and `GET /browsers`.
struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<DevicesResponse> = .loading
    @State private var browsers: [ConnectedBrowser] = []
    @State private var isChecking = false
    @State private var checkResult: CheckRun?
    @State private var checkError: String?
    @State private var browserToRemove: ConnectedBrowser?
    @State private var browserError: String?

    var body: some View {
        TabScreen {
            TabScreenHeader(title: "Devices") {
                EmptyView()
            } trailing: {
                Button {
                    Task { await runCheck() }
                } label: {
                    if isChecking { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(isChecking)
                .accessibilityLabel("Check all devices")
            }
        } content: {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadDevices() } }
            case .loaded(let response):
                if let limit = response.limit {
                    Text("\(response.devices.count + browsers.count) of \(limit) device slots on your plan")
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                if let checkError {
                    ErrorCard(message: checkError)
                }
                if let checkResult {
                    checkCard(checkResult)
                }
                if response.devices.isEmpty {
                    EmptyStateView(symbolName: "iphone.slash", title: "No devices paired", message: "Open a child's profile and tap Set Up Supervision to pair a device.")
                }
                ForEach(response.devices) { device in
                    deviceCard(device)
                }
                if !browsers.isEmpty {
                    browsersSection
                }
            }
        }
        .refreshable { await loadDevices() }
        .task { await loadDevices() }
        .deletionConfirmation(
            "Remove \(browserToRemove?.deviceLabel ?? "this browser")?",
            message: "The eGuard extension forgets the connection on its next check, and the family gets a \"Browser removed\" alert.",
            confirmTitle: "Remove",
            isPresented: Binding(get: { browserToRemove != nil }, set: { if !$0 { browserToRemove = nil } }),
            user: model.user
        ) { confirmation in
            Task { await removeBrowser(confirmation) }
        }
    }

    private func loadDevices() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.devices() }
        browsers = (try? await model.api.browsers()) ?? []
    }

    /// Asks every device for a fresh report and shows who answered.
    private func runCheck() async {
        isChecking = true
        checkError = nil
        defer { isChecking = false }
        do {
            let runId = try await model.api.startCheck(deviceId: nil)
            let started = Date.now
            repeat {
                checkResult = try await model.api.check(runId: runId)
                if checkResult?.done == true { break }
                try? await Task.sleep(for: BatchPoller.interval)
            } while Date.now.timeIntervalSince(started) < 15
        } catch {
            checkError = error.localizedDescription
        }
        await loadDevices()
        await model.refreshDashboard()
    }

    private func checkCard(_ run: CheckRun) -> some View {
        EGuardCard {
            SectionHeader(title: run.done ? "Check complete" : "Checking devices…")
            ForEach(run.results) { result in
                HStack {
                    Text("\(result.deviceName) · \(result.childName)").font(EGuardTypography.callout)
                    Spacer()
                    if result.reachable == false {
                        StatusPill(text: "Couldn't reach", tint: EGuardColors.warning)
                    } else if let issues = result.issues {
                        StatusPill(text: issues == 0 ? "All good" : "\(issues) issue\(issues == 1 ? "" : "s")", tint: issues == 0 ? EGuardColors.success : EGuardColors.warning)
                    } else {
                        ProgressView()
                    }
                }
            }
            if run.done {
                // A full score with offline devices is their last known state, never "verified".
                Text(run.health.isVerified
                     ? "Every protection is verified on every device."
                     : (run.health.score >= run.health.total && run.health.total > 0 ? "Every protection is set, as last reported." : "\(run.health.text) protections passing.") + (run.health.offlineNote.map { " \($0)" } ?? ""))
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }

    private func deviceCard(_ device: APIDevice) -> some View {
        Button {
            router.push(.deviceDetail(deviceId: device.id))
        } label: {
            EGuardCard {
                HStack(spacing: EGuardSpacing.md) {
                    IconTile(symbolName: device.symbolName, tint: tint(device.state), size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(EGuardTypography.title3).foregroundStyle(EGuardColors.textPrimary)
                        Text("\(device.childName) · \(device.osVersion ?? device.platform.title)")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                        HStack(spacing: EGuardSpacing.xs) {
                            // A just-paired device shows "Waiting for first check" instead of its issue count.
                            StatusPill(text: device.statusText, tint: device.isAwaitingFirstCheck ? EGuardColors.primary : tint(device.state))
                            if device.isPrimary { StatusPill(text: "Primary", tint: EGuardColors.tilePurple) }
                            if let battery = device.battery {
                                Label("\(battery)%", systemImage: battery > 20 ? "battery.75percent" : "battery.25percent")
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(EGuardColors.neutral)
                }
                if let seen = device.lastSeenLabel {
                    EGuardValueRow(label: "Last seen", value: seen)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("devices.device.\(device.id)")
    }

    /// Browser extensions take plan slots but never enforce a policy, so they're never shown as protected.
    private var browsersSection: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Browsers")
            EGuardCard {
                ForEach(browsers) { browser in
                    HStack(spacing: EGuardSpacing.sm) {
                        IconTile(symbolName: "globe", tint: browser.connected ? EGuardColors.tileTeal : EGuardColors.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(browser.deviceLabel).font(EGuardTypography.label)
                            Text([browser.childName, browser.detail.isEmpty ? nil : browser.detail, browser.lastSeenAt.map { "Seen \($0.relativeDescription())" }].compactMap { $0 }.joined(separator: " · "))
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                            if !browser.connected {
                                Text("Disconnected for security. Remove it and add it again.")
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.danger)
                            } else {
                                // The extension's own health check; "Not seen for a day" when it can't be confirmed.
                                StatusPill(text: browser.stateLabel, tint: browserTint(browser))
                            }
                        }
                        Spacer()
                        Menu {
                            Button("Website rules", systemImage: "list.bullet.rectangle") { router.push(.browserPolicy(childId: browser.childId)) }
                            Button("Remove", systemImage: "trash", role: .destructive) { browserToRemove = browser }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(EGuardColors.neutral)
                        }
                        .accessibilityLabel("Options for \(browser.deviceLabel)")
                    }
                    .padding(.vertical, EGuardSpacing.xxs)
                    if browser.id != browsers.last?.id { Divider() }
                }
                InlineError(message: browserError)
            }
        }
    }

    private func removeBrowser(_ confirmation: DeletionConfirmation) async {
        guard let browser = browserToRemove else { return }
        do {
            try await model.api.removeBrowser(id: browser.id, confirmation: confirmation)
            browserError = nil
            await loadDevices()
        } catch {
            browserError = error.localizedDescription
        }
        browserToRemove = nil
    }

    private func tint(_ state: DeviceState) -> Color {
        switch state {
        case .healthy: EGuardColors.success
        case .issues: EGuardColors.warning
        case .offline: EGuardColors.neutral
        }
    }

    private func browserTint(_ browser: ConnectedBrowser) -> Color {
        switch browser.stateTint {
        case .good: EGuardColors.success
        case .warning: EGuardColors.warning
        case .bad: EGuardColors.danger
        case .neutral: EGuardColors.neutral
        }
    }
}

/// Device detail: `GET /devices/{id}` with rename, unpair, and a per-device check.
struct DeviceDetailView: View {
    let deviceId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<DeviceDetail> = .loading
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isChoosingRemoval = false
    @State private var deleteHistory = false
    @State private var isConfirmingUnpair = false
    @State private var isChoosingMoveTarget = false
    @State private var moveTargetId: String?
    @State private var error: String?

    private var otherChildren: [ChildSummary] {
        model.children.filter { $0.id != state.value?.childId }
    }

    private var moveTargetName: String {
        model.children.first { $0.id == moveTargetId }?.name ?? "another child"
    }

    var body: some View {
        EGuardScreen {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadDevice() } }
            case .loaded(let detail):
                EGuardCard {
                    HStack(spacing: EGuardSpacing.md) {
                        IconTile(symbolName: detail.device.symbolName, tint: EGuardColors.primary, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detail.name).font(EGuardTypography.title3)
                            Text([detail.model, detail.osVersion].compactMap { $0 }.joined(separator: " · "))
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                            HStack(spacing: EGuardSpacing.xs) {
                                StatusPill(text: detail.device.statusText, tint: detail.device.isAwaitingFirstCheck ? EGuardColors.primary : (detail.state == .healthy ? EGuardColors.success : EGuardColors.warning))
                                if detail.isPrimary { StatusPill(text: "Primary", tint: EGuardColors.tilePurple) }
                            }
                        }
                        Spacer()
                    }
                    Divider()
                    EGuardValueRow(label: "Child", value: detail.childName)
                    EGuardValueRow(label: "eGuard version", value: detail.appVersion ?? "Unknown")
                    EGuardValueRow(label: "Last seen", value: detail.lastSeenLabel ?? "Never")
                    if let battery = detail.battery { EGuardValueRow(label: "Battery", value: "\(battery)%") }
                    if detail.state == .offline {
                        Text("This device hasn't synced in over a day. Its protections show their last known state until it reconnects.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.warning)
                    } else if detail.device.isAwaitingFirstCheck {
                        Text("Waiting for this device's first check. Protections count as issues until it reports what it really has.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                }

                EGuardCard {
                    SectionHeader(title: "Protections on this device")
                    ForEach(detail.protections) { protection in
                        Button {
                            router.push(.protectionEditor(childId: detail.childId, key: protection.key))
                        } label: {
                            HStack {
                                ChecklistRow(title: protection.name, detail: protection.message ?? protection.reportedLabel, status: protection.status.healthStatus)
                                ModeBadge(mode: protection.capability.mode)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(protection.capability == .unsupported)
                        if protection.id != detail.protections.last?.id { Divider() }
                    }
                }
                InlineError(message: error)
            }
        } actions: {
            if let detail = state.value {
                Button("Rename Device") {
                    newName = detail.name
                    isRenaming = true
                }
                .buttonStyle(.eGuardSecondary)
                if !detail.isPrimary {
                    Button("Make Primary Device") { Task { await makePrimary() } }
                        .buttonStyle(.eGuardSecondary)
                        .accessibilityIdentifier("device.makePrimary")
                }
                if !otherChildren.isEmpty {
                    Button("Move to Another Child") { isChoosingMoveTarget = true }
                        .buttonStyle(.eGuardSecondary)
                        .accessibilityIdentifier("device.move")
                }
                Button("Remove Device", role: .destructive) { isChoosingRemoval = true }
                    .buttonStyle(.eGuardText)
                    .accessibilityIdentifier("device.remove")
            }
        }
        .navigationTitle(state.value?.name ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDevice() }
        .alert("Rename device", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Move \(state.value?.name ?? "this device") to", isPresented: $isChoosingMoveTarget, titleVisibility: .visible) {
            ForEach(otherChildren) { child in
                Button(child.name) { afterDialog { moveTargetId = child.id } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The device gets that child's protections and apps on its next sync, without pairing again. What it recorded stays with \(state.value?.childName ?? "the current child").")
        }
        .deletionConfirmation(
            "Move to \(moveTargetName)?",
            message: "Its reported protections are cleared until it reports again, open changes are cancelled, and the family gets a \"Device moved\" alert.",
            confirmTitle: "Move",
            isPresented: Binding(get: { moveTargetId != nil }, set: { if !$0 { moveTargetId = nil } }),
            user: model.user
        ) { confirmation in
            Task { await move(confirmation) }
        }
        .confirmationDialog("Remove this device?", isPresented: $isChoosingRemoval, titleVisibility: .visible) {
            // "Also delete what it recorded" is an option, off by default.
            Button("Remove, keep what it recorded", role: .destructive) { afterDialog { deleteHistory = false; isConfirmingUnpair = true } }
            Button("Remove and delete what it recorded", role: .destructive) { afterDialog { deleteHistory = true; isConfirmingUnpair = true } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("eGuard stops managing it and its token stops working. By default the screen time, app usage and places it recorded stay with \(state.value?.childName ?? "the child") until your plan's retention period ends.")
        }
        .deletionConfirmation(
            deleteHistory ? "Remove this device and delete what it recorded?" : "Remove this device?",
            message: "The device clears its protections at its next check-in, and the family gets a \"Device removed\" alert.",
            confirmTitle: "Remove",
            isPresented: $isConfirmingUnpair,
            user: model.user
        ) { confirmation in
            Task { await unpair(confirmation) }
        }
    }

    /// Runs after a confirmation dialog has closed, so the next alert can present.
    private func afterDialog(_ action: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            action()
        }
    }

    private func loadDevice() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.device(id: deviceId) }
    }

    private func rename() async {
        do {
            state = .loaded(try await model.api.renameDevice(id: deviceId, name: newName.trimmingCharacters(in: .whitespaces)))
            await model.refreshDashboard()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func makePrimary() async {
        do {
            state = .loaded(try await model.api.updateDevice(id: deviceId, patch: DevicePatch(name: nil, isPrimary: true)))
            await model.refreshDashboard()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func move(_ confirmation: DeletionConfirmation) async {
        guard let target = moveTargetId else { return }
        do {
            state = .loaded(try await model.api.moveDevice(id: deviceId, childId: target, confirmation: confirmation))
            await model.refreshDashboard()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        moveTargetId = nil
    }

    private func unpair(_ confirmation: DeletionConfirmation) async {
        do {
            try await model.api.unpairDevice(id: deviceId, confirmation: confirmation, deleteHistory: deleteHistory)
            await model.refreshDashboard()
            router.pop()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        DevicesView()
    }
    .environment(AppModel.live())
    .environment(AppRouter())
}
