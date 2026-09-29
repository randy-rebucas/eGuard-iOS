import AuthenticationServices
import SwiftUI

/// Signs into an existing eGuard account.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

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

            if showsApple {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
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
    }

    private func signIn() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await model.signIn(email: email, password: password)
            finish()
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
        do {
            try await model.signInWithApple(identityToken: token, fullName: credential.fullName.map { formatter.string(from: $0) })
            finish()
        } catch {
            errorMessage = error.localizedDescription
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
