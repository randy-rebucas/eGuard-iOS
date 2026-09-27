import SwiftUI

/// Children tab, from `GET /children`.
struct ChildrenView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<[ChildSummary]> = .loading

    var body: some View {
        TabScreen {
            TabScreenHeader(title: "Children") {
                EmptyView()
            } trailing: {
                Button {
                    router.push(.addChild)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Add child")
                .accessibilityIdentifier("children.add")
            }
        } content: {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadChildren() } }
            case .loaded(let children):
                if children.isEmpty {
                    EmptyStateView(symbolName: "person.crop.circle.badge.plus", title: "No children yet", message: "Add a child to start protecting their devices.")
                    Button("Add Child") { router.push(.addChild) }
                        .buttonStyle(.eGuardPrimary)
                }
                ForEach(children) { child in
                    Button {
                        router.push(.childProfile(childId: child.id))
                    } label: {
                        EGuardCard {
                            HStack(spacing: EGuardSpacing.md) {
                                ChildAvatar(child: child, size: 64)
                                VStack(alignment: .leading, spacing: EGuardSpacing.xxs) {
                                    Text(child.name)
                                        .font(EGuardTypography.title3)
                                        .foregroundStyle(EGuardColors.textPrimary)
                                    Text("\(child.ageDescription) · \(child.deviceCount == 0 ? "No devices" : (child.deviceCount == 1 ? child.deviceName : "\(child.deviceCount) devices"))")
                                        .font(EGuardTypography.caption)
                                        .foregroundStyle(EGuardColors.textSecondary)
                                    HStack(spacing: EGuardSpacing.xs) {
                                        StatusPill(text: child.status.title, tint: statusTint(child.status))
                                        Text("\(child.health.text) health")
                                            .font(EGuardTypography.caption)
                                            .foregroundStyle(EGuardColors.textSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(EGuardColors.neutral)
                            }
                            if let today = child.todayMinutes, let limit = child.todayLimitMinutes, child.deviceCount > 0 {
                                ProgressView(value: Double(min(today, limit)), total: Double(max(limit, 1)))
                                    .tint(EGuardColors.primary)
                                Text("\(ProtectionConfigFormatter.duration(today)) of \(ProtectionConfigFormatter.duration(limit)) screen time today")
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("children.child")
                }
            }
        }
        .refreshable { await loadChildren() }
        .task { await loadChildren() }
    }

    private func loadChildren() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.children() }
    }
}

#Preview {
    NavigationStack {
        ChildrenView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
