import FamilyControls
import SwiftUI
import UserNotifications

/// Child device setup: pairing code → device name → `POST /pair` → permissions → apps to count → done.
/// Pairing happens before permissions so a bad code doesn't waste the permission steps.
struct ChildSetupView: View {
    enum Step: Equatable {
        case code
        case name
        case pairing
        case permissions
        case apps
        case done
    }

    let startStep: Step

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var step: Step
    @State private var code = ""
    @State private var deviceName = DeviceFacts.defaultName
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var selection = FamilyActivitySelection()
    @State private var isPickingApps = false
    @State private var screenTimeGranted = false
    @State private var notificationsGranted = false

    init(startStep: Step) {
        self.startStep = startStep
        _step = State(initialValue: startStep)
    }

    private var childDevice: ChildDeviceModel { model.childDevice }
    private var childName: String { childDevice.session?.childName ?? "your child" }

    var body: some View {
        EGuardScreen {
            switch step {
            case .code: codeStep
            case .name: nameStep
            case .pairing: LoadingCard(message: "Pairing with eGuard…")
            case .permissions: permissionsStep
            case .apps: appsStep
            case .done: doneStep
            }
            InlineError(message: errorMessage)
        } actions: {
            actions
        }
        .navigationTitle("Set up this device")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step != .code && step != .name)
        .toolbar(step == .code || step == .name ? .visible : .hidden, for: .navigationBar)
        .familyActivityPicker(isPresented: $isPickingApps, selection: $selection)
        .onChange(of: selection) { _, newValue in
            childDevice.setScreenTimeSelection(ActivitySelectionCodec.snapshot(from: newValue))
        }
        .task {
            screenTimeGranted = childDevice.enforcer.isAuthorized
            notificationsGranted = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
        }
    }

    // MARK: Steps

    private var codeStep: some View {
        Group {
            EGuardIllustration(symbolName: "qrcode.viewfinder", tint: EGuardColors.tilePurple)
                .frame(maxWidth: .infinity)
            ScreenHeader(
                title: "Enter the pairing code",
                subtitle: "A parent gets an 8-character code in their eGuard app under the child's profile › Set up supervision. Codes last 15 minutes."
            )
            EGuardTextField(label: "Pairing code", placeholder: "K7PQ 2M9X", text: $code, symbolName: "number", autocapitalization: .characters, identifier: "childSetup.code")
            EGuardCard {
                Label("Nobody signs in here. This device will follow the protections a parent chose, and only a parent can remove it from eGuard.", systemImage: "lock.shield")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }

    private var nameStep: some View {
        Group {
            ScreenHeader(title: "Name this device", subtitle: "Parents see this name everywhere, for example \"Mia's iPhone\". Choose it now: it can't be changed from this device later.")
            EGuardTextField(label: "Device name", placeholder: "Mia's iPhone", text: $deviceName, symbolName: DeviceFacts.kind == "TABLET" ? "ipad" : "iphone", autocapitalization: .words, identifier: "childSetup.name")
        }
    }

    private var permissionsStep: some View {
        Group {
            ScreenHeader(
                title: "Paired with \(childName)",
                subtitle: "eGuard needs a few permissions to apply \(childName)'s protections on this device."
            )
            EGuardCard {
                permissionRow(
                    title: "Screen Time",
                    detail: "Lets eGuard apply bedtime, screen-time limits, content ratings and App Store rules.",
                    symbol: "hourglass",
                    granted: screenTimeGranted,
                    required: true
                ) { await requestScreenTime() }
                Divider()
                permissionRow(
                    title: "Notifications",
                    detail: "Tells \(childName) when bedtime is about to start or a limit is reached.",
                    symbol: "bell.fill",
                    granted: notificationsGranted,
                    required: false
                ) { await requestNotifications() }
                if childDevice.isLocationSharingRequested || childDevice.state.policy.isEmpty {
                    Divider()
                    permissionRow(
                        title: "Location",
                        detail: "Only while a parent has turned on location sharing. eGuard sends this device's position to the parent's app.",
                        symbol: "location.fill",
                        granted: childDevice.locationReporter.isAuthorized,
                        required: false
                    ) { await childDevice.locationReporter.requestPermission() }
                }
            }
            if !screenTimeGranted {
                Text("Screen Time approval is required. On a child's Apple Account in Family Sharing a parent approves it; otherwise the device owner approves with Face ID or a passcode.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }

    private var appsStep: some View {
        Group {
            ScreenHeader(
                title: "Apps that count toward screen time",
                subtitle: "Apple asks the family to choose which apps and categories the daily allowance applies to. Pick everything \(childName) uses for fun."
            )
            EGuardCard {
                EGuardValueRow(label: "Selected", value: childDevice.state.screenTimeSelection.summary)
                Button("Choose apps and categories") { isPickingApps = true }
                    .buttonStyle(.eGuardSecondary)
                    .accessibilityIdentifier("childSetup.pickApps")
            }
            Text("Bedtime pauses every app regardless. This choice only affects the daily time allowance.")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        }
    }

    private var doneStep: some View {
        Group {
            EGuardIllustration(symbolName: "checkmark.shield.fill", tint: EGuardColors.success)
                .frame(maxWidth: .infinity)
            ScreenHeader(title: "You're all set", subtitle: "\(childName)'s protections are on this device now. eGuard checks in with the family's settings every few minutes.")
            EGuardCard {
                Text(childDevice.lastSyncDescription)
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }

    private func permissionRow(title: String, detail: String, symbol: String, granted: Bool, required: Bool, request: @escaping () async -> Void) -> some View {
        HStack(alignment: .top, spacing: EGuardSpacing.sm) {
            IconTile(symbolName: symbol, tint: granted ? EGuardColors.success : EGuardColors.primary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(EGuardTypography.label)
                    if required { StatusPill(text: "Required", tint: EGuardColors.warning) }
                }
                Text(detail).font(EGuardTypography.caption).foregroundStyle(EGuardColors.textSecondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(EGuardColors.success)
            } else {
                Button("Allow") { Task { await request() } }
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.primary)
                    .disabled(isWorking)
            }
        }
        .padding(.vertical, EGuardSpacing.xxs)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch step {
        case .code:
            Button("Continue") { step = .name }
                .buttonStyle(.eGuardPrimary)
                .disabled(code.filter { $0.isLetter || $0.isNumber }.count != 8)
                .accessibilityIdentifier("childSetup.continue")
        case .name:
            Button(isWorking ? "Pairing…" : "Pair this device") { Task { await pair() } }
                .buttonStyle(.eGuardPrimary)
                .disabled(deviceName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                .accessibilityIdentifier("childSetup.pair")
        case .pairing:
            EmptyView()
        case .permissions:
            Button("Continue") { step = .apps }
                .buttonStyle(.eGuardPrimary)
                .disabled(!screenTimeGranted)
                .accessibilityIdentifier("childSetup.permissionsContinue")
        case .apps:
            Button(childDevice.state.screenTimeSelection.isEmpty ? "Skip for now" : "Finish") { Task { await finish() } }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("childSetup.finish")
        case .done:
            Button("Open eGuard") { childDevice.completeSetup() }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("childSetup.done")
        }
    }

    private func pair() async {
        isWorking = true
        step = .pairing
        defer { isWorking = false }
        do {
            _ = try await childDevice.pair(code: code, deviceName: deviceName)
            // Any parent session on this phone ends now; the install is the child's from here on.
            await model.enterChildMode()
            errorMessage = nil
            await childDevice.syncNow()
            step = .permissions
        } catch let error as DeviceAPIError {
            errorMessage = Self.pairingMessage(for: error)
            step = .code
        } catch {
            errorMessage = error.localizedDescription
            step = .code
        }
    }

    /// The spec's wording for each pairing failure. The typed code is kept so it can be corrected.
    static func pairingMessage(for error: DeviceAPIError) -> String {
        switch error.status {
        case 400 where error.localizedDescription.localizedCaseInsensitiveContains("browser"):
            return error.localizedDescription
        case 400:
            return "That code didn't work. Codes last 15 minutes and only the newest one works. Ask for a new code."
        case 409:
            return "No free device slots. A parent can remove a device, then use the same code."
        case 429:
            return "Too many attempts. Wait a few minutes and try again."
        default:
            return error.localizedDescription
        }
    }

    private func requestScreenTime() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await childDevice.enforcer.requestAuthorization()
            screenTimeGranted = childDevice.enforcer.isAuthorized
            errorMessage = screenTimeGranted ? nil : "Screen Time approval wasn't granted. Try again."
            await childDevice.syncNow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        notificationsGranted = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    private func finish() async {
        await childDevice.syncNow()
        step = .done
    }
}

#Preview {
    NavigationStack {
        ChildSetupView(startStep: .code)
    }
    .environment(AppModel.mock(mode: .unset))
    .environment(AppRouter())
}
