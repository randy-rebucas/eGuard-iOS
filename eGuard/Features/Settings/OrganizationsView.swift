import SwiftUI

/// Settings › Organizations: schools and groups the family joined with a code. Joining shares nothing
/// about the family; the organization only sees how many families joined.
struct OrganizationsView: View {
    @Environment(AppModel.self) private var model
    @State private var state: LoadState<OrganizationsResponse> = .loading
    @State private var isJoining = false
    @State private var code = ""
    @State private var preview: OrganizationPreview?
    @State private var toLeave: Organization?
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        EGuardScreen {
            ScreenHeader(title: "Organizations", subtitle: "Schools, community groups and businesses your family has joined.")
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let error):
                ErrorCard(message: error) { Task { await loadOrganizations() } }
            case .loaded(let response):
                EGuardCard {
                    if response.organizations.isEmpty {
                        Text("Your family hasn't joined an organization yet.")
                            .font(EGuardTypography.callout)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                    ForEach(response.organizations) { organization in
                        HStack(spacing: EGuardSpacing.sm) {
                            IconTile(symbolName: organization.symbolName, tint: EGuardColors.tileTeal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(organization.name).font(EGuardTypography.label)
                                Text([organization.kindTitle, organization.joinedAt.map { "Joined \($0.formatted(date: .abbreviated, time: .omitted))" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                            }
                            Spacer()
                            if response.canManage {
                                Button("Leave") { toLeave = organization }
                                    .font(EGuardTypography.label)
                                    .foregroundStyle(EGuardColors.danger)
                            }
                        }
                        .padding(.vertical, EGuardSpacing.xxs)
                        if organization.id != response.organizations.last?.id { Divider() }
                    }
                }
                if let privacy = response.privacy {
                    Text(privacy)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                if !response.canManage {
                    Text("Only the family admin can join or leave an organization.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            if let message {
                Label(message, systemImage: "checkmark.circle.fill").font(EGuardTypography.caption).foregroundStyle(EGuardColors.success)
            }
            InlineError(message: errorMessage)
        } actions: {
            if state.value?.canManage == true {
                Button("Join with a Code") { isJoining = true }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("organizations.join")
            }
        }
        .navigationTitle("Organizations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadOrganizations() }
        .sheet(isPresented: $isJoining, onDismiss: { preview = nil; code = "" }) { joinSheet }
        .confirmationDialog("Leave \(toLeave?.name ?? "this organization")?", isPresented: Binding(get: { toLeave != nil }, set: { if !$0 { toLeave = nil } }), titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await leave() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A plan the organization already sponsored keeps running until it ends.")
        }
    }

    private var joinSheet: some View {
        NavigationStack {
            EGuardScreen {
                if let preview {
                    ScreenHeader(title: preview.name, subtitle: preview.kindLabel ?? preview.kind.capitalized)
                    EGuardCard {
                        Text(preview.message)
                            .font(EGuardTypography.callout)
                            .foregroundStyle(EGuardColors.textPrimary)
                    }
                    if preview.alreadyJoined {
                        Label("Your family already joined this organization.", systemImage: "checkmark.circle.fill")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.success)
                    }
                } else {
                    ScreenHeader(title: "Join an organization", subtitle: "Enter the 8-character join code the organization gave you. Dashes and spaces don't matter.")
                    EGuardTextField(label: "Join code", placeholder: "SCHL-2026", text: $code, symbolName: "building.2", autocapitalization: .characters, identifier: "organizations.code")
                }
                InlineError(message: errorMessage)
            } actions: {
                if let preview {
                    Button(isWorking ? "Joining…" : (preview.alreadyJoined ? "Done" : "Join \(preview.name)")) {
                        Task { preview.alreadyJoined ? (isJoining = false) : await join() }
                    }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(isWorking)
                    .accessibilityIdentifier("organizations.confirmJoin")
                    Button("Back") { self.preview = nil }
                        .buttonStyle(.eGuardText)
                } else {
                    Button(isWorking ? "Checking…" : "Continue") { Task { await previewCode() } }
                        .buttonStyle(.eGuardPrimary)
                        .disabled(code.filter { $0.isLetter || $0.isNumber }.count != 8 || isWorking)
                        .accessibilityIdentifier("organizations.preview")
                    Button("Cancel") { isJoining = false }
                        .buttonStyle(.eGuardText)
                }
            }
            .navigationTitle("Join")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadOrganizations() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.organizations() }
    }

    private func previewCode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            preview = try await model.api.previewOrganization(code: code)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func join() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let joined = try await model.api.joinOrganization(code: code)
            message = "Your family joined \(joined.name)."
            errorMessage = nil
            isJoining = false
            await loadOrganizations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leave() async {
        guard let organization = toLeave else { return }
        do {
            let left = try await model.api.leaveOrganization(id: organization.id)
            message = "Your family left \(left.name ?? organization.name)."
            errorMessage = nil
            await loadOrganizations()
        } catch {
            errorMessage = error.localizedDescription
        }
        toLeave = nil
    }
}

#Preview {
    NavigationStack {
        OrganizationsView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
