import SwiftUI

/// 17 Your plan, from `GET /subscription`. Payments live in the web app, so this screen is
/// read-only: it shows the current plan, what it includes, and device usage. Any plan change
/// goes through support.
struct SubscriptionView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<SubscriptionInfo> = .loading

    var body: some View {
        // No footer bar: the plan is read-only here, and the support button lives inside the card.
        EGuardScreen(showsActionBackground: false) {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadSubscription() } }
            case .loaded(let info):
                planCard(info)
                planUsage(info)
            }
        } actions: {
            EmptyView()
        }
        .navigationTitle("Your plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSubscription() }
    }

    private func loadSubscription() async {
        state = await load { try await model.api.subscription() }
    }

    private func planCard(_ info: SubscriptionInfo) -> some View {
        // Only features the plan includes are listed; there is no in-app upgrade path to point at.
        let included = info.features.filter(\.included)

        return EGuardCard {
            HStack(spacing: EGuardSpacing.md) {
                IconTile(symbolName: "rosette", tint: EGuardColors.tileYellow, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.plan).font(EGuardTypography.title3)
                    Text(info.isActive ? "Active Plan" : "Expired")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(info.isActive ? EGuardColors.success : EGuardColors.danger)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            if !included.isEmpty {
                VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
                    ForEach(included) { feature in
                        HStack(spacing: EGuardSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(EGuardColors.success)
                            Text(feature.label)
                                .font(EGuardTypography.label)
                                .foregroundStyle(EGuardColors.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, EGuardSpacing.xxs)
            }

            Button("Contact support") { router.push(.supportTicket) }
                .buttonStyle(.eGuardSecondary)
                .padding(.top, EGuardSpacing.xs)
        }
    }

    private func planUsage(_ info: SubscriptionInfo) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.xs) {
            SectionHeader(title: "Plan Usage")
            Text("\(info.usage.devicesUsed) of \(info.usage.deviceLimit) devices used")
                .font(EGuardTypography.label)
                .foregroundStyle(EGuardColors.textSecondary)
            ProgressView(value: Double(info.usage.devicesUsed), total: Double(max(info.usage.deviceLimit, 1)))
                .tint(EGuardColors.primary)
        }
        .padding(.horizontal, EGuardSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
