import SwiftUI

/// Settings › Family, from `GET /family`. The admin invites parents by email; they join once they accept.
struct FamilyView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<Family> = .loading
    @State private var isAddingParent = false
    @State private var parentName = ""
    @State private var parentEmail = ""
    @State private var memberToRemove: FamilyMember?
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isSending = false

    var body: some View {
        EGuardScreen {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let error):
                ErrorCard(message: error) { Task { await loadFamily() } }
            case .loaded(let family):
                ScreenHeader(title: family.name, subtitle: subtitle(family))

                if let plan = family.plan {
                    EGuardCard {
                        HStack {
                            IconTile(symbolName: "rosette", tint: EGuardColors.tileYellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan).font(EGuardTypography.label)
                                Text(usageLine(family))
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                            }
                            Spacer()
                            Button("View") { router.push(.subscription) }
                                .font(EGuardTypography.label)
                                .foregroundStyle(EGuardColors.primary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: "Parents", actionTitle: family.canManage ? "Invite" : nil) { isAddingParent = true }
                    EGuardCard {
                        ForEach(family.members) { member in
                            HStack(spacing: EGuardSpacing.sm) {
                                AvatarView(name: member.name, size: 40, tint: member.role == .familyAdmin ? EGuardColors.primary : EGuardColors.tileTeal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.you ? "\(member.name) (you)" : member.name).font(EGuardTypography.label)
                                    Text("\(member.email) · \(member.isPending ? "Invitation sent" : member.role.title)")
                                        .font(EGuardTypography.caption)
                                        .foregroundStyle(EGuardColors.textSecondary)
                                }
                                Spacer()
                                if member.isPending { StatusPill(text: "Pending", tint: EGuardColors.warning) }
                                if family.canManage, !member.you, member.role == .parent {
                                    Menu {
                                        if member.isPending {
                                            Button("Resend invitation", systemImage: "envelope") { Task { await resend(member) } }
                                        }
                                        Button(member.isPending ? "Withdraw invitation" : "Remove", systemImage: "trash", role: .destructive) { memberToRemove = member }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .foregroundStyle(EGuardColors.neutral)
                                    }
                                    .accessibilityLabel("Options for \(member.name)")
                                }
                            }
                            .padding(.vertical, EGuardSpacing.xxs)
                            if member.id != family.members.last?.id { Divider() }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: "Children", actionTitle: "Add") { router.push(.addChild) }
                    EGuardCard {
                        if family.children.isEmpty {
                            Text("No children yet.").font(EGuardTypography.callout).foregroundStyle(EGuardColors.textSecondary)
                        }
                        ForEach(family.children) { child in
                            EGuardNavRow(title: child.name, subtitle: "\(child.ageDescription) · \(child.deviceCount) device\(child.deviceCount == 1 ? "" : "s")", symbolName: "person.fill", tint: statusTint(child.status)) {
                                router.push(.childProfile(childId: child.id))
                            } trailing: {
                                StatusPill(text: child.status.title, tint: statusTint(child.status))
                            }
                            if child.id != family.children.last?.id { Divider() }
                        }
                    }
                }

                if let message {
                    Label(message, systemImage: "checkmark.circle.fill").font(EGuardTypography.caption).foregroundStyle(EGuardColors.success)
                }
                InlineError(message: errorMessage)

                if !family.canManage {
                    Text("Only the family admin can invite or remove parents.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
        } actions: {
            EmptyView()
        }
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFamily() }
        .sheet(isPresented: $isAddingParent) { addParentSheet }
        .confirmationDialog(memberToRemove?.isPending == true ? "Withdraw the invitation to \(memberToRemove?.name ?? "this parent")?" : "Remove \(memberToRemove?.name ?? "parent")?", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), titleVisibility: .visible) {
            Button(memberToRemove?.isPending == true ? "Withdraw" : "Remove", role: .destructive) { Task { await removeMember() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(memberToRemove?.isPending == true ? "Their invitation link stops working." : "They are signed out everywhere and lose access to the family.")
        }
    }

    private func subtitle(_ family: Family) -> String {
        "\(family.slotsUsed) of \(family.deviceLimit) devices · \(family.timezone)"
    }

    private func usageLine(_ family: Family) -> String {
        var parts = ["\(family.slotsUsed) of \(family.deviceLimit) devices"]
        if let childLimit = family.childLimit {
            parts.append("\(family.childCount ?? family.children.count) of \(childLimit) children")
        }
        return parts.joined(separator: " · ")
    }

    private var addParentSheet: some View {
        NavigationStack {
            EGuardScreen {
                ScreenHeader(title: "Invite a parent", subtitle: "We email them an invitation. They choose their own password when they accept, and the link works for 7 days.")
                VStack(spacing: EGuardSpacing.sm) {
                    EGuardTextField(label: "Full name", placeholder: "Ana Cruz", text: $parentName, symbolName: "person", contentType: .name, autocapitalization: .words)
                    EGuardTextField(label: "Email address", placeholder: "ana@example.com", text: $parentEmail, symbolName: "envelope", contentType: .emailAddress, keyboard: .emailAddress)
                }
                InlineError(message: errorMessage)
            } actions: {
                Button(isSending ? "Sending…" : "Send Invitation") { Task { await invite() } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(AccountValidator.validateName(parentName) != nil || AccountValidator.validateEmail(parentEmail) != nil || isSending)
                Button("Cancel") { isAddingParent = false }
                    .buttonStyle(.eGuardText)
            }
            .navigationTitle("Invite parent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadFamily() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.family() }
    }

    private func invite() async {
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await model.api.inviteMember(name: parentName, email: parentEmail)
            if sent.emailSent == false {
                message = "\(sent.name) was added, but the email didn't go out. Use Resend invitation."
            } else {
                message = "We emailed \(sent.email) an invitation. It works for \(sent.expiresInDays ?? 7) days."
            }
            errorMessage = nil
            isAddingParent = false
            parentName = ""; parentEmail = ""
            await loadFamily()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resend(_ member: FamilyMember) async {
        do {
            try await model.api.resendInvitation(memberId: member.id)
            message = "We sent \(member.name) a new invitation link."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember() async {
        guard let member = memberToRemove else { return }
        do {
            try await model.api.removeMember(id: member.id)
            message = member.isPending ? "The invitation to \(member.name) was withdrawn." : "\(member.name) was removed."
            await loadFamily()
        } catch {
            errorMessage = error.localizedDescription
        }
        memberToRemove = nil
    }
}

#Preview {
    NavigationStack {
        FamilyView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
