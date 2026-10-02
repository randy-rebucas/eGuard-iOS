import SwiftUI

/// `POST /auth/forgot-password`. Also how Apple/Google parents set their first password.
struct ForgotPasswordView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isSending = false

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: "Forgot your password?", subtitle: "We'll email a link to set a new one. It works for one hour.")
            EGuardTextField(label: "Email address", placeholder: "randy@example.com", text: $email, symbolName: "envelope", contentType: .emailAddress, keyboard: .emailAddress, identifier: "forgot.email")
            if let message {
                EGuardCard {
                    Label(message, systemImage: "envelope.badge.fill")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.success)
                }
                .accessibilityIdentifier("forgot.sent")
            }
            InlineError(message: errorMessage)
            EGuardCard {
                Text("Signed up with Apple or Google? This is also how you set a password for your account.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            Button(isSending ? "Sending…" : "Email me a link") { Task { await send() } }
                .buttonStyle(.eGuardPrimary)
                .disabled(AccountValidator.validateEmail(email) != nil || isSending)
                .accessibilityIdentifier("forgot.send")
        }
        .navigationTitle("Reset password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let response = try await model.api.forgotPassword(email: email)
            message = response.message ?? "If an eGuard account uses that address, a link is on its way."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `POST /auth/reset-password`, opened from the emailed link. Signs in with the new session.
struct ResetPasswordView: View {
    let token: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var password = ""
    @State private var confirm = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var validation: String? {
        if let message = AccountValidator.validatePassword(password) { return message }
        if !confirm.isEmpty, confirm != password { return "The passwords don't match." }
        return nil
    }

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: "Choose a new password", subtitle: "Every other device is signed out. This one signs in with the new password.")
            VStack(spacing: EGuardSpacing.sm) {
                EGuardTextField(label: "New password", placeholder: "At least 10 characters", text: $password, symbolName: "lock.rotation", isSecure: true, contentType: .newPassword)
                EGuardTextField(label: "Confirm new password", placeholder: "Repeat the new password", text: $confirm, symbolName: "lock.rotation", isSecure: true, contentType: .newPassword)
            }
            InlineError(message: errorMessage ?? (password.isEmpty ? nil : validation))
        } actions: {
            Button(isSaving ? "Saving…" : "Set password and sign in") { Task { await save() } }
                .buttonStyle(.eGuardPrimary)
                .disabled(validation != nil || confirm.isEmpty || isSaving)
        }
        .navigationTitle("Reset password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch try await model.resetPassword(token: token, password: password) {
            case .signedIn: router.popToRoot()
            case .twoFactorRequired(let challenge): router.push(.twoFactorCode(challenge))
            }
        } catch let error as APIError where error.code == "link_expired" || error.code == "link_invalid" {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `POST /auth/two-factor`: the 6-digit authenticator code, or a recovery code.
struct TwoFactorCodeView: View {
    let challenge: TwoFactorChallenge

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var code = ""
    @State private var usesRecoveryCode = false
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var recoveryNotice: String?

    private var isExpired: Bool { challenge.expiresAt <= .now }

    var body: some View {
        EGuardScreen {
            ScreenHeader(
                title: "Two-step verification",
                subtitle: usesRecoveryCode ? "Enter one of the recovery codes you saved when you turned this on." : "Enter the 6-digit code from your authenticator app."
            )
            EGuardTextField(
                label: usesRecoveryCode ? "Recovery code" : "Authenticator code",
                placeholder: usesRecoveryCode ? "abcd1234" : "123456",
                text: $code,
                symbolName: "lock.shield",
                contentType: .oneTimeCode,
                keyboard: usesRecoveryCode ? .asciiCapable : .numberPad,
                identifier: "twoFactor.code"
            )
            InlineError(message: errorMessage)
            if isExpired {
                ErrorCard(message: "This sign-in expired. Go back and sign in again.") { router.pop() }
            }
            Button(usesRecoveryCode ? "Use an authenticator code instead" : "Use a recovery code") {
                usesRecoveryCode.toggle()
                code = ""
            }
            .buttonStyle(.eGuardText)
            .frame(maxWidth: .infinity)
        } actions: {
            Button(isSubmitting ? "Checking…" : "Continue") { Task { await submit() } }
                .buttonStyle(.eGuardPrimary)
                .disabled(code.trimmingCharacters(in: .whitespaces).count < 6 || isSubmitting || isExpired)
                .accessibilityIdentifier("twoFactor.submit")
        }
        .navigationTitle("Verify it's you")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Recovery code used", isPresented: Binding(get: { recoveryNotice != nil }, set: { if !$0 { recoveryNotice = nil } })) {
            Button("OK") { finish() }
        } message: {
            Text(recoveryNotice ?? "")
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await model.completeTwoFactor(challenge: challenge, code: code.trimmingCharacters(in: .whitespaces))
            if response.usedRecoveryCode == true {
                let left = response.recoveryCodesLeft ?? 0
                recoveryNotice = "That recovery code is used up. \(left) left." + (left <= 2 ? " Make new codes soon under Account › Two-step verification." : "")
            } else {
                finish()
            }
        } catch let error as APIError where error.code == "challenge_expired" {
            errorMessage = error.localizedDescription
            router.pop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() {
        if model.hasChildren || model.dashboard == nil {
            router.popToRoot()
        } else {
            router.push(.addChild)
        }
    }
}

/// `POST /auth/verify-email`, opened from the emailed link.
struct VerifyEmailLinkView: View {
    let token: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<Bool> = .loading

    var body: some View {
        EGuardScreen {
            EGuardIllustration(symbolName: "envelope.badge.shield.half.filled", tint: EGuardColors.success)
                .frame(maxWidth: .infinity)
            switch state {
            case .loading:
                LoadingCard(message: "Verifying your email…")
            case .failed(let message):
                ErrorCard(message: message)
                Text("Ask for a new link from the Verify your email banner, then open the newest one.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            case .loaded:
                ScreenHeader(title: "Email verified", subtitle: "You can now pair your children's devices.")
            }
        } actions: {
            Button("Continue") { router.popToRoot() }
                .buttonStyle(.eGuardPrimary)
                .disabled(state.isLoading)
        }
        .navigationTitle("Verify email")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            state = await load {
                try await model.api.verifyEmail(token: token)
                return true
            }
            if state.value == true, model.isSignedIn { await model.refreshUser() }
        }
    }
}

/// `GET /auth/invite` then `POST /auth/accept-invite` or `/decline-invite`, opened from the emailed link.
struct AcceptInviteView: View {
    let token: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<InvitationPreview> = .loading
    @State private var password = ""
    @State private var confirm = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var declined: String?

    private var validation: String? {
        if let message = AccountValidator.validatePassword(password) { return message }
        if !confirm.isEmpty, confirm != password { return "The passwords don't match." }
        return nil
    }

    var body: some View {
        EGuardScreen {
            switch state {
            case .loading:
                LoadingCard(message: "Opening your invitation…")
            case .failed(let message):
                ErrorCard(message: message)
            case .loaded(let invite):
                if let declined {
                    ScreenHeader(title: "Invitation declined", subtitle: "Nothing about you stays with \(declined).")
                } else {
                    ScreenHeader(title: "Join \(invite.familyName)", subtitle: "\(invite.invitedBy ?? "A family admin") invited you (\(invite.email)) to help manage the family's protections. Choose your own password to accept.")
                    VStack(spacing: EGuardSpacing.sm) {
                        EGuardTextField(label: "Password", placeholder: "At least 10 characters", text: $password, symbolName: "lock", isSecure: true, contentType: .newPassword)
                        EGuardTextField(label: "Confirm password", placeholder: "Repeat the password", text: $confirm, symbolName: "lock", isSecure: true, contentType: .newPassword)
                    }
                    InlineError(message: errorMessage ?? (password.isEmpty ? nil : validation))
                }
            }
        } actions: {
            if declined != nil || state.value == nil {
                Button("Done") { router.popToRoot() }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(state.isLoading)
            } else {
                Button(isWorking ? "Joining…" : "Accept and join") { Task { await accept() } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(validation != nil || confirm.isEmpty || isWorking)
                Button("Decline") { Task { await decline() } }
                    .buttonStyle(.eGuardText)
                    .disabled(isWorking)
            }
        }
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
        .task { state = await load { try await model.api.invitation(token: token) } }
    }

    private func accept() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.acceptInvitation(token: token, password: password)
            router.popToRoot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decline() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await model.api.declineInvitation(token: token)
            declined = result.familyName ?? state.value?.familyName ?? "the family"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
