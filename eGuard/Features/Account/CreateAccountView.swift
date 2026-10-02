import AuthenticationServices
import Observation
import SwiftUI

/// Validates the sign-up form and registers the parent on the server.
@Observable
final class CreateAccountViewModel {
    var fullName = ""
    var email = ""
    var password = ""
    var isGuardian = false
    var errorMessage: String?
    var highlightedField: String?
    var isSubmitting = false
    var isShowingGoogleNotice = false

    var validationMessage: String? {
        AccountValidator.validateName(fullName)
            ?? AccountValidator.validateEmail(email)
            ?? AccountValidator.validatePassword(password)
            ?? (isGuardian ? nil : "Confirm that you're a parent or legal guardian, 18 or older.")
    }

    var canSubmit: Bool { validationMessage == nil && !isSubmitting }

    /// Creates the account. Returns true when the app should continue to Add Child.
    func submit(model: AppModel) async -> Bool {
        guard canSubmit else {
            errorMessage = validationMessage
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await model.register(name: fullName, email: email, password: password)
            errorMessage = nil
            return true
        } catch let error as APIError {
            highlightedField = error.fieldName
            errorMessage = error.code == "conflict"
                ? "That email already has an eGuard account. Sign in instead."
                : error.localizedDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// A two-step challenge from Apple sign-in on an account that has it on.
    var twoFactorChallenge: TwoFactorChallenge?
    /// Fresh for every Apple request; its hash goes in the request, the raw value to the server.
    var appleNonce = AppleNonce()

    /// Continue with Apple. The guardian checkbox on this form is the confirmation a new account needs.
    func handleApple(_ result: Result<ASAuthorization, Error>, model: AppModel) async -> Bool {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = AccountError.providerUnavailable(.apple).localizedDescription
                return false
            }
            let formatter = PersonNameComponentsFormatter()
            let name = credential.fullName.map { formatter.string(from: $0) }
            do {
                isSubmitting = true
                defer { isSubmitting = false }
                switch try await model.signInWithApple(identityToken: token, fullName: name, nonce: appleNonce, guardianConfirmed: isGuardian) {
                case .signedIn:
                    return true
                case .twoFactorRequired(let challenge):
                    twoFactorChallenge = challenge
                    return false
                }
            } catch let error as APIError where error.code == "guardian_required" {
                errorMessage = AccountError.guardianRequired.localizedDescription
                return false
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
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

    private var signInOptions: AppInfo.SignInOptions {
        model.appInfo?.signIn ?? AppInfo.SignInOptions(password: true, apple: true, google: false)
    }

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
                    placeholder: "At least 10 characters",
                    text: $viewModel.password,
                    symbolName: "lock",
                    isSecure: true,
                    identifier: "account.password"
                )
            }

            Toggle(isOn: $viewModel.isGuardian) {
                Text("I'm a parent or legal guardian, 18 or older.")
                    .font(EGuardTypography.callout)
            }
            .toggleStyle(CheckboxToggleStyle())
            .accessibilityIdentifier("account.guardian")

            InlineError(message: viewModel.errorMessage)

            Button(viewModel.isSubmitting ? "Creating account…" : "Create account") {
                Task {
                    if await viewModel.submit(model: model) {
                        router.push(.addChild)
                    }
                }
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("account.create")

            if signInOptions.apple || signInOptions.google {
                orDivider
            }

            VStack(spacing: EGuardSpacing.sm) {
                if signInOptions.apple {
                    SignInWithAppleButton(.continue) { request in
                        viewModel.appleNonce = AppleNonce()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = viewModel.appleNonce.hashed
                    } onCompletion: { result in
                        Task {
                            if await viewModel.handleApple(result, model: model) {
                                // An existing family lands on the dashboard; a new one adds its first child.
                                if model.hasChildren { router.popToRoot() } else { router.push(.addChild) }
                            } else if let challenge = viewModel.twoFactorChallenge {
                                viewModel.twoFactorChallenge = nil
                                router.push(.twoFactorCode(challenge))
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(EGuardShapes.button)
                    .accessibilityIdentifier("account.apple")
                }

                if signInOptions.google {
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
            }

            EGuardCard {
                Label("Children never get accounts. You'll add them after signing up, and we'll email you a verification link.", systemImage: "lock.shield")
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
            Text("Google sign-in needs the Google Sign-In SDK and a client ID registered with the eGuard server. Use email or Apple for now.")
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

/// A checkbox-style toggle for confirmations.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: EGuardSpacing.sm) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? EGuardColors.primary : EGuardColors.neutral)
                configuration.label
                    .foregroundStyle(EGuardColors.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
