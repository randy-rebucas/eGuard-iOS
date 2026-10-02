import SwiftUI

/// Profile and login details, from `/me`.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var name = ""
    @State private var email = ""
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isConfirmingEmailChange = false
    @State private var currentPassword = ""
    @State private var isExporting = false
    @State private var exportFile: ExportFile?

    private var validationMessage: String? {
        AccountValidator.validateName(name) ?? AccountValidator.validateEmail(email)
    }

    var body: some View {
        EGuardScreen {
            if let user = model.user {
                VStack(spacing: EGuardSpacing.sm) {
                    AvatarView(name: user.name, size: 96)
                    Text(user.name).font(EGuardTypography.title)
                    StatusPill(text: user.role.title, tint: EGuardColors.primary)
                }
                .frame(maxWidth: .infinity)

                VerifyEmailBanner()

                VStack(spacing: EGuardSpacing.sm) {
                    EGuardTextField(label: "Full name", placeholder: "Your name", text: $name, symbolName: "person", contentType: .name, autocapitalization: .words)
                    EGuardTextField(label: "Email address", placeholder: "you@example.com", text: $email, symbolName: "envelope", contentType: .emailAddress, keyboard: .emailAddress)
                }
                if !user.canUsePassword, emailChanged(user) {
                    Text("Set a password first (Forgot password? on the sign-in screen) to change your email.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.warning)
                }
                InlineError(message: errorMessage ?? validationMessage)
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.success)
                }

                EGuardCard {
                    if user.canUsePassword {
                        EGuardNavRow(title: "Change password", subtitle: "Signs out your other devices", symbolName: "key.fill", tint: EGuardColors.tileOrange) {
                            router.push(.changePassword)
                        }
                    } else {
                        // Apple/Google accounts have no password until they set one through a reset link.
                        EGuardNavRow(title: "Set a password", subtitle: "You signed up with Apple or Google. We'll email you a link.", symbolName: "key.fill", tint: EGuardColors.tileOrange) {
                            router.push(.forgotPassword)
                        }
                    }
                    Divider()
                    EGuardNavRow(title: "Two-step verification", subtitle: user.twoFactor ? "On" : "Off", symbolName: "lock.shield.fill", tint: user.twoFactor ? EGuardColors.success : EGuardColors.tileGray) {
                        router.push(.twoFactor)
                    }
                    .accessibilityIdentifier("account.twoFactor")
                    Divider()
                    EGuardNavRow(title: "Linked sign-ins", subtitle: "Apple and Google accounts that can sign in", symbolName: "person.badge.key.fill", tint: EGuardColors.tilePurple) {
                        router.push(.linkedSignIns)
                    }
                    Divider()
                    EGuardNavRow(title: "Signed-in devices", subtitle: "See and sign out other sessions", symbolName: "laptopcomputer.and.iphone", tint: EGuardColors.tileTeal) {
                        router.push(.sessions)
                    }
                }

                EGuardCard {
                    EGuardValueRow(label: "Family", value: user.family.name)
                    Divider()
                    EGuardValueRow(label: "Time zone", value: user.family.timezone)
                    Divider()
                    EGuardValueRow(label: "Member since", value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
                }

                EGuardCard {
                    EGuardNavRow(
                        title: isExporting ? "Preparing your export…" : "Export your family's data",
                        subtitle: "A JSON file with parents, children, settings, devices, history and alerts. Never passwords.",
                        symbolName: "square.and.arrow.up.fill",
                        tint: EGuardColors.primary
                    ) {
                        Task { await export() }
                    }
                    .disabled(isExporting)
                    .accessibilityIdentifier("account.export")
                    Divider()
                    EGuardNavRow(
                        title: "Delete account",
                        subtitle: user.isAdmin ? "Deletes your whole family's data." : "Deletes only your account.",
                        symbolName: "trash.fill",
                        tint: EGuardColors.danger
                    ) {
                        router.push(.deleteAccount)
                    }
                    .accessibilityIdentifier("account.delete")
                }
            } else {
                EmptyStateView(symbolName: "person.crop.circle.badge.questionmark", title: "Not signed in", message: "Sign in to manage your profile.")
            }
        } actions: {
            if model.user != nil {
                Button(isSaving ? "Saving…" : "Save Changes") { Task { await saveTapped() } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(validationMessage != nil || isSaving || !hasChanges || (model.user.map { !$0.canUsePassword && emailChanged($0) } ?? false))
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasLoaded, let user = model.user else { return }
            hasLoaded = true
            name = user.name
            email = user.email
        }
        .alert("Confirm your password", isPresented: $isConfirmingEmailChange) {
            SecureField("Current password", text: $currentPassword)
            Button("Change email") { Task { await save(password: currentPassword) } }
            Button("Cancel", role: .cancel) { currentPassword = "" }
        } message: {
            Text("Changing your email needs your current password. You'll get a verification link at the new address, and Apple or Google sign-ins are unlinked.")
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    private var hasChanges: Bool {
        guard let user = model.user else { return false }
        return name.trimmingCharacters(in: .whitespaces) != user.name || emailChanged(user)
    }

    private func emailChanged(_ user: APIUser) -> Bool {
        AccountValidator.normalizedEmail(email) != user.email
    }

    private func saveTapped() async {
        guard let user = model.user else { return }
        if emailChanged(user) {
            isConfirmingEmailChange = true
        } else {
            await save(password: nil)
        }
    }

    private func save(password: String?) async {
        guard let user = model.user else { return }
        isSaving = true
        defer { isSaving = false; currentPassword = "" }
        do {
            let emailChanged = emailChanged(user)
            _ = try await model.api.updateMe(
                name: name.trimmingCharacters(in: .whitespaces) != user.name ? name.trimmingCharacters(in: .whitespaces) : nil,
                email: emailChanged ? email : nil,
                password: emailChanged ? password : nil,
                timezone: nil
            )
            await model.refreshUser()
            errorMessage = nil
            message = emailChanged ? "Saved. Check \(AccountValidator.normalizedEmail(email)) for a verification link." : "Saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `POST /me/export`: saves the file and hands it to the share sheet.
    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await model.api.exportData()
            let url = FileManager.default.temporaryDirectory.appending(path: "eguard-family-export.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportFile = ExportFile(url: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A saved export ready for the share sheet.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path() }
}

/// UIKit's share sheet for files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// `POST /me/password`
struct ChangePasswordView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var current = ""
    @State private var next = ""
    @State private var confirm = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var validation: String? {
        if current.isEmpty { return nil }
        if let message = AccountValidator.validatePassword(next) { return message }
        if next != confirm { return "The new passwords don't match." }
        return nil
    }

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: "Change password", subtitle: "Your other devices are signed out afterwards. This one stays signed in.")
            VStack(spacing: EGuardSpacing.sm) {
                EGuardTextField(label: "Current password", placeholder: "Current password", text: $current, symbolName: "lock", isSecure: true, contentType: .password)
                EGuardTextField(label: "New password", placeholder: "At least 10 characters", text: $next, symbolName: "lock.rotation", isSecure: true)
                EGuardTextField(label: "Confirm new password", placeholder: "Repeat the new password", text: $confirm, symbolName: "lock.rotation", isSecure: true)
            }
            InlineError(message: errorMessage ?? validation)
        } actions: {
            Button(isSaving ? "Saving…" : "Change Password") { Task { await save() } }
                .buttonStyle(.eGuardPrimary)
                .disabled(current.isEmpty || next.isEmpty || validation != nil || isSaving)
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await model.api.changePassword(current: current, next: next)
            router.pop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `GET /me/sessions` and `DELETE /me/sessions`
struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[SessionInfo]> = .loading
    @State private var message: String?

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: "Signed-in devices", subtitle: "Every device and browser with access to your family.")
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let error):
                ErrorCard(message: error) { Task { await loadSessions() } }
            case .loaded(let sessions):
                EGuardCard {
                    ForEach(sessions) { session in
                        HStack(spacing: EGuardSpacing.sm) {
                            IconTile(symbolName: session.userAgent.localizedCaseInsensitiveContains("iphone") ? "iphone" : "laptopcomputer", tint: session.current ? EGuardColors.success : EGuardColors.neutral)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.userAgent).font(EGuardTypography.label).lineLimit(1)
                                Text("Last seen \((session.lastSeenAt ?? session.createdAt).verifiedDescription())")
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                            }
                            Spacer()
                            if session.current { StatusPill(text: "This device", tint: EGuardColors.success) }
                        }
                        .padding(.vertical, EGuardSpacing.xxs)
                        if session.id != sessions.last?.id { Divider() }
                    }
                }
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill").font(EGuardTypography.caption).foregroundStyle(EGuardColors.success)
                }
            }
        } actions: {
            Button("Sign Out Other Devices") {
                Task {
                    if let count = try? await model.api.signOutOtherSessions() {
                        message = count == 0 ? "No other sessions were signed in." : "Signed out \(count) other session\(count == 1 ? "" : "s")."
                        await loadSessions()
                    }
                }
            }
            .buttonStyle(.eGuardSecondary)
            .disabled((state.value?.count ?? 0) <= 1)
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSessions() }
    }

    private func loadSessions() async {
        state = await load { try await model.api.sessions() }
    }
}

/// `GET /me/identities` and `DELETE /me/identities/{id}`
struct LinkedSignInsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<[LinkedIdentity]> = .loading
    @State private var errorMessage: String?

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: "Linked sign-ins", subtitle: "Apple and Google accounts that can sign in to eGuard as you.")
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadIdentities() } }
            case .loaded(let identities):
                EGuardCard {
                    if identities.isEmpty {
                        Text("No Apple or Google sign-in is linked. Continue with Apple on the sign-in screen with the same email to link one.")
                            .font(EGuardTypography.callout)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                    ForEach(identities) { identity in
                        HStack(spacing: EGuardSpacing.sm) {
                            IconTile(symbolName: identity.provider == "apple" ? "apple.logo" : "g.circle.fill", tint: EGuardColors.textPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(identity.providerTitle).font(EGuardTypography.label)
                                Text(identity.email ?? "Linked \(identity.createdAt?.verifiedDescription() ?? "")")
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                            }
                            Spacer()
                            Button("Unlink") { Task { await unlink(identity) } }
                                .font(EGuardTypography.label)
                                .foregroundStyle(EGuardColors.danger)
                        }
                        .padding(.vertical, EGuardSpacing.xxs)
                        if identity.id != identities.last?.id { Divider() }
                    }
                }
                if model.user?.canUsePassword == false, !identities.isEmpty {
                    Text("This is your only way to sign in. Set a password before unlinking it.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            InlineError(message: errorMessage)
        } actions: {
            EmptyView()
        }
        .navigationTitle("Linked sign-ins")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIdentities() }
    }

    private func loadIdentities() async {
        state = await load { try await model.api.identities() }
    }

    private func unlink(_ identity: LinkedIdentity) async {
        do {
            try await model.api.deleteIdentity(id: identity.id)
            errorMessage = nil
            await loadIdentities()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `DELETE /me`, with the confirmation the account needs.
struct DeleteAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var isConfirming = false
    @State private var errorMessage: String?
    @State private var isDeleting = false

    private var isAdmin: Bool { model.user?.isAdmin ?? false }

    var body: some View {
        EGuardScreen {
            EGuardIllustration(symbolName: "trash.fill", tint: EGuardColors.danger)
                .frame(maxWidth: .infinity)
            ScreenHeader(
                title: "Delete your account",
                subtitle: isAdmin
                    ? "You're the family admin, so this deletes the whole family: every child, device, setting, history and the other parents' accounts."
                    : "This removes your account from the family. The children, their devices and the other parents stay."
            )
            EGuardCard {
                Label("This can't be undone.", systemImage: "exclamationmark.triangle.fill")
                    .font(EGuardTypography.headline)
                    .foregroundStyle(EGuardColors.danger)
                Text("Paired devices stop syncing and lose their protections at their next check-in. Export your data first if you want a copy.")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            InlineError(message: errorMessage)
        } actions: {
            Button(isDeleting ? "Deleting…" : (isAdmin ? "Delete Family and Account" : "Delete My Account")) { isConfirming = true }
                .buttonStyle(.eGuardPrimary)
                .tint(EGuardColors.danger)
                .disabled(isDeleting)
                .accessibilityIdentifier("deleteAccount.confirm")
            Button("Keep my account") { router.pop() }
                .buttonStyle(.eGuardText)
        }
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .deletionConfirmation(
            isAdmin ? "Delete the whole family?" : "Delete your account?",
            message: isAdmin ? "Every child, device and parent in your family is deleted." : "Only your account is removed.",
            isPresented: $isConfirming,
            user: model.user
        ) { confirmation in
            Task { await delete(confirmation) }
        }
    }

    private func delete(_ confirmation: DeletionConfirmation) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await model.deleteAccount(confirmation: confirmation)
            router.popToRoot()
        } catch {
            errorMessage = error.localizedDescription
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
