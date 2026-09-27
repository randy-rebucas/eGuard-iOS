import AuthenticationServices
import Observation
import SwiftUI

/// Validates the sign-up form and creates the local account.
@Observable
final class CreateAccountViewModel {
    var fullName = ""
    var email = ""
    var password = ""
    var errorMessage: String?
    var isShowingGoogleNotice = false

    var validationMessage: String? {
        AccountValidator.validateName(fullName)
            ?? AccountValidator.validateEmail(email)
            ?? AccountValidator.validatePassword(password)
    }

    var canSubmit: Bool { validationMessage == nil }

    func submit(to model: AppModel) -> Bool {
        guard canSubmit else {
            errorMessage = validationMessage
            return false
        }
        model.createAccount(AccountValidator.makeEmailAccount(fullName: fullName, email: email, password: password))
        errorMessage = nil
        return true
    }

    func handleApple(_ result: Result<ASAuthorization, Error>, model: AppModel) -> Bool {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = AccountError.providerUnavailable(.apple).localizedDescription
                return false
            }
            let formatter = PersonNameComponentsFormatter()
            let name = credential.fullName.map { formatter.string(from: $0) }
            model.signIn(provider: .apple, fullName: name, email: credential.email)
            return true
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return false }
            errorMessage = AccountError.providerUnavailable(.apple).localizedDescription
            return false
        }
    }
}

/// 03 Create Account
struct CreateAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = CreateAccountViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen(showsActionBackground: false) {
            AccountStepProgress(fraction: 0.15)

            ScreenHeader(
                title: "Create your account",
                subtitle: "Start your family's digital safety journey today."
            )

            VStack(spacing: EGuardSpacing.sm) {
                EGuardTextField(
                    label: "Full name",
                    placeholder: "Randy Cruz",
                    text: $viewModel.fullName,
                    symbolName: "person",
                    contentType: .name,
                    autocapitalization: .words,
                    identifier: "account.name"
                )
                EGuardTextField(
                    label: "Email address",
                    placeholder: "randy@example.com",
                    text: $viewModel.email,
                    symbolName: "envelope",
                    contentType: .emailAddress,
                    keyboard: .emailAddress,
                    identifier: "account.email"
                )
                EGuardTextField(
                    label: "Password",
                    placeholder: "At least 8 characters",
                    text: $viewModel.password,
                    symbolName: "lock",
                    isSecure: true,
                    identifier: "account.password"
                )
            }

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.danger)
                    .accessibilityIdentifier("account.error")
            }

            Button("Create account") {
                if viewModel.submit(to: model) {
                    router.push(.childDevice)
                }
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("account.create")

            orDivider

            VStack(spacing: EGuardSpacing.sm) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    if viewModel.handleApple(result, model: model) {
                        router.push(.childDevice)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(EGuardShapes.button)
                .accessibilityIdentifier("account.apple")

                Button {
                    viewModel.isShowingGoogleNotice = true
                } label: {
                    Label {
                        Text("Continue with Google")
                    } icon: {
                        Image(systemName: "g.circle.fill")
                            .foregroundStyle(EGuardColors.danger)
                    }
                    .font(EGuardTypography.headline)
                    .foregroundStyle(EGuardColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(EGuardColors.surface, in: EGuardShapes.button)
                    .overlay(EGuardShapes.button.strokeBorder(EGuardColors.divider))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.google")
            }

            EGuardCard {
                Label("Your account is stored securely on this device only. eGuard has no servers and never uploads family information.", systemImage: "lock.shield")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            HStack(spacing: EGuardSpacing.xxs) {
                Text("Already have an account?")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
                Button("Sign in") { router.push(.signIn) }
                    .buttonStyle(.eGuardText)
                    .accessibilityIdentifier("account.signIn")
            }
        }
        .brandNavigationTitle()
        .alert("Google sign-in not configured", isPresented: $viewModel.isShowingGoogleNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Google sign-in needs the Google Sign-In SDK and a client ID. Use email or Apple for now.")
        }
    }

    private var orDivider: some View {
        HStack(spacing: EGuardSpacing.sm) {
            Rectangle().fill(EGuardColors.divider).frame(height: 1)
            Text("or continue with")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
            Rectangle().fill(EGuardColors.divider).frame(height: 1)
        }
    }
}

/// A thin bar showing where the parent is in the account steps.
struct AccountStepProgress: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(EGuardColors.primary.opacity(0.15))
                Capsule().fill(EGuardColors.primary).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
