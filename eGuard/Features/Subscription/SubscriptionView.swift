import StoreKit
import SwiftUI

/// 17 Subscription: the current plan, what it includes, and App Store management.
struct SubscriptionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.purchase) private var purchase
    @State private var service = SubscriptionService()
    @State private var isManaging = false

    private var plan: SubscriptionService.Plan { service.plan }

    var body: some View {
        EGuardScreen {
            planCard

            EGuardCard {
                SectionHeader(title: "What's included")
                feature("Up to 3 children", included: true)
                Divider()
                feature("Up to 5 devices", included: plan.isPlus, plusOnly: true)
                Divider()
                feature("Configuration health checks", included: true)
                Divider()
                feature("Protection alerts", included: true)
                Divider()
                feature("Advanced reports", included: plan.isPlus, plusOnly: true)
                Divider()
                feature("Priority support", included: plan.isPlus, plusOnly: true)
            }

            EGuardCard {
                SectionHeader(title: "Plan Usage")
                let devices = model.childProfile == nil ? 0 : 1
                let limit = plan.isPlus ? 5 : 1
                Text("\(devices) of \(limit) devices used")
                    .font(EGuardTypography.label)
                ProgressView(value: Double(devices), total: Double(limit))
                    .tint(EGuardColors.primary)
                    .accessibilityLabel("\(devices) of \(limit) devices used")
            }

            if let message = service.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.warning)
            }
        } actions: {
            if plan.isPlus {
                Button("Manage Subscription") { isManaging = true }
                    .buttonStyle(.eGuardSecondary)
            } else if let product = service.product {
                Button("Upgrade to eGuard Plus · \(product.displayPrice)") {
                    Task {
                        do {
                            await service.handle(try await purchase(product))
                        } catch {
                            service.report(error)
                        }
                    }
                }
                .buttonStyle(.eGuardPrimary)
            } else {
                Button(service.isLoading ? "Checking the App Store…" : "eGuard Plus coming soon") {}
                    .buttonStyle(.eGuardSecondary)
                    .disabled(true)
                Button("Restore Purchases") {
                    Task {
                        try? await AppStore.sync()
                        await service.refreshEntitlements()
                    }
                }
                .buttonStyle(.eGuardText)
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.load() }
        .manageSubscriptionsSheet(isPresented: $isManaging)
    }

    private var planCard: some View {
        EGuardCard {
            HStack(spacing: EGuardSpacing.md) {
                IconTile(symbolName: "crown.fill", tint: EGuardColors.tileYellow, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(EGuardTypography.title3)
                    Text(plan.statusText)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(plan.isPlus ? EGuardColors.success : EGuardColors.textSecondary)
                }
                Spacer()
            }
            Divider()
            if case .plus(let renews) = plan, let renews {
                EGuardValueRow(label: "Renews on", value: renews.formatted(date: .abbreviated, time: .omitted))
            } else if plan.isPlus {
                EGuardValueRow(label: "Renewal", value: "Managed by the App Store")
            } else {
                Text("The free plan includes everything needed to protect the child using this device. Plus adds multi-device features when it launches.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }

    private func feature(_ title: String, included: Bool, plusOnly: Bool = false) -> some View {
        HStack(spacing: EGuardSpacing.sm) {
            Image(systemName: included ? "checkmark.circle.fill" : "lock.circle.fill")
                .foregroundStyle(included ? EGuardColors.success : EGuardColors.neutral)
            Text(title)
                .font(EGuardTypography.label)
                .foregroundStyle(included ? EGuardColors.textPrimary : EGuardColors.textSecondary)
            Spacer()
            if plusOnly && !included {
                StatusPill(text: "Plus", tint: EGuardColors.tileYellow)
            }
        }
        .padding(.vertical, EGuardSpacing.xxs)
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
