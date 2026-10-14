import SwiftUI

/// Devices tab, from `GET /devices` and `GET /browsers`.
struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<DevicesResponse> = .loading
    @State private var browsers: [ConnectedBrowser] = []
    /// `GET /browsers` failed: say so rather than show none.
    @State private var browsersFailed = false
    @State private var isChecking = false
    @State private var checkResult: CheckRun?
    @State private var checkError: String?
    /// Kept until the removal finishes; the alert has its own flag, which closing it clears first.
    @State private var browserToRemove: ConnectedBrowser?
    @State private var isConfirmingBrowserRemoval = false
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
                    // The server's count; a browser disconnected for security doesn't take a slot
                    Text("\(response.used ?? response.devices.count + browsers.filter(\.connected).count) of \(limit) device slots on your plan")
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
                    EmptyStateView(symbolName: "iphone.slash", title: "No devices paired", message: "Open a child's profile and tap Pair a device.")
                }
                ForEach(response.devices) { device in
                    deviceCard(device)
                }
                if browsersFailed {
                    SectionHeader(title: "Browsers")
                    InlineError(message: "Couldn't load your browsers. Pull to refresh to try again.")
                } else if !browsers.isEmpty {
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
            isPresented: $isConfirmingBrowserRemoval,
            user: model.user
        ) { confirmation in
            // Read now: closing the alert clears `browserToRemove` before the Task runs
            guard let browser = browserToRemove else { return }
            Task { await removeBrowser(browser, confirmation) }
        }
    }

    private func loadDevices() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.devices() }
        do {
            browsers = try await model.api.browsers()
            browsersFailed = false
        } catch {
            browsersFailed = true
        }
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
                    IconTile(symbolName: device.symbolName, tint: deviceTint(device), size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(EGuardTypography.title3).foregroundStyle(EGuardColors.textPrimary)
                        Text("\(device.childName) · \(device.osVersion ?? device.platform.title)")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                        HStack(spacing: EGuardSpacing.xs) {
                            StatusPill(text: device.statusTitle, tint: deviceTint(device))
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

    /// Browser extensions, with the server's status: what the extension last reported, unless it's disconnected or silent.
    private var browsersSection: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Browsers")
            EGuardCard {
                ForEach(browsers) { browser in
                    let color = browserTint(browser)
                    HStack(spacing: EGuardSpacing.sm) {
                        IconTile(symbolName: "globe", tint: color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(browser.deviceLabel).font(EGuardTypography.label)
                            Text([browser.childName, browser.detail.isEmpty ? nil : browser.detail, browser.lastSeenAt.map { "Seen \($0.relativeDescription())" }].compactMap { $0 }.joined(separator: " · "))
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                            StatusPill(text: browser.statusLabel, tint: color)
                            // Only when something needs doing: a healthy browser's note just repeats its label
                            if let note = browser.status?.note, browser.status?.tone == "warn" || browser.status?.tone == "crit" {
                                Text(note)
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(color)
                            }
                        }
                        Spacer()
                        Menu {
                            Button("Website rules", systemImage: "list.bullet.rectangle") { router.push(.browserPolicy(childId: browser.childId)) }
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                browserToRemove = browser
                                isConfirmingBrowserRemoval = true
                            }
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

    private func removeBrowser(_ browser: ConnectedBrowser, _ confirmation: DeletionConfirmation) async {
        do {
            try await model.api.removeBrowser(id: browser.id, confirmation: confirmation)
            browserError = nil
            await loadDevices()
        } catch {
            browserError = error.localizedDescription
        }
        browserToRemove = nil
    }

    private func browserTint(_ browser: ConnectedBrowser) -> Color {
        guard let tone = browser.status?.tone else { return browser.connected ? EGuardColors.tileTeal : EGuardColors.danger }
        return switch tone {
        case "ok": EGuardColors.success
        case "warn": EGuardColors.warning
        case "crit": EGuardColors.danger
        case "accent": EGuardColors.primary
        default: EGuardColors.neutral
        }
    }
}

/// A device's tint: waiting for its first check is neutral, not "issues".
func deviceTint(_ device: APIDevice) -> Color {
    if device.state != .offline, device.firstCheck == true { return EGuardColors.neutral }
    return switch device.state {
    case .healthy: EGuardColors.success
    case .issues: EGuardColors.warning
    case .offline: EGuardColors.neutral
    }
}

/// Device detail: `GET /devices/{id}` with rename, make primary, move to another child and unpair, as on the web.
struct DeviceDetailView: View {
    let deviceId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<DeviceDetail> = .loading
    @State private var isRenaming = false
    @State private var newName = ""
    /// Remove: first keep or delete what it recorded, then the password.
    @State private var isChoosingRemoval = false
    @State private var deleteHistory = false
    @State private var isConfirmingUnpair = false
    /// Move: first the child, then the password.
    @State private var isChoosingChild = false
    @State private var moveTarget: ChildSummary?
    @State private var isBusy = false
    @State private var notice: String?
    @State private var error: String?

    /// The family's other children, from the dashboard.
    private var otherChildren: [ChildSummary] {
        guard let childId = state.value?.childId else { return [] }
        return model.children.filter { $0.id != childId }
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
                            StatusPill(text: detail.device.statusTitle, tint: deviceTint(detail.device))
                        }
                        Spacer()
                    }
                    Divider()
                    EGuardValueRow(label: "Child", value: detail.childName)
                    if detail.isPrimary {
                        Text("\(detail.childName)'s primary device: listed first and shown on their card.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                    EGuardValueRow(label: "eGuard version", value: detail.appVersion ?? "Unknown")
                    EGuardValueRow(label: "Last seen", value: detail.lastSeenLabel ?? "Never")
                    if let battery = detail.battery { EGuardValueRow(label: "Battery", value: "\(battery)%") }
                    if detail.state == .offline {
                        Text("This device hasn't synced in over a day. Its protections show their last known state until it reconnects.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.warning)
                    }
                }

                EGuardCard {
                    SectionHeader(title: "Protections on this device")
                    ForEach(detail.protections) { protection in
                        Button {
                            router.push(.protectionEditor(childId: detail.childId, key: protection.key))
                        } label: {
                            HStack {
                                ChecklistRow(title: protection.name, detail: protection.message ?? protection.reportedLabel, status: protection.displayStatus)
                                if protection.capability == .parentSet {
                                    // Set in Google Play by the parent: "Set by you" or "Not set up yet", never "Not supported"
                                    StatusPill(text: protection.statusTitle, tint: EGuardTheme.color(for: protection.displayStatus))
                                } else {
                                    ModeBadge(mode: protection.capability.mode)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(protection.capability == .unsupported)
                        if protection.id != detail.protections.last?.id { Divider() }
                    }
                }
                if let notice {
                    Text(notice)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.success)
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
                .disabled(isBusy)
                // A child's only device is already primary, so this shows only when they have another
                if !detail.isPrimary {
                    Button("Make Primary Device") { Task { await makePrimary() } }
                        .buttonStyle(.eGuardSecondary)
                        .disabled(isBusy)
                }
                if !otherChildren.isEmpty {
                    Button("Move to Another Child") { isChoosingChild = true }
                        .buttonStyle(.eGuardSecondary)
                        .disabled(isBusy)
                }
                Button("Remove Device", role: .destructive) { isChoosingRemoval = true }
                    .buttonStyle(.eGuardText)
                    .disabled(isBusy)
                    .accessibilityIdentifier("device.remove")
            }
        }
        .navigationTitle(state.value?.name ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDevice() }
        .refreshable { await loadDevice() }
        .alert("Rename device", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") { Task { await rename() } }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newName.count > 60)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("1 to 60 characters.")
        }
        .confirmationDialog("Move \(state.value?.name ?? "this device") to…", isPresented: $isChoosingChild, titleVisibility: .visible) {
            ForEach(otherChildren) { child in
                Button(child.name) {
                    moveTarget = child
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It gets the new child's protections and apps on its next sync, and eGuard checks them again then. What it recorded stays in \(state.value?.childName ?? "the child")'s reports and history.")
        }
        .deletionConfirmation(
            "Move to \(moveTarget?.name ?? "another child")?",
            message: "Other parents in your family are told.",
            confirmTitle: "Move",
            isPresented: Binding(get: { moveTarget != nil }, set: { if !$0 { moveTarget = nil } }),
            user: model.user
        ) { confirmation in
            if let child = moveTarget { Task { await move(to: child, confirmation) } }
        }
        .confirmationDialog("Remove \(state.value?.name ?? "this device")?", isPresented: $isChoosingRemoval, titleVisibility: .visible) {
            Button("Remove, Keep What It Recorded", role: .destructive) {
                deleteHistory = false
                isConfirmingUnpair = true
            }
            Button("Remove and Delete What It Recorded", role: .destructive) {
                deleteHistory = true
                isConfirmingUnpair = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The eGuard app on it stops applying your settings, and eGuard stops checking it. Its screen time, app usage and places can stay in your child's reports and history, or be deleted (that can't be undone).")
        }
        .deletionConfirmation(
            deleteHistory ? "Remove and delete its history?" : "Remove this device?",
            message: "The family gets a \"Device removed\" alert.",
            confirmTitle: "Remove",
            isPresented: $isConfirmingUnpair,
            user: model.user
        ) { confirmation in
            Task { await unpair(confirmation) }
        }
    }

    private func loadDevice() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.device(id: deviceId) }
    }

    private func rename() async {
        await perform { try await model.api.renameDevice(id: deviceId, name: newName.trimmingCharacters(in: .whitespaces)) } done: { _ in "Device renamed." }
    }

    private func makePrimary() async {
        await perform { try await model.api.setPrimaryDevice(id: deviceId) } done: { "Now \($0.childName)'s primary device." }
    }

    private func move(to child: ChildSummary, _ confirmation: DeletionConfirmation) async {
        moveTarget = nil
        await perform { try await model.api.moveDevice(id: deviceId, childId: child.id, confirmation: confirmation) } done: {
            "Moved to \($0.childName). It gets their settings on its next sync."
        }
    }

    /// Runs one change at a time, shows the updated device and refreshes the dashboard (children's device lists).
    private func perform(_ call: () async throws -> DeviceDetail, done: (DeviceDetail) -> String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let detail = try await call()
            state = .loaded(detail)
            error = nil
            notice = done(detail)
            await model.refreshDashboard()
        } catch {
            notice = nil
            self.error = error.localizedDescription
        }
    }

    private func unpair(_ confirmation: DeletionConfirmation) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await model.api.unpairDevice(id: deviceId, confirmation: confirmation, deleteHistory: deleteHistory)
            await model.refreshDashboard()
            router.pop()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DevicesView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
#endif
