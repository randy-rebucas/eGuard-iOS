import SwiftUI

/// Everything shown in child device mode: setup until permissions are done, the removed screen after a
/// parent removes the device, the update gate, and otherwise the child's home.
struct ChildDeviceRootView: View {
    @Environment(AppModel.self) private var model
    @State private var router = AppRouter()

    private var childDevice: ChildDeviceModel { model.childDevice }

    var body: some View {
        Group {
            if childDevice.wasRemoved {
                DeviceRemovedView()
            } else if let minimum = childDevice.updateRequired {
                UpdateRequiredView(minimumVersion: minimum)
            } else if !childDevice.isSetupComplete {
                NavigationStack { ChildSetupView(startStep: .permissions) }
            } else {
                NavigationStack { ChildHomeView() }
            }
        }
        .environment(router)
        .tint(EGuardColors.primary)
        .task {
            childDevice.startSyncLoop()
        }
        .onDisappear { childDevice.stopSyncLoop() }
        .alert("Open this on a parent's phone", isPresented: Binding(get: { childDevice.deepLinkNotice != nil }, set: { if !$0 { childDevice.deepLinkNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(childDevice.deepLinkNotice ?? "")
        }
    }
}

/// The child's own screen: which protections are on, when eGuard last checked in, and "Ask a parent".
struct ChildHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isAskingForApp = false
    @State private var appName = ""
    @State private var askResult: String?

    private var childDevice: ChildDeviceModel { model.childDevice }
    private var childName: String { childDevice.session?.childName ?? "you" }

    var body: some View {
        EGuardScreen {
            VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                EGuardWordmark(markSize: 28, showsTagline: false)
                Text("Hi \(childName)")
                    .font(EGuardTypography.display)
                    .foregroundStyle(EGuardColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("This is \(childDevice.session?.deviceName ?? "your device"). A parent manages its protections from their own eGuard app.")
                    .font(EGuardTypography.body)
                    .foregroundStyle(EGuardColors.textSecondary)
            }

            syncCard

            protectionsCard

            if !childDevice.isLocationSharingRequested {
                EmptyView()
            } else if childDevice.locationReporter.isAuthorized {
                EGuardCard {
                    Label("Location sharing is on", systemImage: "location.fill")
                        .font(EGuardTypography.headline)
                        .foregroundStyle(EGuardColors.success)
                    Text("Your parent can see where this device is while eGuard checks in.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            } else {
                EGuardCard {
                    Label("Your parent turned on location sharing", systemImage: "location.slash")
                        .font(EGuardTypography.headline)
                        .foregroundStyle(EGuardColors.warning)
                    Text("Allow location access so eGuard can share where this device is.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                    Button(childDevice.locationReporter.isUndetermined ? "Allow location" : "Open Settings") {
                        Task {
                            if childDevice.locationReporter.isUndetermined {
                                await childDevice.locationReporter.requestPermission()
                                await childDevice.syncNow()
                            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                await UIApplication.shared.open(url)
                            }
                        }
                    }
                    .buttonStyle(.eGuardSecondary)
                }
            }

            if let askResult {
                EGuardCard {
                    Label(askResult, systemImage: "paperplane.fill")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.primary)
                }
            }

            EGuardCard {
                Label("Only a parent can change these settings or remove this device, from their phone or at eguard.family.", systemImage: "lock.shield")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            Button("Ask a parent for an app") { isAskingForApp = true }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("childHome.askApp")
        }
        .background(EGuardColors.heroGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await childDevice.syncNow() }
        .alert("Ask a parent for an app", isPresented: $isAskingForApp) {
            TextField("App name", text: $appName)
            Button("Ask") { Task { await ask() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type the app's name exactly as it appears on the App Store. Your parent gets a request to approve it.")
        }
    }

    private var syncCard: some View {
        EGuardCard {
            HStack(spacing: EGuardSpacing.sm) {
                IconTile(symbolName: syncSymbol, tint: syncTint, filled: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("eGuard check-in").font(EGuardTypography.label)
                    Text(childDevice.lastSyncDescription)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                Spacer()
                Button("Check now") { Task { await childDevice.syncNow() } }
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.primary)
                    .disabled(childDevice.syncState == .syncing)
                    .accessibilityIdentifier("childHome.sync")
            }
        }
        .accessibilityIdentifier("childHome.syncCard")
    }

    private var syncSymbol: String {
        switch childDevice.syncState {
        case .syncing: "arrow.triangle.2.circlepath"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        default: "checkmark.shield.fill"
        }
    }

    private var syncTint: Color {
        switch childDevice.syncState {
        case .offline: EGuardColors.warning
        case .failed: EGuardColors.danger
        default: EGuardColors.success
        }
    }

    private var protectionsCard: some View {
        let statuses = childDevice.protectionStatuses()
        return VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Protections on this device")
            EGuardCard {
                if statuses.isEmpty {
                    Text(childDevice.enforcer.isAuthorized ? "Waiting for the family's settings…" : "Screen Time approval is needed before protections can apply.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                ForEach(statuses) { status in
                    HStack(spacing: EGuardSpacing.sm) {
                        IconTile(symbolName: ProtectionKey.symbol(status.key), tint: LucideIcon.tint(forKey: status.key))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.name).font(EGuardTypography.label)
                            Text(status.policyLabel)
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                        }
                        Spacer()
                        if status.isMatching {
                            StatusPill(text: "On", tint: EGuardColors.success)
                        } else if status.capability == .guided || status.capability == .verifyOnly {
                            StatusPill(text: "Set in Settings", tint: EGuardColors.warning)
                        } else {
                            StatusPill(text: "Applying…", tint: EGuardColors.neutral)
                        }
                    }
                    .padding(.vertical, EGuardSpacing.xxs)
                    .accessibilityIdentifier("childHome.protection.\(status.key.lowercased())")
                    if status.id != statuses.last?.id { Divider() }
                }
            }
        }
    }

    private func ask() async {
        let name = appName.trimmingCharacters(in: .whitespaces)
        appName = ""
        guard !name.isEmpty else { return }
        do {
            switch try await childDevice.requestApp(named: name) {
            case .allowed?, .alwaysAllowed?, .filtered?:
                askResult = "\(name) is already allowed. You can use it."
            case .blocked?:
                askResult = "Your parent said no to \(name) for now."
            default:
                askResult = "We asked your parent about \(name). You'll be able to use it once they approve."
            }
        } catch {
            askResult = "We'll send your request for \(name) as soon as eGuard is back online."
        }
    }
}

/// Shown after a parent removes this device. Nothing from the device's past is kept.
struct DeviceRemovedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            EGuardColors.heroGradient.ignoresSafeArea()
            VStack(spacing: EGuardSpacing.lg) {
                EGuardLogoMark(size: 96)
                Text("This device was removed from eGuard by your parent.")
                    .font(EGuardTypography.title)
                    .multilineTextAlignment(.center)
                Text("Its protections were cleared and nothing from it is kept. A parent can pair it again with a new code.")
                    .font(EGuardTypography.body)
                    .foregroundStyle(EGuardColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Set up eGuard again") { model.leaveChildMode() }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("removed.setUpAgain")
            }
            .padding(EGuardSpacing.xl)
        }
    }
}

#Preview {
    ChildDeviceRootView()
        .environment(AppModel.mock(mode: .child))
}
