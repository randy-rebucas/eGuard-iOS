import AuthenticationServices
import SwiftUI

/// Signs into an existing eGuard account. Handles two-step verification, lockouts and the
/// parent/guardian confirmation Apple sign-in needs for a brand-new account.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var pendingApple: (token: String, name: String?)?
    @State private var appleNonce = AppleNonce()

    private var showsApple: Bool { model.appInfo?.signIn.apple ?? true }

    var body: some View {
        EGuardScreen(showsActionBackground: false) {
            AccountStepProgress(fraction: 0.15)

            ScreenHeader(
                title: "Welcome back",
                subtitle: "Sign in to continue protecting your family."
            )

            VStack(spacing: EGuardSpacing.sm) {
                EGuardTextField(
                    label: "Email address",
                    placeholder: "randy@example.com",
                    text: $email,
                    symbolName: "envelope",
                    contentType: .emailAddress,
                    keyboard: .emailAddress,
                    identifier: "signIn.email"
                )
                EGuardTextField(
                    label: "Password",
                    placeholder: "Your password",
                    text: $password,
                    symbolName: "lock",
                    isSecure: true,
                    contentType: .password,
                    identifier: "signIn.password"
                )
            }

            InlineError(message: errorMessage)

            Button(isSubmitting ? "Signing in…" : "Sign in") { Task { await signIn() } }
                .buttonStyle(.eGuardPrimary)
                .disabled(email.isEmpty || password.isEmpty || isSubmitting)
                .accessibilityIdentifier("signIn.submit")

            Button("Forgot password?") { router.push(.forgotPassword) }
                .buttonStyle(.eGuardText)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("signIn.forgot")

            if showsApple {
                SignInWithAppleButton(.signIn) { request in
                    appleNonce = AppleNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = appleNonce.hashed
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(EGuardShapes.button)
            }
        } actions: {
            HStack(spacing: EGuardSpacing.xxs) {
                Text("New to eGuard?")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
                Button("Create account") {
                    router.pop()
                    router.push(.createAccount)
                }
                .buttonStyle(.eGuardText)
            }
        }
        .brandNavigationTitle()
        .confirmationDialog("Are you a parent or legal guardian, 18 or older?", isPresented: Binding(get: { pendingApple != nil }, set: { if !$0 { pendingApple = nil } }), titleVisibility: .visible) {
            Button("Yes, I'm a parent or guardian") {
                guard let pending = pendingApple else { return }
                pendingApple = nil
                Task { await continueWithApple(token: pending.token, name: pending.name, guardianConfirmed: true) }
            }
            Button("Cancel", role: .cancel) { pendingApple = nil }
        } message: {
            Text("Children never get eGuard accounts. This creates a parent account and a new family.")
        }
    }

    private func signIn() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            handle(try await model.signIn(email: email, password: password))
        } catch let error as APIError where error.code == "rate_limited" {
            errorMessage = error.localizedDescription + " You can also reset your password, which lifts the lock."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let authorization) = result else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = AccountError.providerUnavailable(.apple).localizedDescription
            }
            return
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
            errorMessage = AccountError.providerUnavailable(.apple).localizedDescription
            return
        }
        let formatter = PersonNameComponentsFormatter()
        await continueWithApple(token: token, name: credential.fullName.map { formatter.string(from: $0) }, guardianConfirmed: false)
    }

    private func continueWithApple(token: String, name: String?, guardianConfirmed: Bool) async {
        do {
            handle(try await model.signInWithApple(identityToken: token, fullName: name, nonce: appleNonce, guardianConfirmed: guardianConfirmed))
        } catch let error as APIError where error.code == "guardian_required" {
            // A new account: ask the question, then retry the same token.
            pendingApple = (token, name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ outcome: AppModel.SignInOutcome) {
        switch outcome {
        case .signedIn: finish()
        case .twoFactorRequired(let challenge): router.push(.twoFactorCode(challenge))
        }
    }

    /// Existing families land on the dashboard; a family with no children continues to Add Child.
    /// If the dashboard couldn't load, Welcome shows the error with a retry instead of assuming no children.
    private func finish() {
        if model.hasChildren || model.dashboard == nil {
            router.popToRoot()
        } else {
            router.push(.addChild)
        }
    }
}

#Preview {
    NavigationStack {
        SignInView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
