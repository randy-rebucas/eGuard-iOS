import FamilyControls
import ManagedSettings
import Observation
import SwiftUI

/// Manages which selected apps are always shielded. Apple never reveals installed apps to eGuard,
/// so the list is built from the apps the parent chose in Apple's picker.
@Observable
final class AppsManagementViewModel {
    enum Tab: String, CaseIterable {
        case managed = "Managed"
        case blocked = "Blocked"
    }

    var tab: Tab = .managed
    var isChoosingApps = false

    func selection(_ purpose: SelectionPurpose, model: AppModel) -> FamilyActivitySelection {
        ActivitySelectionCodec.selection(from: model.selections[purpose]) ?? FamilyActivitySelection(includeEntireCategory: true)
    }

    /// Every app the parent has selected for any purpose.
    func managedApps(model: AppModel) -> [ApplicationToken] {
        var tokens = Set<ApplicationToken>()
        for purpose in [SelectionPurpose.gaming, .socialApps, .restrictedApps] {
            tokens.formUnion(selection(purpose, model: model).applicationTokens)
        }
        return Array(tokens)
    }

    func managedCategories(model: AppModel) -> [ActivityCategoryToken] {
        var tokens = Set<ActivityCategoryToken>()
        for purpose in [SelectionPurpose.gaming, .socialApps, .restrictedApps] {
            tokens.formUnion(selection(purpose, model: model).categoryTokens)
        }
        return Array(tokens)
    }

    func blockedApps(model: AppModel) -> [ApplicationToken] {
        Array(selection(.restrictedApps, model: model).applicationTokens)
    }

    func blockedCategories(model: AppModel) -> [ActivityCategoryToken] {
        Array(selection(.restrictedApps, model: model).categoryTokens)
    }

    func isBlocked(_ token: ApplicationToken, model: AppModel) -> Bool {
        selection(.restrictedApps, model: model).applicationTokens.contains(token)
    }

    func isBlocked(_ token: ActivityCategoryToken, model: AppModel) -> Bool {
        selection(.restrictedApps, model: model).categoryTokens.contains(token)
    }

    func setBlocked(_ blocked: Bool, app token: ApplicationToken, model: AppModel) {
        var restricted = selection(.restrictedApps, model: model)
        if blocked { restricted.applicationTokens.insert(token) } else { restricted.applicationTokens.remove(token) }
        apply(restricted, model: model)
    }

    func setBlocked(_ blocked: Bool, category token: ActivityCategoryToken, model: AppModel) {
        var restricted = selection(.restrictedApps, model: model)
        if blocked { restricted.categoryTokens.insert(token) } else { restricted.categoryTokens.remove(token) }
        apply(restricted, model: model)
    }

    /// Saves the shield list and re-applies it immediately so the change is real, not just recorded.
    private func apply(_ restricted: FamilyActivitySelection, model: AppModel) {
        let snapshot = ActivitySelectionCodec.snapshot(from: restricted)
        model.updateSelection(snapshot, for: .restrictedApps)
        var settings = model.settings
        settings.restrictSelectedApps = !snapshot.isEmpty
        model.updateSettings(settings)
        if snapshot.isEmpty {
            try? model.restrictions.applyAppRestrictions(.empty)
        } else if model.authorizationStatus.isAuthorized {
            model.configure(.appRestrictions)
        }
    }
}

/// 13 Apps Management
struct AppsManagementView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var viewModel = AppsManagementViewModel()

    private var pickerAvailable: Bool {
        model.authorizationStatus.isAuthorized && !model.environment.isSimulator
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            PillSegmentedControl(options: AppsManagementViewModel.Tab.allCases, selection: $viewModel.tab) { $0.rawValue }

            switch viewModel.tab {
            case .managed: managedList
            case .blocked: blockedList
            }

            EGuardCard {
                Label("Apple shows app names and icons here without telling eGuard which apps they are. Blocked apps are shielded at all times.", systemImage: "lock.shield")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            Button("Request to Install App") { router.push(.featureDetail(.appInstallation)) }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("apps.requestInstall")
            Button(pickerAvailable ? "Choose Apps to Manage" : "App picker needs a real device") {
                viewModel.isChoosingApps = true
            }
            .buttonStyle(.eGuardText)
            .disabled(!pickerAvailable)
        }
        .navigationTitle("App Management")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.isChoosingApps) {
            AppSelectionView(purpose: .restrictedApps)
        }
    }

    @ViewBuilder
    private var managedList: some View {
        let apps = viewModel.managedApps(model: model)
        let categories = viewModel.managedCategories(model: model)
        if apps.isEmpty && categories.isEmpty {
            emptyState(
                title: "No managed apps yet",
                message: pickerAvailable
                    ? "Choose the apps that daily allowances and shields apply to."
                    : "Apple's app picker is available on a real, authorized device."
            )
        } else {
            EGuardCard {
                ForEach(apps, id: \.self) { token in
                    appRow(token, isBlocked: viewModel.isBlocked(token, model: model)) { blocked in
                        viewModel.setBlocked(blocked, app: token, model: model)
                    }
                    Divider()
                }
                ForEach(categories, id: \.self) { token in
                    categoryRow(token, isBlocked: viewModel.isBlocked(token, model: model)) { blocked in
                        viewModel.setBlocked(blocked, category: token, model: model)
                    }
                    if token != categories.last { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private var blockedList: some View {
        let apps = viewModel.blockedApps(model: model)
        let categories = viewModel.blockedCategories(model: model)
        if apps.isEmpty && categories.isEmpty {
            emptyState(
                title: "Nothing is blocked",
                message: "Turn on Blocked for an app in the Managed list, or choose apps to shield at all times."
            )
        } else {
            EGuardCard {
                ForEach(apps, id: \.self) { token in
                    appRow(token, isBlocked: true) { blocked in
                        viewModel.setBlocked(blocked, app: token, model: model)
                    }
                    Divider()
                }
                ForEach(categories, id: \.self) { token in
                    categoryRow(token, isBlocked: true) { blocked in
                        viewModel.setBlocked(blocked, category: token, model: model)
                    }
                    if token != categories.last { Divider() }
                }
            }
        }
    }

    private func appRow(_ token: ApplicationToken, isBlocked: Bool, onToggle: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: EGuardSpacing.sm) {
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(EGuardTypography.label)
            Spacer()
            Text(isBlocked ? "Blocked" : "Allowed")
                .font(EGuardTypography.caption)
                .foregroundStyle(isBlocked ? EGuardColors.danger : EGuardColors.textSecondary)
            Toggle("Blocked", isOn: Binding(get: { isBlocked }, set: onToggle))
                .labelsHidden()
                .tint(EGuardColors.primary)
        }
        .padding(.vertical, EGuardSpacing.xxs)
    }

    private func categoryRow(_ token: ActivityCategoryToken, isBlocked: Bool, onToggle: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: EGuardSpacing.sm) {
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(EGuardTypography.label)
            Spacer()
            Text(isBlocked ? "Blocked" : "Allowed")
                .font(EGuardTypography.caption)
                .foregroundStyle(isBlocked ? EGuardColors.danger : EGuardColors.textSecondary)
            Toggle("Blocked", isOn: Binding(get: { isBlocked }, set: onToggle))
                .labelsHidden()
                .tint(EGuardColors.primary)
        }
        .padding(.vertical, EGuardSpacing.xxs)
    }

    private func emptyState(title: String, message: String) -> some View {
        EGuardCard {
            EmptyStateView(symbolName: "square.grid.2x2", title: title, message: message, tint: EGuardColors.tilePurple)
        }
    }
}

#Preview {
    NavigationStack {
        AppsManagementView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
