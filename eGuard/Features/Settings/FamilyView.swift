import SwiftUI

/// Settings › Family, from `GET /family`, with parent management for the admin.
struct FamilyView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<Family> = .loading
    @State private var isAddingParent = false
    @State private var parentName = ""
    @State private var parentEmail = ""
    @State private var parentPassword = ""
    @State private var memberToRemove: FamilyMember?
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        EGuardScreen {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let error):
                ErrorCard(message: error) { Task { await loadFamily() } }
            case .loaded(let family):
                ScreenHeader(title: family.name, subtitle: "\(family.deviceCount) of \(family.deviceLimit) devices · \(family.timezone)")

                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: "Parents", actionTitle: family.canManage ? "Add" : nil) { isAddingParent = true }
                    EGuardCard {
                        ForEach(family.members) { member in
                            HStack(spacing: EGuardSpacing.sm) {
                                AvatarView(name: member.name, size: 40, tint: member.role == .familyAdmin ? EGuardColors.primary : EGuardColors.tileTeal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.you ? "\(member.name) (you)" : member.name).font(EGuardTypography.label)
                                    Text("\(member.email) · \(member.role.title)")
                                        .font(EGuardTypography.caption)
                                        .foregroundStyle(EGuardColors.textSecondary)
                                }
                                Spacer()
                                if family.canManage, !member.you, member.role == .parent {
                                    Button("Remove") { memberToRemove = member }
                                        .font(EGuardTypography.label)
                                        .foregroundStyle(EGuardColors.danger)
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
                    Text("Only the family admin can add or remove parents.")
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
        .confirmationDialog("Remove \(memberToRemove?.name ?? "parent")?", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await removeMember() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They are signed out everywhere and lose access to the family.")
        }
    }

    private var addParentSheet: some View {
        NavigationStack {
            EGuardScreen {
                ScreenHeader(title: "Add a parent", subtitle: "Share the temporary password with them so they can sign in and change it.")
                VStack(spacing: EGuardSpacing.sm) {
                    EGuardTextField(label: "Full name", placeholder: "Ana Cruz", text: $parentName, symbolName: "person", contentType: .name, autocapitalization: .words)
                    EGuardTextField(label: "Email address", placeholder: "ana@example.com", text: $parentEmail, symbolName: "envelope", contentType: .emailAddress, keyboard: .emailAddress)
                    EGuardTextField(label: "Temporary password", placeholder: "At least 10 characters", text: $parentPassword, symbolName: "lock", isSecure: true)
                }
                InlineError(message: errorMessage)
            } actions: {
                Button("Add Parent") { Task { await addParent() } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(AccountValidator.validateName(parentName) != nil || AccountValidator.validateEmail(parentEmail) != nil || AccountValidator.validatePassword(parentPassword) != nil)
                Button("Cancel") { isAddingParent = false }
                    .buttonStyle(.eGuardText)
            }
            .navigationTitle("Add parent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadFamily() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.family() }
    }

    private func addParent() async {
        do {
            let member = try await model.api.addMember(name: parentName, email: parentEmail, password: parentPassword)
            message = "\(member.name) can now sign in with the temporary password."
            errorMessage = nil
            isAddingParent = false
            parentName = ""; parentEmail = ""; parentPassword = ""
            await loadFamily()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember() async {
        guard let member = memberToRemove else { return }
        do {
            try await model.api.removeMember(id: member.id)
            message = "\(member.name) was removed."
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
