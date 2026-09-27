import Observation
import SwiftUI

/// Holds the server's recommendations and the parent's edits.
@Observable
final class RecommendedSetupViewModel {
    var state: LoadState<Recommendations> = .loading
    /// Current config per key, starting from the recommendation.
    var configs: [String: JSONValue] = [:]
    var editingKey: String?

    func load(childId: String, profile: String, api: EGuardAPIService) async {
        state = .loading
        state = await MyApp.load { try await api.recommendations(childId: childId, profile: profile) }
        if let recommendations = state.value {
            configs = Dictionary(uniqueKeysWithValues: recommendations.settings.map { ($0.key, $0.config) })
        }
    }

    func label(for key: String) -> String {
        guard let config = configs[key] else { return "" }
        return ProtectionConfigFormatter.label(key: key, config: config)
    }

    /// Configs the parent changed, each carrying its `key`, as the setup endpoint expects.
    var overrides: [JSONValue] {
        guard let recommendations = state.value else { return [] }
        return recommendations.settings.compactMap { setting in
            guard let edited = configs[setting.key], edited != setting.config else { return nil }
            return edited.setting("key", to: .string(setting.key))
        }
    }

    func binding(for key: String) -> Binding<JSONValue> {
        Binding(
            get: { self.configs[key] ?? .object([:]) },
            set: { self.configs[key] = $0 }
        )
    }
}

/// 06 Recommended Setup, from `GET /children/{id}/recommendations`.
struct RecommendedSetupView: View {
    let childId: String
    let profile: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = RecommendedSetupViewModel()

    private var child: ChildSummary? { model.children.first { $0.id == childId } }

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            OnboardingProgressIndicator(step: .recommendedSetup)
            ScreenHeader(
                title: "Your recommended setup",
                subtitle: child.map { "Based on \($0.name)'s age, here are the suggested settings." }
                    ?? "Here are the suggested settings for the \(profile.capitalized) profile."
            )

            switch viewModel.state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await viewModel.load(childId: childId, profile: profile, api: model.api) } }
            case .loaded(let recommendations):
                let primary = recommendations.settings.filter { ProtectionKey.recommendedOrder.contains($0.key) }
                    .sorted { ProtectionKey.recommendedOrder.firstIndex(of: $0.key)! < ProtectionKey.recommendedOrder.firstIndex(of: $1.key)! }
                let more = recommendations.settings.filter { !ProtectionKey.recommendedOrder.contains($0.key) }

                EGuardCard {
                    ForEach(primary) { setting in
                        row(setting)
                        if setting.id != primary.last?.id { Divider() }
                    }
                }

                VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                    SectionHeader(title: "More protections")
                    EGuardCard {
                        ForEach(more) { setting in
                            row(setting)
                            if setting.id != more.last?.id { Divider() }
                        }
                    }
                }

                if recommendations.settings.allSatisfy({ $0.devices.isEmpty }) {
                    EGuardCard {
                        Label("No device is paired yet. eGuard saves these settings and applies them the moment you pair \(child?.name ?? "your child")'s device.", systemImage: "info.circle.fill")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                }
            }
        } actions: {
            Button("Review & Configure") {
                router.push(.setupProgress(childId: childId, profile: profile, overrides: viewModel.overrides))
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(viewModel.state.value == nil)
            .accessibilityIdentifier("recommended.reviewSetup")
        }
        .brandNavigationTitle()
        .task { await viewModel.load(childId: childId, profile: profile, api: model.api) }
        .sheet(item: $viewModel.editingKey) { key in
            ProtectionConfigSheet(key: key, config: viewModel.binding(for: key))
                .presentationDetents([.medium, .large])
        }
    }

    private func row(_ setting: RecommendedSetting) -> some View {
        EGuardNavRow(
            title: ProtectionKey.name(setting.key),
            subtitle: viewModel.label(for: setting.key),
            symbolName: LucideIcon.symbol(for: setting.icon, fallback: ProtectionKey.symbol(setting.key)),
            tint: LucideIcon.tint(forKey: setting.key)
        ) {
            viewModel.editingKey = setting.key
        } trailing: {
            if setting.devices.contains(where: { $0.capability == .unsupported }) && setting.devices.allSatisfy({ $0.capability == .unsupported }) {
                StatusPill(text: "Not supported", tint: EGuardColors.neutral)
            } else if setting.devices.contains(where: { $0.capability == .guided || $0.capability == .verifyOnly }) {
                StatusPill(text: "Guided", tint: EGuardColors.accent)
            }
        }
        .accessibilityIdentifier("recommended.edit.\(setting.key.lowercased())")
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    NavigationStack {
        RecommendedSetupView(childId: "child_1", profile: "PROTECTED")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
