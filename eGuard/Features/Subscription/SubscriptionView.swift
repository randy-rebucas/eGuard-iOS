import SwiftUI

/// 17 Subscription, from `GET /subscription`. iOS has no in-app billing yet, so upgrades route to support.
struct SubscriptionView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<SubscriptionInfo> = .loading

    var body: some View {
        EGuardScreen {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadSubscription() } }
            case .loaded(let info):
                planCard(info)

                EGuardCard {
                    SectionHeader(title: "What's included")
                    ForEach(info.features) { feature in
                        HStack(spacing: EGuardSpacing.sm) {
                            Image(systemName: feature.included ? "checkmark.circle.fill" : "lock.circle.fill")
                                .foregroundStyle(feature.included ? EGuardColors.success : EGuardColors.neutral)
                            Text(feature.label)
                                .font(EGuardTypography.label)
                                .foregroundStyle(feature.included ? EGuardColors.textPrimary : EGuardColors.textSecondary)
                            Spacer()
                            if !feature.included, let upgrade = info.upgrade {
                                StatusPill(text: upgrade.name.replacingOccurrences(of: "eGuard ", with: ""), tint: EGuardColors.tileYellow)
                            }
                        }
                        .padding(.vertical, EGuardSpacing.xxs)
                        .accessibilityElement(children: .combine)
                        if feature.id != info.features.last?.id { Divider() }
                    }
                }

                EGuardCard {
                    SectionHeader(title: "Plan Usage")
                    Text("\(info.usage.devicesUsed) of \(info.usage.deviceLimit) devices used")
                        .font(EGuardTypography.label)
                    ProgressView(value: Double(info.usage.devicesUsed), total: Double(max(info.usage.deviceLimit, 1)))
                        .tint(EGuardColors.primary)
                    EGuardValueRow(label: "Children", value: "\(info.usage.children)")
                }

                if !info.billingAvailable {
                    Text("Plan changes aren't available in the iPhone app yet. Contact support to upgrade or change your plan.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
        } actions: {
            if let info = state.value {
                if info.billingAvailable, info.upgrade != nil, info.canManage {
                    Button("Upgrade to \(info.upgrade?.name ?? "Family")") { router.push(.supportTicket) }
                        .buttonStyle(.eGuardPrimary)
                } else {
                    Button("Contact Support About Your Plan") { router.push(.supportTicket) }
                        .buttonStyle(.eGuardSecondary)
                }
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSubscription() }
    }

    private func loadSubscription() async {
        state = await load { try await model.api.subscription() }
    }

    private func planCard(_ info: SubscriptionInfo) -> some View {
        EGuardCard {
            HStack(spacing: EGuardSpacing.md) {
                IconTile(symbolName: "crown.fill", tint: EGuardColors.tileYellow, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.plan).font(EGuardTypography.title3)
                    Text(info.isActive ? "Active Plan" : "Expired")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(info.isActive ? EGuardColors.success : EGuardColors.danger)
                }
                Spacer()
            }
            Divider()
            if let label = info.renewsLabel {
                EGuardValueRow(label: "Renewal", value: label)
            }
            if let store = info.store {
                EGuardValueRow(label: "Billed through", value: store.name == "GOOGLE_PLAY" ? "Google Play" : store.name)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
