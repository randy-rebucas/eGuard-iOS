import SwiftUI

/// Protection & Controls for one child, from `GET /children/{id}/protections`.
struct ProtectionsView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<[Protection]> = .loading

    private var child: ChildSummary? { model.children.first { $0.id == childId } }

    var body: some View {
        EGuardScreen {
            ScreenHeader(
                title: "Protection & Controls",
                subtitle: child.map { "\($0.name)'s protections and what each device reports." }
            )

            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadProtections() } }
            case .loaded(let protections):
                let verified = protections.filter { $0.status == .pass }.count
                let evaluated = protections.filter { $0.status != .unsupported }.count
                Text("\(verified) of \(evaluated) protections verified")
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.textSecondary)

                VStack(spacing: EGuardSpacing.xs) {
                    ForEach(protections) { protection in
                        Button {
                            router.push(.protectionEditor(childId: childId, key: protection.key))
                        } label: {
                            HStack(spacing: EGuardSpacing.sm) {
                                IconTile(symbolName: LucideIcon.symbol(for: protection.icon, fallback: ProtectionKey.symbol(protection.key)), tint: LucideIcon.tint(forKey: protection.key))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ProtectionKey.name(protection.key))
                                        .font(EGuardTypography.label)
                                        .foregroundStyle(EGuardColors.textPrimary)
                                    Text(protection.openBatchId != nil ? "Change in progress…" : protection.policyLabel)
                                        .font(EGuardTypography.caption)
                                        .foregroundStyle(protection.openBatchId != nil ? EGuardColors.primary : EGuardColors.textSecondary)
                                }
                                Spacer(minLength: EGuardSpacing.xs)
                                HealthStatusBadge(status: protection.status.healthStatus)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(EGuardColors.neutral)
                            }
                            .padding(EGuardSpacing.sm)
                            .background(EGuardColors.surface, in: EGuardShapes.card)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(protection.isUnsupportedEverywhere)
                        .opacity(protection.isUnsupportedEverywhere ? 0.6 : 1)
                        .accessibilityIdentifier("protections.\(protection.key.lowercased())")
                    }
                }
            }
        } actions: {
            Button("Check Configuration") {
                router.push(.healthCheck(childId: childId, isOnboarding: false))
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("configure.checkConfiguration")
        }
        .navigationTitle("Manage Protection")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProtections() }
    }

    private func loadProtections() async {
        state = .loading
        state = await load { try await model.api.protections(childId: childId) }
    }
}

#Preview {
    NavigationStack {
        ProtectionsView(childId: "child_1")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
