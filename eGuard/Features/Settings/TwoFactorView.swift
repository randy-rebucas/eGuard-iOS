import SwiftUI
import UniformTypeIdentifiers

/// Two-step verification: `GET /me/two-factor`, setup, confirm, recovery codes, and turn off.
struct TwoFactorView: View {
    private enum Stage: Equatable {
        case status
        case setup(TwoFactorSetup)
        case recoveryCodes([String], isNew: Bool)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    /// The app switcher snapshots the screen as the app leaves: the key and codes are hidden unless it's active.
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: LoadState<TwoFactorStatus> = .loading
    @State private var stage: Stage = .status
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var isAskingCode: CodePurpose?
    @State private var copied = false

    private enum CodePurpose: Identifiable {
        case regenerate, disable
        var id: Int { self == .regenerate ? 0 : 1 }
    }

    var body: some View {
        EGuardScreen {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadStatus() } }
            case .loaded(let status):
                content(status)
            }
            InlineError(message: errorMessage)
        } actions: {
            actions
        }
        .navigationTitle("Two-step verification")
        .navigationBarTitleDisplayMode(.inline)
        // Shown once: leaving by Back would lose them, so "I've saved them" is the way out
        .navigationBarBackButtonHidden(isShowingCodes)
        // Belt and braces with the masked values above: a plain cover over the whole screen while the key
        // or codes are up and the app isn't active, so the app-switcher snapshot shows neither.
        .overlay {
            if isShowingSecrets && scenePhase != .active {
                EGuardColors.background
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
        .task { await loadStatus() }
        .alert(isAskingCode == .disable ? "Turn off two-step verification?" : "Make new recovery codes?", isPresented: Binding(get: { isAskingCode != nil }, set: { if !$0 { isAskingCode = nil } })) {
            TextField("Authenticator or recovery code", text: $code)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
            Button(isAskingCode == .disable ? "Turn Off" : "Make New Codes", role: isAskingCode == .disable ? .destructive : nil) {
                let purpose = isAskingCode
                isAskingCode = nil
                Task { await purpose == .disable ? disable() : regenerate() }
            }
            Button("Cancel", role: .cancel) { code = "" }
        } message: {
            Text(isAskingCode == .disable ? "Signing in will only need your password again." : "Your old recovery codes stop working.")
        }
    }

    @ViewBuilder
    private func content(_ status: TwoFactorStatus) -> some View {
        switch stage {
        case .status:
            EGuardIllustration(symbolName: "lock.shield.fill", tint: status.enabled ? EGuardColors.success : EGuardColors.primary)
                .frame(maxWidth: .infinity)
            ScreenHeader(
                title: status.enabled ? "Two-step verification is on" : "Add a second step",
                subtitle: status.enabled
                    ? "Signing in needs your password and a code from your authenticator app."
                    : "After your password, you'll enter a 6-digit code from an authenticator app such as Google Authenticator or Authy."
            )
            if !status.available {
                EGuardCard {
                    Label("Not available on this server yet", systemImage: "info.circle.fill")
                        .font(EGuardTypography.headline)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            } else if status.enabled {
                EGuardCard {
                    EGuardValueRow(label: "Recovery codes left", value: "\(status.recoveryCodesLeft ?? 0)")
                    if (status.recoveryCodesLeft ?? 0) <= 2 {
                        Text("You're running low. Make new codes and keep them somewhere safe.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.warning)
                    }
                }
            }

        case .setup(let setup):
            ScreenHeader(title: "Set up your authenticator", subtitle: "Open your authenticator app and add eGuard, then enter the 6-digit code it shows.")
            EGuardCard {
                SectionHeader(title: "Setup key")
                Text(scenePhase == .active ? setup.secret : String(repeating: "•", count: 16))
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .textSelection(.enabled)
                    .privacySensitive()
                    .accessibilityIdentifier("twoFactor.secret")
                HStack(spacing: EGuardSpacing.sm) {
                    Button(copied ? "Copied" : "Copy key") {
                        Self.copySecret(setup.secret)
                        copied = true
                    }
                    .buttonStyle(.eGuardSecondary)
                    if let url = URL(string: setup.uri) {
                        Button("Open in authenticator") { openURL(url) }
                            .buttonStyle(.eGuardSecondary)
                    }
                }
                Text("Type the key by hand, or open the link to hand it to an authenticator app on this phone.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            EGuardTextField(label: "Code from the app", placeholder: "123456", text: $code, symbolName: "number", contentType: .oneTimeCode, keyboard: .numberPad, identifier: "twoFactor.setupCode")

        case .recoveryCodes(let codes, let isNew):
            ScreenHeader(
                title: isNew ? "Two-step verification is on" : "Your new recovery codes",
                subtitle: "Save these recovery codes somewhere safe. Each works once if you lose your authenticator. They're shown only now."
            )
            EGuardCard {
                ForEach(codes, id: \.self) { recovery in
                    Text(scenePhase == .active ? recovery : "••••-••••-••••")
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .textSelection(.enabled)
                        .privacySensitive()
                }
                Button(copied ? "Copied" : "Copy all codes") {
                    Self.copySecret(codes.joined(separator: "\n"))
                    copied = true
                }
                .buttonStyle(.eGuardSecondary)
            }
            .accessibilityIdentifier("twoFactor.recoveryCodes")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let status = state.value {
            switch stage {
            case .status:
                if status.available {
                    if status.enabled {
                        Button(isWorking ? "Checking…" : "Make New Recovery Codes") { isAskingCode = .regenerate }
                            .buttonStyle(.eGuardSecondary)
                            .disabled(isWorking)
                        Button("Turn Off") { isAskingCode = .disable }
                            .buttonStyle(.eGuardText)
                            .disabled(isWorking)
                    } else {
                        Button(isWorking ? "Starting…" : "Turn On") { Task { await startSetup() } }
                            .buttonStyle(.eGuardPrimary)
                            .disabled(isWorking)
                            .accessibilityIdentifier("twoFactor.turnOn")
                    }
                }
            case .setup:
                Button(isWorking ? "Checking…" : "Verify and Turn On") { Task { await confirm() } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(code.trimmingCharacters(in: .whitespaces).count != 6 || isWorking)
                    .accessibilityIdentifier("twoFactor.confirm")
                Button("Cancel") { stage = .status; code = "" }
                    .buttonStyle(.eGuardText)
            case .recoveryCodes:
                Button("I've saved them") {
                    stage = .status
                    copied = false
                    Task { await loadStatus() }
                }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("twoFactor.saved")
            }
        }
    }

    private func loadStatus() async {
        state = await load { try await model.api.twoFactorStatus() }
    }

    private func startSetup() async {
        isWorking = true
        defer { isWorking = false }
        do {
            stage = .setup(try await model.api.setupTwoFactor())
            copied = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirm() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let codes = try await model.api.confirmTwoFactor(code: code.trimmingCharacters(in: .whitespaces))
            code = ""
            copied = false
            stage = .recoveryCodes(codes, isNew: true)
            errorMessage = nil
            await model.refreshUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var isShowingCodes: Bool {
        if case .recoveryCodes = stage { return true }
        return false
    }

    /// The setup key or recovery codes are on screen.
    private var isShowingSecrets: Bool {
        stage != .status
    }

    /// Copied for this phone only (not Universal Clipboard) and gone after two minutes.
    private static func copySecret(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
    }

    private func regenerate() async {
        isWorking = true
        defer { code = ""; isWorking = false }
        do {
            let codes = try await model.api.regenerateRecoveryCodes(code: code.trimmingCharacters(in: .whitespaces))
            copied = false
            stage = .recoveryCodes(codes, isNew: false)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disable() async {
        isWorking = true
        defer { code = ""; isWorking = false }
        do {
            state = .loaded(try await model.api.disableTwoFactor(code: code.trimmingCharacters(in: .whitespaces)))
            errorMessage = nil
            await model.refreshUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TwoFactorView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
#endif
