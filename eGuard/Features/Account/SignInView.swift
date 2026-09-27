import AuthenticationServices
import SwiftUI

/// Signs into the account stored on this device.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?

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

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.danger)
                    .accessibilityIdentifier("signIn.error")
            }

            Button("Sign in") { signIn() }
                .buttonStyle(.eGuardPrimary)
                .disabled(email.isEmpty || password.isEmpty)
                .accessibilityIdentifier("signIn.submit")

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                if case .success(let authorization) = result,
                   let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                    let formatter = PersonNameComponentsFormatter()
                    model.signIn(provider: .apple, fullName: credential.fullName.map { formatter.string(from: $0) }, email: credential.email)
                    finish()
                } else if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                    errorMessage = AccountError.providerUnavailable(.apple).localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(EGuardShapes.button)
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

    private func signIn() {
        do {
            try model.signIn(email: email, password: password)
            finish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() {
        if model.isSetupComplete {
            router.popToRoot()
        } else {
            router.push(.childDevice)
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
