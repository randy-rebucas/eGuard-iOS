import SwiftUI

/// Family privacy settings from `/family/privacy` (admin only), plus what eGuard stores.
struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var state: LoadState<PrivacySettings> = .loading
    @State private var isConfirmingHistoryOff = false
    @State private var errorMessage: String?

    private var canManage: Bool { model.user?.isAdmin ?? false }

    var body: some View {
        EGuardScreen {
            EGuardIllustration(symbolName: "lock.shield.fill", size: 96)
                .frame(maxWidth: .infinity)
            ScreenHeader(
                title: "Privacy",
                subtitle: canManage ? "These settings apply to the whole family." : "Only the family admin can change these settings."
            )

            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadPrivacy() } }
            case .loaded(let settings):
                EGuardCard {
                    Toggle(isOn: Binding(
                        get: { settings.keepLocationHistory },
                        set: { value in
                            if value { Task { await update(PrivacyPatch(keepLocationHistory: true)) } } else { isConfirmingHistoryOff = true }
                        }
                    )) {
                        HStack(spacing: EGuardSpacing.sm) {
                            IconTile(symbolName: "clock.arrow.circlepath", tint: EGuardColors.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep location history").font(EGuardTypography.label)
                                Text(settings.retentionDays.map { "Places visited are kept for \($0) days" } ?? "Keeps a list of places visited")
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                            }
                        }
                    }
                    .tint(EGuardColors.primary)
                    .disabled(!canManage)
                    Divider()
                    Toggle(isOn: Binding(
                        get: { settings.shareAnalytics },
                        set: { value in Task { await update(PrivacyPatch(shareAnalytics: value)) } }
                    )) {
                        HStack(spacing: EGuardSpacing.sm) {
                            IconTile(symbolName: "chart.bar.fill", tint: EGuardColors.tilePurple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Share anonymous analytics").font(EGuardTypography.label)
                                Text("Helps improve eGuard. Never includes names or locations.")
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                            }
                        }
                    }
                    .tint(EGuardColors.primary)
                    .disabled(!canManage)
                }
            }
            InlineError(message: errorMessage)

            EGuardCard {
                SectionHeader(title: "What eGuard stores")
                point("The protections you chose and what each device reports about them.", symbol: "checkmark.shield.fill", tint: EGuardColors.success)
                Divider()
                point("Your children's names, ages, and optional photos.", symbol: "person.fill", tint: EGuardColors.primary)
                Divider()
                point("Location only while a device shares it, and history only when turned on above.", symbol: "location.fill", tint: EGuardColors.success)
                Divider()
                point("Never messages, recordings, or passwords from your child's device.", symbol: "eye.slash.fill", tint: EGuardColors.danger)
            }

            EGuardCard {
                SectionHeader(title: "Privacy questions")
                Text("Ask about your family's data, or request a copy or deletion, by emailing \(EGuardPublisher.name).")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
                EGuardNavRow(title: "Privacy Policy", subtitle: "What eGuard collects, why, and for how long", symbolName: "doc.text.fill", tint: EGuardColors.primary) {
                    openURL(EGuardPublisher.privacyPolicyURL)
                }
                Divider()
                EGuardNavRow(title: "Email privacy contact", subtitle: model.supportEmail, symbolName: "envelope.fill", tint: EGuardColors.tileTeal) {
                    if let url = EGuardPublisher.mailURL(for: model.supportEmail) { openURL(url) }
                }
            }
        } actions: {
            EmptyView()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPrivacy() }
        .confirmationDialog("Turn off location history?", isPresented: $isConfirmingHistoryOff, titleVisibility: .visible) {
            Button("Turn Off and Delete History", role: .destructive) { Task { await update(PrivacyPatch(keepLocationHistory: false)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All stored visits are deleted immediately. This can't be undone.")
        }
    }

    private func loadPrivacy() async {
        state = await load { try await model.api.privacy() }
    }

    private func update(_ patch: PrivacyPatch) async {
        do {
            state = .loaded(try await model.api.updatePrivacy(patch))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func point(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: EGuardSpacing.sm) {
            IconTile(symbolName: symbol, tint: tint, size: 32)
            Text(text)
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.textPrimary)
        }
        .padding(.vertical, EGuardSpacing.xxs)
    }
}

#Preview {
    NavigationStack {
        PrivacyView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
