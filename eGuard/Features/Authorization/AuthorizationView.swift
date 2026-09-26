import Observation
import SwiftUI

/// Drives the pre-permission explanation and Apple's authorization request.
@Observable
final class AuthorizationViewModel {
    enum Phase: Equatable {
        case explaining
        case requesting
        case approved
        case denied
        case failed(String)
    }

    private(set) var phase: Phase = .explaining

    func start(model: AppModel) {
        model.refreshAuthorization()
        if model.authorizationStatus.isAuthorized {
            phase = .approved
        } else if model.authorizationStatus == .denied {
            phase = .denied
        }
    }

    func request(model: AppModel) async {
        phase = .requesting
        do {
            try await model.requestAuthorization()
            phase = model.authorizationStatus.isAuthorized ? .approved : .denied
        } catch let error as ParentalControlAuthorizationError {
            phase = error == .canceled ? .denied : .failed(error.localizedDescription)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// Family Controls permission flow with honest handling of every outcome.
struct AuthorizationView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = AuthorizationViewModel()

    var body: some View {
        EGuardScreen {
            switch viewModel.phase {
            case .explaining, .requesting:
                explanation
            case .approved:
                approved
            case .denied:
                denied(message: nil)
            case .failed(let message):
                denied(message: message)
            }
        } actions: {
            actions
        }
        .navigationTitle("Permission")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.start(model: model) }
    }

    // MARK: Content

    private var explanation: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
            EGuardIllustration(symbolName: "hand.raised.fill", size: 104)
                .frame(maxWidth: .infinity)
            ScreenHeader(
                title: "eGuard needs your permission",
                subtitle: "This allows eGuard to configure supported parental controls on this device."
            )
            EGuardCard {
                Label("Your child is not being secretly monitored.", systemImage: "eye.slash.fill")
                    .font(EGuardTypography.headline)
                Text("Apple shows its own approval screen next. \(approverNote)")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            if viewModel.phase == .requesting {
                HStack(spacing: EGuardSpacing.xs) {
                    ProgressView()
                    Text("Waiting for Apple's approval screen…")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
        }
    }

    private var approved: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
            EGuardIllustration(symbolName: "checkmark.seal.fill", tint: EGuardColors.success, size: 104)
                .frame(maxWidth: .infinity)
            ScreenHeader(
                title: "Authorization approved",
                subtitle: "eGuard can now configure supported protections on this device."
            )
            EGuardCard {
                EGuardValueRow(label: "Status", value: model.authorizationStatus.title)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("authorization.approved")
    }

    private func denied(message: String?) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
            EGuardIllustration(symbolName: "xmark.shield.fill", tint: EGuardColors.danger, size: 104)
                .frame(maxWidth: .infinity)
            ScreenHeader(
                title: "Authorization Not Granted",
                subtitle: "eGuard cannot configure these protections until authorization is granted."
            )
            if let message {
                EGuardCard {
                    Label(message, systemImage: "info.circle.fill")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("authorization.denied")
    }

    private var approverNote: String {
        switch model.childProfile?.relationship.memberKind ?? .child {
        case .child: "A parent or guardian in your Family Sharing group approves the request."
        case .individual: "The device owner approves with Face ID, Touch ID, or the device passcode."
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch viewModel.phase {
        case .explaining, .requesting:
            Button("Continue") {
                Task { await viewModel.request(model: model) }
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(viewModel.phase == .requesting)
            .accessibilityIdentifier("authorization.continue")

        case .approved:
            Button("Continue") { router.pop() }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("authorization.done")

        case .denied, .failed:
            Button("Try Again") {
                Task { await viewModel.request(model: model) }
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("authorization.tryAgain")
            Button("Continue Without") { router.pop() }
                .buttonStyle(.eGuardText)
                .accessibilityIdentifier("authorization.continueWithout")
        }
    }
}

#Preview("Explaining") {
    NavigationStack {
        AuthorizationView()
    }
    .environment(AppModel.mock())
    .environment(AppRouter())
}

#Preview("Denied") {
    NavigationStack {
        AuthorizationView()
    }
    .environment(AppModel.mock(authorizationStatus: .denied, authorizationBehavior: .deny))
    .environment(AppRouter())
}
