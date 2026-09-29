import SwiftUI

/// Profile and login details, from `/me`.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var email = ""
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var errorMessage: String?

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
                InlineError(message: errorMessage ?? validationMessage)
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.success)
                }

                EGuardCard {
                    EGuardNavRow(title: "Change password", subtitle: "Signs out your other devices", symbolName: "key.fill", tint: EGuardColors.tileOrange) {
                        router.push(.changePassword)
                    }
                    Divider()
                    EGuardNavRow(title: "Signed-in devices", subtitle: "See and sign out other sessions", symbolName: "laptopcomputer.and.iphone", tint: EGuardColors.tileTeal) {
                        router.push(.sessions)
                    }
                    Divider()
                    EGuardNavRow(title: "Two-step verification", subtitle: "Coming soon", symbolName: "lock.shield.fill", tint: EGuardColors.tileGray, showsChevron: false)
                }

                EGuardCard {
                    EGuardValueRow(label: "Family", value: user.family.name)
                    Divider()
                    EGuardValueRow(label: "Time zone", value: user.family.timezone)
                    Divider()
                    EGuardValueRow(label: "Member since", value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
                }

                // Deletion runs on the web (Settings › Data), shared with Android. Linking it here keeps
                // the process reachable from inside the app, as the App Store requires.
                EGuardCard {
                    EGuardNavRow(
                        title: "Delete account",
                        subtitle: user.isAdmin ? "Deletes your whole family's data. Opens eguard.family." : "Deletes only your account. Opens eguard.family.",
                        symbolName: "trash.fill",
                        tint: EGuardColors.danger
                    ) {
                        openURL(EGuardPublisher.deleteAccountURL)
                    }
                    .accessibilityIdentifier("account.delete")
                }
            } else {
                EmptyStateView(symbolName: "person.crop.circle.badge.questionmark", title: "Not signed in", message: "Sign in to manage your profile.")
            }
        } actions: {
            if model.user != nil {
                Button(isSaving ? "Saving…" : "Save Changes") { Task { await save() } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(validationMessage != nil || isSaving || !hasChanges)
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
    }

    private var hasChanges: Bool {
        guard let user = model.user else { return false }
        return name.trimmingCharacters(in: .whitespaces) != user.name || AccountValidator.normalizedEmail(email) != user.email
    }

    private func save() async {
        guard let user = model.user else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let emailChanged = AccountValidator.normalizedEmail(email) != user.email
            _ = try await model.api.updateMe(
                name: name.trimmingCharacters(in: .whitespaces) != user.name ? name.trimmingCharacters(in: .whitespaces) : nil,
                email: emailChanged ? email : nil,
                timezone: nil
            )
            await model.refreshUser()
            errorMessage = nil
            message = emailChanged ? "Saved. Check \(AccountValidator.normalizedEmail(email)) for a verification link." : "Saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
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

#Preview {
    NavigationStack {
        AccountView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
