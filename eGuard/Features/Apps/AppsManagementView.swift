import Observation
import SwiftUI

/// Loads a child's apps and applies rule changes.
@Observable
final class AppsManagementViewModel {
    var filter: AppsFilter = .installed
    var state: LoadState<AppsResponse> = .loading
    var websiteRequests: [BrowserAccessRequest] = []
    var isAdding = false
    var newAppName = ""
    var newAppApproval: AppApproval = .allowed
    var errorMessage: String?
    var limitEditing: ChildApp?
    var websiteRequestToApprove: BrowserAccessRequest?

    func load(childId: String, api: EGuardAPIService) async {
        if state.value == nil { state = .loading }
        state = await eGuard.load { try await api.apps(childId: childId, filter: filter) }
        // Website requests come from the browser extension and show alongside app requests.
        websiteRequests = (try? await api.browserAccessRequests(childId: childId))?.pending ?? []
    }

    func setAllowed(_ allowed: Bool, app: ChildApp, childId: String, api: EGuardAPIService) async {
        do {
            _ = try await api.updateApp(id: app.id, patch: AppPatch(approval: allowed ? .allowed : .blocked))
            await load(childId: childId, api: api)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLimit(_ minutes: Int?, app: ChildApp, childId: String, api: EGuardAPIService) async {
        do {
            _ = try await api.updateApp(id: app.id, patch: AppPatch(approval: nil, dailyLimitMinutes: minutes, removeLimit: minutes == nil))
            await load(childId: childId, api: api)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addApp(childId: String, api: EGuardAPIService) async -> Bool {
        do {
            _ = try await api.addApp(childId: childId, name: newAppName.trimmingCharacters(in: .whitespaces), approval: newAppApproval, dailyLimitMinutes: nil)
            newAppName = ""
            await load(childId: childId, api: api)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func decideWebsite(_ request: BrowserAccessRequest, decision: BrowserAccessDecision, childId: String, api: EGuardAPIService) async {
        do {
            _ = try await api.decideBrowserAccessRequest(id: request.id, decision: decision)
            await load(childId: childId, api: api)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 13 App Management, from `GET /children/{id}/apps?filter=`.
struct AppsManagementView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @State private var viewModel = AppsManagementViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        EGuardScreen {
            PillSegmentedControl(options: AppsFilter.allCases, selection: $viewModel.filter) { filter in
                if let counts = viewModel.state.value?.counts {
                    let count = switch filter {
                    case .installed: counts.installed
                    case .blocked: counts.blocked
                    case .pending: counts.pending + (filter == .pending ? viewModel.websiteRequests.count : 0)
                    }
                    return count > 0 ? "\(filter.title) (\(count))" : filter.title
                }
                return filter.title
            }

            switch viewModel.state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await viewModel.load(childId: childId, api: model.api) } }
            case .loaded(let response):
                if viewModel.filter == .pending, !viewModel.websiteRequests.isEmpty {
                    websiteRequestsCard
                }
                if response.apps.isEmpty {
                    if viewModel.filter != .pending || viewModel.websiteRequests.isEmpty {
                        EGuardCard {
                            EmptyStateView(symbolName: "square.grid.2x2", title: emptyTitle, message: emptyMessage, tint: EGuardColors.tilePurple)
                        }
                    }
                } else {
                    EGuardCard {
                        ForEach(response.apps) { app in
                            appRow(app)
                            if app.id != response.apps.last?.id { Divider() }
                        }
                    }
                }
                if let limited = response.limited {
                    // The plan names only this many apps. Neutral wording: no upgrade call to action on iOS.
                    EGuardCard {
                        Label("\(limited.hidden) more app\(limited.hidden == 1 ? "" : "s") not shown", systemImage: "eye.slash.fill")
                            .font(EGuardTypography.headline)
                            .foregroundStyle(EGuardColors.textSecondary)
                        Text(APIClient.storeSafeMessage(limited.message, status: 409))
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                }
            }

            InlineError(message: viewModel.errorMessage)

            EGuardCard {
                Label("Switch an app off to block it. Approving or declining a request also clears its alert. Devices pick up changes on their next sync, within about 5 minutes.", systemImage: "info.circle.fill")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            Button("Request to Install App") { viewModel.isAdding = true }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("apps.requestInstall")
        }
        .navigationTitle("App Management")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.filter) { await viewModel.load(childId: childId, api: model.api) }
        .alert("Add an app", isPresented: $viewModel.isAdding) {
            TextField("App name", text: $viewModel.newAppName)
            Button("Add") { Task { _ = await viewModel.addApp(childId: childId, api: model.api) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app is allowed ahead of time, so your child can install it without asking.")
        }
        .sheet(item: $viewModel.limitEditing) { app in
            AppLimitSheet(app: app) { minutes in
                Task { await viewModel.setLimit(minutes, app: app, childId: childId, api: model.api) }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Allow \(viewModel.websiteRequestToApprove?.domain ?? "this site") for how long?", isPresented: Binding(get: { viewModel.websiteRequestToApprove != nil }, set: { if !$0 { viewModel.websiteRequestToApprove = nil } }), titleVisibility: .visible) {
            ForEach(BrowserAccessDuration.allCases) { duration in
                Button(duration.title) {
                    guard let request = viewModel.websiteRequestToApprove else { return }
                    viewModel.websiteRequestToApprove = nil
                    Task { await viewModel.decideWebsite(request, decision: .approve(duration), childId: childId, api: model.api) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"Always\" adds the site to the allowed list. The browser picks up the answer within 5 minutes.")
        }
    }

    private var emptyTitle: String {
        switch viewModel.filter {
        case .installed: "No apps yet"
        case .blocked: "Nothing is blocked"
        case .pending: "No requests waiting"
        }
    }

    private var emptyMessage: String {
        switch viewModel.filter {
        case .installed: "Apps appear here as soon as the paired device reports them."
        case .blocked: "Switch an app off in the Installed list to block it."
        case .pending: "When your child asks for an app or a website, it shows up here for approval."
        }
    }

    /// Sites the child asked to open from the browser extension's block page.
    private var websiteRequestsCard: some View {
        EGuardCard {
            SectionHeader(title: "Website requests")
            ForEach(viewModel.websiteRequests) { request in
                HStack(spacing: EGuardSpacing.sm) {
                    IconTile(symbolName: "globe", tint: EGuardColors.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.domain).font(EGuardTypography.label)
                        Text(request.reason ?? request.createdAt.relativeDescription())
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                    Spacer()
                    Button("Deny") { Task { await viewModel.decideWebsite(request, decision: .deny, childId: childId, api: model.api) } }
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.danger)
                    Button("Allow") { viewModel.websiteRequestToApprove = request }
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.primary)
                }
                .padding(.vertical, EGuardSpacing.xxs)
                .accessibilityIdentifier("apps.webrequest.\(request.id)")
                if request.id != viewModel.websiteRequests.last?.id { Divider() }
            }
        }
    }

    private func appRow(_ app: ChildApp) -> some View {
        HStack(spacing: EGuardSpacing.sm) {
            IconTile(symbolName: "app.fill", tint: app.approval == .blocked ? EGuardColors.danger : (app.isRequested ? EGuardColors.warning : EGuardColors.primary))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(EGuardTypography.label)
                Text(app.subtitle)
                    .font(EGuardTypography.caption)
                    .foregroundStyle(app.approval == .blocked ? EGuardColors.danger : EGuardColors.textSecondary)
            }
            Spacer()
            if app.isRequested {
                // Either answer resolves the request, even for an app that is already blocked.
                Button("Decline") { Task { await viewModel.setAllowed(false, app: app, childId: childId, api: model.api) } }
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.danger)
                Button("Approve") { Task { await viewModel.setAllowed(true, app: app, childId: childId, api: model.api) } }
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.primary)
            } else {
                Toggle("Allowed", isOn: Binding(
                    get: { app.allowed },
                    set: { value in Task { await viewModel.setAllowed(value, app: app, childId: childId, api: model.api) } }
                ))
                .labelsHidden()
                .tint(EGuardColors.primary)
            }
        }
        .padding(.vertical, EGuardSpacing.xxs)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Set daily limit", systemImage: "hourglass") { viewModel.limitEditing = app }
            if app.dailyLimitMinutes != nil {
                Button("Remove limit", systemImage: "hourglass.badge.minus") { Task { await viewModel.setLimit(nil, app: app, childId: childId, api: model.api) } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("apps.row.\(app.id)")
    }
}

/// Picks a per-app daily limit.
struct AppLimitSheet: View {
    let app: ChildApp
    let onSave: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int

    init(app: ChildApp, onSave: @escaping (Int?) -> Void) {
        self.app = app
        self.onSave = onSave
        _minutes = State(initialValue: app.dailyLimitMinutes ?? 60)
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
            .navigationTitle("\(app.name) limit")
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

#Preview {
    NavigationStack {
        AppsManagementView(childId: "child_1")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
