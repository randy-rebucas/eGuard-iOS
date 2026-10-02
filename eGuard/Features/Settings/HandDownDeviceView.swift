import SwiftUI

/// Settings › Set up this device for a child: a parent hands down the phone they're holding.
/// Pairs with a code from the parent API, then signs the parent out and switches the install to child mode.
struct HandDownDeviceView: View {
    private enum Stage: Equatable {
        case chooseChild
        case confirm
        case name
        case pairing
    }

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var stage: Stage = .chooseChild
    @State private var child: ChildSummary?
    @State private var deviceName = DeviceFacts.defaultName
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var needsVerification = false

    var body: some View {
        EGuardScreen {
            switch stage {
            case .chooseChild:
                ScreenHeader(title: "Whose device will this be?", subtitle: "Handing down this phone or tablet? Choose the child who'll use it.")
                EGuardCard {
                    ForEach(model.children) { candidate in
                        SelectableOptionRow(title: candidate.name, subtitle: candidate.ageDescription, symbolName: "person.fill", tint: statusTint(candidate.status), isSelected: child?.id == candidate.id) {
                            child = candidate
                        }
                    }
                }
            case .confirm:
                EGuardIllustration(symbolName: "arrow.triangle.swap", tint: EGuardColors.tilePurple)
                    .frame(maxWidth: .infinity)
                ScreenHeader(title: "Make this \(child?.name ?? "your child")'s device?", subtitle: "You'll be signed out of eGuard on this device. It will become \(child?.name ?? "your child")'s device and can only be changed back by removing it from eGuard on another phone or on the web.")
                VerifyEmailBanner()
                if needsVerification {
                    Text("Verify your email first, then try again.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.warning)
                }
            case .name:
                ScreenHeader(title: "Name this device", subtitle: "You'll see this name in your eGuard app, for example \"\(child?.name ?? "Mia")'s iPhone\".")
                EGuardTextField(label: "Device name", placeholder: "\(child?.name ?? "Mia")'s iPhone", text: $deviceName, symbolName: DeviceFacts.kind == "TABLET" ? "ipad" : "iphone", autocapitalization: .words, identifier: "handDown.name")
            case .pairing:
                LoadingCard(message: "Pairing and signing you out…")
            }
            InlineError(message: errorMessage)
        } actions: {
            switch stage {
            case .chooseChild:
                Button("Continue") { stage = .confirm }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(child == nil)
                    .accessibilityIdentifier("handDown.continue")
            case .confirm:
                Button("Continue") {
                    if let child { deviceName = "\(child.name)'s \(DeviceFacts.defaultName)" }
                    stage = .name
                }
                .buttonStyle(.eGuardPrimary)
                .disabled(model.user?.isEmailVerified == false)
                .accessibilityIdentifier("handDown.confirm")
                Button("Cancel") { router.pop() }
                    .buttonStyle(.eGuardText)
            case .name:
                Button(isWorking ? "Pairing…" : "Pair and switch to child mode") { Task { await pair() } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(deviceName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                    .accessibilityIdentifier("handDown.pair")
            case .pairing:
                EmptyView()
            }
        }
        .navigationTitle("Set up for a child")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if child == nil, model.children.count == 1 { child = model.children.first }
        }
    }

    /// Code from the parent API, pair with the device API, then end the parent session. If pairing fails
    /// the parent stays signed in. If sign-out fails (offline) the token is still deleted locally.
    private func pair() async {
        guard let child else { return }
        isWorking = true
        stage = .pairing
        defer { isWorking = false }
        do {
            let code = try await model.api.pairingCode(childId: child.id)
            _ = try await model.childDevice.pair(code: code.code, deviceName: deviceName)
            await model.enterChildMode()
            await model.childDevice.syncNow()
        } catch let error as APIError where error.code == "email_unverified" {
            needsVerification = true
            errorMessage = error.localizedDescription
            stage = .confirm
        } catch let error as DeviceAPIError {
            errorMessage = ChildSetupView.pairingMessage(for: error)
            stage = .name
        } catch {
            errorMessage = error.localizedDescription
            stage = .name
        }
    }
}

#Preview {
    NavigationStack {
        HandDownDeviceView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
