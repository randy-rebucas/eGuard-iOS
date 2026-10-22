import Observation
import SwiftUI

/// Holds the server's recommendations and the parent's edits.
@Observable
final class RecommendedSetupViewModel {
    var state: LoadState<Recommendations> = .loading
    /// Current config per key, starting from the recommendation.
    var configs: [String: JSONValue] = [:]
    var editingKey: String?
    /// The parent's edits to category limits ("Gaming time"), by category. Missing means the recommendation stands.
    var categoryMinutes: [String: Int] = [:]
    var editingCategory: RecommendedCategoryLimit?

    func load(childId: String, profile: String, api: EGuardAPIService) async {
        state = .loading
        state = await eGuard.load { try await api.recommendations(childId: childId, profile: profile) }
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

    func minutes(for limit: RecommendedCategoryLimit) -> Int? {
        categoryMinutes[limit.category] ?? limit.dailyLimitMinutes
    }

    /// Category limits to send with the profile: only the ones the plan allows, with the parent's edits.
    var categoryLimits: [CategoryLimitUpdate]? {
        guard let limits = state.value?.categoryLimits?.filter(\.available), !limits.isEmpty else { return nil }
        return limits.map { CategoryLimitUpdate(category: $0.category, dailyLimitMinutes: minutes(for: $0)) }
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
    @State private var isConfirmingReplace = false

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

                if let limits = recommendations.categoryLimits, !limits.isEmpty {
                    categoryLimitsSection(limits)
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
                // With a device paired, the next screen sends all ten settings at once
                if viewModel.state.value?.settings.contains(where: { !$0.devices.isEmpty }) == true {
                    isConfirmingReplace = true
                } else {
                    router.push(.setupProgress(childId: childId, profile: profile, overrides: viewModel.overrides, categoryLimits: viewModel.categoryLimits))
                }
            }
            .buttonStyle(.eGuardPrimary)
            .disabled(viewModel.state.value == nil)
            .accessibilityIdentifier("recommended.reviewSetup")
        }
        .brandNavigationTitle()
        .task { await viewModel.load(childId: childId, profile: profile, api: model.api) }
        .confirmationDialog("Apply these settings?", isPresented: $isConfirmingReplace, titleVisibility: .visible) {
            Button("Apply to \(child?.name ?? "the child")'s devices") {
                router.push(.setupProgress(childId: childId, profile: profile, overrides: viewModel.overrides, categoryLimits: viewModel.categoryLimits))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All ten protections change to what's shown here, replacing \(child?.name ?? "the child")'s current settings and any change still waiting for a device, including another parent's.")
        }
        .sheet(item: $viewModel.editingKey) { key in
            ProtectionConfigSheet(key: key, config: viewModel.binding(for: key))
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $viewModel.editingCategory) { limit in
            MinutesPickerSheet(title: limit.label, minutes: viewModel.minutes(for: limit) ?? 60) { minutes in
                viewModel.categoryMinutes[limit.category] = minutes
            }
            .presentationDetents([.medium])
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
            } else if setting.devices.contains(where: { $0.capability.isGuided }) {
                StatusPill(text: "Guided", tint: EGuardColors.accent)
            }
        }
        .accessibilityIdentifier("recommended.edit.\(setting.key.lowercased())")
    }

    /// The design's "Gaming time": one limit for all apps of a kind together. Locked on plans without it.
    private func categoryLimitsSection(_ limits: [RecommendedCategoryLimit]) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "App categories")
            EGuardCard {
                ForEach(limits) { limit in
                    let kind = AppCategory(rawValue: limit.category)
                    EGuardNavRow(
                        title: limit.label,
                        subtitle: subtitle(for: limit, kind: kind),
                        symbolName: kind?.symbolName ?? "square.grid.2x2.fill",
                        tint: EGuardColors.tileOrange
                    ) {
                        if limit.available { viewModel.editingCategory = limit }
                    } trailing: {
                        if !limit.available { StatusPill(text: "Not on your plan", tint: EGuardColors.neutral) }
                    }
                    .accessibilityIdentifier("recommended.category.\(limit.category.lowercased())")
                    if limit.id != limits.last?.id { Divider() }
                }
            }
        }
    }

    private func subtitle(for limit: RecommendedCategoryLimit, kind: AppCategory?) -> String {
        guard limit.available else {
            return APIClient.storeSafeMessage(limit.upgrade ?? "Not included in your plan.", status: 403)
        }
        guard let minutes = viewModel.minutes(for: limit) else { return "No limit" }
        return "\(ProtectionConfigFormatter.duration(minutes)) a day, all \(kind?.title.lowercased() ?? "these apps") together"
    }
}

/// Picks a number of minutes a day, for category limits and anything else that is just a duration.
struct MinutesPickerSheet: View {
    let title: String
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int

    init(title: String, minutes: Int, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.onSave = onSave
        _minutes = State(initialValue: minutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Daily limit", selection: $minutes) {
                    ForEach(ProtectionConfigEditor.minuteOptions, id: \.self) { option in
                        Text(ProtectionConfigFormatter.duration(option)).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(minutes)
                        dismiss()
                    }
                }
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#if DEBUG
#Preview {
    NavigationStack {
        RecommendedSetupView(childId: "child_1", profile: "PROTECTED")
    }
    .environment(AppModel.live())
    .environment(AppRouter())
}
#endif
