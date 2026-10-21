import AuthenticationServices
import Observation
import SwiftUI

/// Validates the sign-up form and starts the sign-up on the server, which emails a 6-digit code.
@Observable
final class CreateAccountViewModel {
    var fullName = ""
    var email = ""
    var password = ""
    var isGuardian = false
    var errorMessage: String?
    var highlightedField: String?
    var isSubmitting = false

    var validationMessage: String? {
        AccountValidator.validateName(fullName)
            ?? AccountValidator.validateEmail(email)
            ?? AccountValidator.validatePassword(password)
            ?? (isGuardian ? nil : "Confirm that you're a parent or legal guardian, 18 or older.")
    }

    var canSubmit: Bool { validationMessage == nil && !isSubmitting }

    /// Step 1: sends the form, and the server emails a code. Returns the sign-up to finish on the code screen, or nil
    /// with `errorMessage` set. The answer doesn't say whether the email already has an account: that inbox gets a
    /// "you already have an account" email instead of a code.
    func submit(model: AppModel) async -> SignupStarted? {
        guard canSubmit else {
            errorMessage = validationMessage
            return nil
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let signup = try await model.register(name: fullName, email: email, password: password)
            errorMessage = nil
            highlightedField = nil
            return signup
        } catch let error as APIError {
            // Field messages, and the "appeared in a data breach" password message, are shown as the server words them
            highlightedField = error.fieldName
            errorMessage = error.localizedDescription
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
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
                    if let signup = await viewModel.submit(model: model) {
                        router.push(.signupCode(signup))
                    }
                }
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("account.create")

            // Google isn't offered: the app has no Google Sign-In SDK, so the button could only say "not available"
            if signInOptions.apple {
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
            }

            EGuardCard {
                Label("Children never get accounts. You'll add them after signing up. We'll email you a code to confirm your address.", systemImage: "lock.shield")
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

/// Create Account, step 2: the 6-digit code from the email (`POST /auth/register/verify`), and "Send a new code"
/// (`POST /auth/register/resend`). The `signup` ticket stays in memory only.
@Observable
final class SignupCodeViewModel {
    private(set) var signup: SignupStarted
    var code = ""
    var errorMessage: String?
    var notice: String?
    var isSubmitting = false
    var isResending = false
    /// The server's reason the sign-up ended (expired, used up, or out of tries): the form has to be filled in again.
    var endedMessage: String?
    /// The email got an account in the minutes between the steps (`409`): sign in instead.
    var accountExists = false

    init(signup: SignupStarted) {
        self.signup = signup
    }

    var isEnded: Bool { endedMessage != nil }
    var canSubmit: Bool { code.count == 6 && !isSubmitting && !isEnded && !accountExists }

    /// Digits only, at most six: pasted or autofilled codes can carry spaces.
    static func sanitized(_ input: String) -> String {
        String(input.filter(\.isNumber).prefix(6))
    }

    /// Creates the account and signs in. Returns true when the app should continue as after any new sign-up.
    func submit(model: AppModel) async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        notice = nil
        do {
            try await model.completeSignup(signup, code: code)
            errorMessage = nil
            return true
        } catch let error as APIError where error.code == "signup_expired" {
            errorMessage = nil
            endedMessage = error.localizedDescription
        } catch let error as APIError where error.code == "conflict" {
            errorMessage = error.localizedDescription
            accountExists = true
        } catch {
            // wrong_code included: the message says so, and they can try again
            errorMessage = error.localizedDescription
        }
        return false
    }

    /// "Send a new code". The previous code stops working.
    func resend(model: AppModel) async {
        guard !isResending, !isEnded else { return }
        isResending = true
        defer { isResending = false }
        do {
            let sent = try await model.api.resendSignupCode(signup: signup.signup)
            signup.email = sent.email
            signup.expiresAt = sent.expiresAt
            code = ""
            errorMessage = nil
            notice = "We sent a new code to \(sent.email). Earlier codes no longer work."
        } catch let error as APIError where error.code == "signup_expired" {
            errorMessage = nil
            notice = nil
            endedMessage = error.localizedDescription
        } catch {
            notice = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct SignupCodeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel: SignupCodeViewModel

    init(signup: SignupStarted) {
        _viewModel = State(initialValue: SignupCodeViewModel(signup: signup))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            AccountStepProgress(fraction: 0.2)

            ScreenHeader(
                title: "Check your email",
                subtitle: "We sent a 6-digit code to \(viewModel.signup.email). Enter it to finish creating your account."
            )

            EGuardTextField(
                label: "Code",
                placeholder: "123456",
                text: $viewModel.code,
                symbolName: "envelope.badge",
                contentType: .oneTimeCode,
                keyboard: .numberPad,
                identifier: "signupCode.code"
            )
            .onChange(of: viewModel.code) { _, newValue in
                let digits = SignupCodeViewModel.sanitized(newValue)
                if digits != newValue { viewModel.code = digits }
            }

            if let notice = viewModel.notice {
                EGuardCard {
                    Label(notice, systemImage: "envelope.badge.fill")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.success)
                }
                .accessibilityIdentifier("signupCode.sent")
            }

            InlineError(message: viewModel.errorMessage)

            if let ended = viewModel.endedMessage {
                // Back to the form, which still holds what they typed
                ErrorCard(message: ended) { router.pop() }
            }

            if viewModel.accountExists {
                Button("Sign in instead") {
                    router.popToRoot()
                    router.push(.signIn)
                }
                .buttonStyle(.eGuardSecondary)
                .accessibilityIdentifier("signupCode.signIn")
            }

            Button(viewModel.isResending ? "Sending…" : "Send a new code") {
                Task { await viewModel.resend(model: model) }
            }
            .buttonStyle(.eGuardText)
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isResending || viewModel.isEnded || viewModel.accountExists)
            .accessibilityIdentifier("signupCode.resend")
        } actions: {
            Button(viewModel.isSubmitting ? "Creating account…" : "Create account") {
                Task {
                    if await viewModel.submit(model: model) {
                        router.push(.addChild)
                    }
                }
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("signupCode.submit")

            Button("Wrong email? Start again") { router.pop() }
                .buttonStyle(.eGuardText)
                .disabled(viewModel.isSubmitting)
                .accessibilityIdentifier("signupCode.startAgain")
        }
        .brandNavigationTitle()
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

#if DEBUG
#Preview {
    NavigationStack {
        CreateAccountView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}

#Preview("Check your email") {
    NavigationStack {
        SignupCodeView(signup: SignupStarted(verificationRequired: true, signup: "preview-ticket", email: "randy@example.com", expiresAt: .now.addingTimeInterval(900)))
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}
#endif
