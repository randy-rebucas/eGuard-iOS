import SwiftUI

/// Profile and login details for the parent's local account.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var fullName = ""
    @State private var email = ""
    @State private var hasLoaded = false
    @State private var isConfirmingSignOut = false

    private var validationMessage: String? {
        AccountValidator.validateName(fullName) ?? AccountValidator.validateEmail(email)
    }

    var body: some View {
        EGuardScreen {
            if let account = model.account {
                VStack(spacing: EGuardSpacing.sm) {
                    AvatarView(name: account.fullName, size: 96)
                    Text(account.fullName)
                        .font(EGuardTypography.title)
                    StatusPill(text: "Signed in with \(account.provider.title)", tint: EGuardColors.primary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: EGuardSpacing.sm) {
                    EGuardTextField(label: "Full name", placeholder: "Your name", text: $fullName, symbolName: "person", contentType: .name, autocapitalization: .words)
                    EGuardTextField(label: "Email address", placeholder: "you@example.com", text: $email, symbolName: "envelope", contentType: .emailAddress, keyboard: .emailAddress)
                        .disabled(account.provider != .email)
                        .opacity(account.provider == .email ? 1 : 0.6)
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.danger)
                }

                EGuardCard {
                    EGuardValueRow(label: "Member since", value: account.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Divider()
                    EGuardValueRow(label: "Stored", value: "On this device only")
                }
            } else {
                EmptyStateView(symbolName: "person.crop.circle.badge.questionmark", title: "Not signed in", message: "Sign in or create an account to manage your profile.")
            }
        } actions: {
            if model.account != nil {
                Button("Save Changes") { model.updateAccount(fullName: fullName, email: email) }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(validationMessage != nil)
                Button("Sign Out") { isConfirmingSignOut = true }
                    .buttonStyle(.eGuardText)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasLoaded, let account = model.account else { return }
            hasLoaded = true
            fullName = account.fullName
            email = account.email
        }
        .confirmationDialog("Sign out of eGuard?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                model.signOut()
                router.popToRoot()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Protections stay active on this device. Sign back in to manage them.")
        }
    }
}

#Preview {
    NavigationStack {
        AccountView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
