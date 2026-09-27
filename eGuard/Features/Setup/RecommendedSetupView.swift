import Observation
import SwiftUI

/// Holds an editable draft of the recommended settings.
@Observable
final class RecommendedSetupViewModel {
    var draft = ProtectionSettings.off
    var editingFeature: ProtectionFeature?
    private(set) var hasLoaded = false

    static let allowanceOptions = [15, 30, 45, 60, 90, 120, 180]

    func load(from model: AppModel) {
        guard !hasLoaded else { return }
        draft = model.settings
        hasLoaded = true
    }

    func save(to model: AppModel) {
        model.updateSettings(draft)
    }

    var moreProtections: [ProtectionFeature] {
        [.appRestrictions, .purchases, .explicitContent, .deviceActivity, .screenTimePasscode]
    }

    func binding(for feature: ProtectionFeature) -> Bool {
        draft.isEnabled(feature)
    }

    func setEnabled(_ enabled: Bool, for feature: ProtectionFeature) {
        switch feature {
        case .appRestrictions: draft.restrictSelectedApps = enabled
        case .purchases: draft.requirePasswordForPurchases = enabled
        case .explicitContent: draft.blockExplicitContent = enabled
        case .deviceActivity: draft.monitorDeviceActivity = enabled
        case .screenTimePasscode: draft.requireScreenTimePasscode = enabled
        case .downtime:
            draft.downtime = enabled
                ? DowntimeWindow(start: TimeOfDay(hour: 21, minute: 30), end: TimeOfDay(hour: 6, minute: 0))
                : nil
        case .gaming: draft.gamingLimitMinutes = enabled ? 60 : nil
        case .socialApps: draft.socialAppsLimitMinutes = enabled ? 60 : nil
        case .webContent: draft.webContent = enabled ? .limited : .unrestricted
        case .appInstallation: draft.appInstallation = enabled ? .parentApproval : .allowed
        }
    }
}

/// 04 Recommended Setup
struct RecommendedSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = RecommendedSetupViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            if !model.isSetupComplete {
                OnboardingProgressIndicator(step: .recommendedSetup)
            }
            ScreenHeader(
                title: "Your recommended setup",
                subtitle: subtitle
            )

            EGuardCard {
                ForEach(ProtectionFeature.recommendedSetupOrder) { feature in
                    EGuardNavRow(
                        title: rowTitle(for: feature),
                        subtitle: viewModel.draft.summary(for: feature),
                        symbolName: feature.symbolName,
                        tint: EGuardTheme.tint(for: feature)
                    ) {
                        viewModel.editingFeature = feature
                    }
                    .accessibilityIdentifier("recommended.edit.\(feature.rawValue)")
                    if feature != ProtectionFeature.recommendedSetupOrder.last {
                        Divider()
                    }
                }
            }

            VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                SectionHeader(title: "More protections")
                EGuardCard {
                    ForEach(viewModel.moreProtections) { feature in
                        Toggle(isOn: Binding(
                            get: { viewModel.binding(for: feature) },
                            set: { viewModel.setEnabled($0, for: feature) }
                        )) {
                            HStack(spacing: EGuardSpacing.sm) {
                                IconTile(symbolName: feature.symbolName, tint: EGuardTheme.tint(for: feature))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(EGuardTypography.label)
                                    Text(feature.shortDescription)
                                        .font(EGuardTypography.caption)
                                        .foregroundStyle(EGuardColors.textSecondary)
                                }
                            }
                        }
                        .tint(EGuardColors.primary)
                        .accessibilityIdentifier("recommended.toggle.\(feature.rawValue)")
                        if feature != viewModel.moreProtections.last {
                            Divider()
                        }
                    }
                }
            }
        } actions: {
            Button(model.isSetupComplete ? "Save & Configure" : "Review & Configure") {
                viewModel.save(to: model)
                router.push(model.isSetupComplete ? .manageProtection : .configureSettings)
            }
            .buttonStyle(.eGuardPrimary)
            .accessibilityIdentifier("recommended.reviewSetup")
        }
        .brandNavigationTitle()
        .onAppear { viewModel.load(from: model) }
        .sheet(item: $viewModel.editingFeature) { feature in
            FeatureEditorSheet(feature: feature, settings: $viewModel.draft)
                .presentationDetents([.medium, .large])
        }
    }

    private var subtitle: String {
        if let child = model.childProfile {
            return "Based on \(child.trimmedName)'s age, here are the suggested settings."
        }
        return "Based on the \(viewModel.draft.profile.title) profile, here are the suggested settings."
    }

    /// Row titles follow the mockup's everyday wording.
    private func rowTitle(for feature: ProtectionFeature) -> String {
        switch feature {
        case .downtime: "Bedtime"
        case .gaming: "Gaming time"
        case .socialApps: "Social apps time"
        case .webContent: "Explicit content"
        case .appInstallation: "App downloads"
        default: feature.title
        }
    }
}

/// Native editors for each recommended value.
struct FeatureEditorSheet: View {
    let feature: ProtectionFeature
    @Binding var settings: ProtectionSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch feature {
                case .downtime: downtimeEditor
                case .gaming: allowanceEditor(
                    title: "Gaming",
                    value: $settings.gamingLimitMinutes
                )
                case .socialApps: allowanceEditor(
                    title: "Social Apps",
                    value: $settings.socialAppsLimitMinutes
                )
                case .webContent: webContentEditor
                case .appInstallation: appInstallationEditor
                default: Text(feature.shortDescription)
                }
            }
            .navigationTitle(feature.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("editor.done")
                }
            }
        }
    }

    @ViewBuilder
    private var downtimeEditor: some View {
        Section {
            Toggle("Downtime", isOn: Binding(
                get: { settings.downtime != nil },
                set: { enabled in
                    settings.downtime = enabled
                        ? DowntimeWindow(start: TimeOfDay(hour: 21, minute: 30), end: TimeOfDay(hour: 6, minute: 0))
                        : nil
                }
            ))
        } footer: {
            Text("Apps are shielded from the start time until the end time every day.")
        }
        if let window = settings.downtime {
            Section("Schedule") {
                DatePicker(
                    "Start",
                    selection: Binding(
                        get: { window.start.date() },
                        set: { settings.downtime?.start = TimeOfDay(date: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "End",
                    selection: Binding(
                        get: { window.end.date() },
                        set: { settings.downtime?.end = TimeOfDay(date: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                if !window.isValid {
                    Label("The schedule must cover at least fifteen minutes.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(EGuardColors.warning)
                        .font(EGuardTypography.caption)
                }
            }
        }
    }

    private func allowanceEditor(title: String, value: Binding<Int?>) -> some View {
        Group {
            Section {
                Toggle("Daily limit", isOn: Binding(
                    get: { value.wrappedValue != nil },
                    set: { value.wrappedValue = $0 ? 60 : nil }
                ))
            } footer: {
                Text("When the allowance runs out, the selected apps are shielded until tomorrow.")
            }
            if let minutes = value.wrappedValue {
                Section("Allowance") {
                    Picker("Per day", selection: Binding(
                        get: { minutes },
                        set: { value.wrappedValue = $0 }
                    )) {
                        ForEach(RecommendedSetupViewModel.allowanceOptions, id: \.self) { option in
                            Text(ProtectionSettings.formatDailyAllowance(option)).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        }
    }

    private var webContentEditor: some View {
        Section {
            Picker("Web Content", selection: $settings.webContent) {
                ForEach(WebContentLevel.allCases) { level in
                    VStack(alignment: .leading) {
                        Text(level.title)
                        Text(level.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(level)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } footer: {
            Text("Apple's filter blocks adult websites automatically. Specific sites can be added under App Restrictions.")
        }
    }

    private var appInstallationEditor: some View {
        Section {
            Picker("App Installation", selection: $settings.appInstallation) {
                ForEach(AppInstallationPolicy.allCases) { policy in
                    VStack(alignment: .leading) {
                        Text(policy.title)
                        Text(policy.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(policy)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } footer: {
            Text("Parent approval uses Apple's Ask to Buy, which is finished in Settings.")
        }
    }
}

#Preview {
    NavigationStack {
        RecommendedSetupView()
    }
    .environment({
        let model = AppModel.mock()
        model.chooseProfile(.balanced)
        return model
    }())
    .environment(AppRouter())
}
