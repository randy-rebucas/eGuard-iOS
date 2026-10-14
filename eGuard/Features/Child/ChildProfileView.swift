import SwiftUI

/// 11 Child Profile: `GET /children/{id}` with Overview / Activity / Apps / Protection / History tabs.
struct ChildProfileView: View {
    private enum Section: String, CaseIterable {
        case overview = "Overview"
        case activity = "Activity"
        case apps = "Apps"
        case protection = "Protection"
        case history = "History"
    }

    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<ChildDetail> = .loading
    @State private var history: LoadState<HistoryPage> = .loading
    @State private var section: Section = .overview
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?
    @State private var isPairing = false
    @State private var isLoadingMoreHistory = false
    @State private var historyMoreError: String?
    @State private var photoError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
                switch state {
                case .loading:
                    LoadingCard().padding(.horizontal, EGuardSpacing.md)
                case .failed(let message):
                    ErrorCard(message: message) { Task { await loadChild() } }.padding(.horizontal, EGuardSpacing.md)
                case .loaded(let detail):
                    header(detail)
                    PillSegmentedControl(options: Section.allCases, selection: $section) { $0.rawValue }
                        .padding(.horizontal, EGuardSpacing.md)
                    Group {
                        switch section {
                        case .overview: overview(detail)
                        case .activity: activity(detail)
                        case .apps: apps(detail)
                        case .protection: protection(detail)
                        case .history: historySection
                        }
                    }
                    .padding(.horizontal, EGuardSpacing.md)
                }
            }
            .padding(.bottom, EGuardSpacing.xl)
        }
        .background(EGuardColors.background)
        .navigationTitle(state.value?.child.name ?? "Child")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit child", systemImage: "pencil") { router.push(.editChild(childId: childId)) }
                    // A photo can be changed in Edit child; this was the only way to go back to initials
                    if state.value?.child.photoUrl != nil {
                        Button("Remove photo", systemImage: "person.crop.circle.badge.minus") { Task { await removePhoto() } }
                    }
                    Button("Change protection profile", systemImage: "shield.lefthalf.filled") { router.push(.protectionProfile(childId: childId)) }
                    Button("Manage protection", systemImage: "slider.horizontal.3") { router.push(.protections(childId: childId)) }
                    if model.user?.isAdmin == true {
                        Button("Delete child", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .task { await loadChild() }
        // Every tab comes from the child's detail; History has its own first page
        .refreshable {
            await loadChild()
            if section == .history {
                history = await load { try await model.api.history(childId: childId, before: nil) }
            }
        }
        .sheet(isPresented: $isPairing, onDismiss: { Task { await loadChild() } }) {
            PairingCodeView(childId: childId)
        }
        .task(id: section) {
            if section == .history, history.value == nil {
                history = await load { try await model.api.history(childId: childId, before: nil) }
            }
        }
        .deletionConfirmation(
            "Delete \(state.value?.child.name ?? "child")?",
            message: "This permanently deletes the child, their devices, and all their data.",
            isPresented: $isConfirmingDelete,
            user: model.user
        ) { confirmation in
            Task { await deleteChild(confirmation) }
        }
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Couldn't remove the photo", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoError ?? "")
        }
    }

    private func removePhoto() async {
        do {
            try await model.api.deletePhoto(childId: childId)
            await loadChild()
            await model.refreshDashboard()
        } catch {
            photoError = error.localizedDescription
        }
    }

    private func loadChild() async {
        if state.value == nil { state = .loading }
        state = await load { try await model.api.child(id: childId) }
    }

    private func deleteChild(_ confirmation: DeletionConfirmation) async {
        do {
            try await model.api.deleteChild(id: childId, confirmation: confirmation)
            await model.refreshDashboard()
            router.popToRoot()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    // MARK: Header

    private func header(_ detail: ChildDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            FamilyIllustration(height: 200)
            HStack(alignment: .bottom, spacing: EGuardSpacing.sm) {
                ChildAvatar(child: detail.child, size: 72)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.child.name)
                        .font(EGuardTypography.title)
                        .foregroundStyle(EGuardColors.textPrimary)
                    Text(detail.child.ageDescription)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                Spacer()
                StatusPill(text: detail.child.status.title, tint: statusTint(detail.child.status))
                    .background(.white.opacity(0.9), in: Capsule())
            }
            .padding(EGuardSpacing.md)
        }
        .padding(.horizontal, EGuardSpacing.md)
    }

    // MARK: Sections

    private func overview(_ detail: ChildDetail) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.md) {
            EGuardCard {
                Text("Screen time today")
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: EGuardSpacing.xs) {
                    Text(ProtectionConfigFormatter.duration(detail.today.minutes))
                        .font(EGuardTypography.metric)
                    if let limit = detail.today.limitMinutes {
                        Text("/ \(ProtectionConfigFormatter.duration(limit))")
                            .font(EGuardTypography.callout)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                }
                if let limit = detail.today.limitMinutes {
                    ProgressView(value: Double(min(detail.today.minutes, limit)), total: Double(max(limit, 1)))
                        .tint(EGuardColors.primary)
                }
                if detail.child.deviceCount == 0 {
                    // Screen time comes from phones and tablets; a browser alone doesn't report it
                    Text(detail.child.isBrowserOnly ? "Browser only. Pair a phone or tablet to see screen time." : "Pair a device to see screen time.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }

            EGuardCard {
                EGuardNavRow(title: "App usage", subtitle: detail.today.appsUsed == 0 ? "No apps used today" : "\(detail.today.appsUsed) apps today" + (detail.pendingApprovals > 0 ? " · \(detail.pendingApprovals) waiting for approval" : ""), symbolName: "square.grid.2x2.fill", tint: EGuardColors.success) {
                    router.push(.appsManagement(childId: childId))
                }
                Divider()
                EGuardNavRow(title: "Bedtime", subtitle: detail.bedtime?.label ?? "Off", symbolName: "moon.zzz.fill", tint: EGuardColors.tilePurple) {
                    router.push(.protectionEditor(childId: childId, key: "BEDTIME"))
                }
                Divider()
                EGuardNavRow(title: "Location", subtitle: detail.location.label, symbolName: "location.fill", tint: EGuardColors.success) {
                    router.push(.location(childId: childId))
                }
                Divider()
                EGuardNavRow(title: "Device protection", subtitle: "\(detail.deviceProtection.label) · \(detail.health.healthScore.text)\(detail.health.healthScore.isVerified ? " verified" : (detail.health.healthScore.offlineCount > 0 ? " last known" : ""))", symbolName: "checkmark.shield.fill", tint: statusTint(detail.child.status)) {
                    router.push(.healthCheck(childId: childId, isOnboarding: false))
                }
            }

            if detail.location.locationState == .planRequired {
                Text("Location sharing isn't included in your plan.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }

            if !detail.devices.isEmpty {
                EGuardCard {
                    SectionHeader(title: "Devices")
                    ForEach(detail.devices) { device in
                        EGuardNavRow(title: device.name, subtitle: [device.statusTitle, device.lastSeenLabel].compactMap { $0 }.joined(separator: " · "), symbolName: device.symbolName, tint: deviceTint(device)) {
                            router.push(.deviceDetail(deviceId: device.id))
                        }
                        if device.id != detail.devices.last?.id { Divider() }
                    }
                }
            }
            // Pairs only, as the web's "Pair a device": the child's saved protections apply when the device pairs.
            // (Running Setup here would send a profile and replace whatever the parent had set.)
            Button("Pair a device") { isPairing = true }
                .buttonStyle(detail.devices.isEmpty ? AnyButtonStyle(.eGuardPrimary) : AnyButtonStyle(.eGuardSecondary))
                .accessibilityIdentifier("child.pairDevice")
        }
    }

    private func activity(_ detail: ChildDetail) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.md) {
            EGuardCard {
                SectionHeader(title: "Top apps today")
                if detail.today.topApps.isEmpty {
                    Text("No activity recorded today.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                ForEach(detail.today.topApps) { app in
                    EGuardValueRow(label: app.name, value: ProtectionConfigFormatter.duration(app.minutes))
                }
            }
            Button("Open Screen Time") { router.push(.screenTime(childId: childId)) }
                .buttonStyle(.eGuardPrimary)
        }
    }

    private func apps(_ detail: ChildDetail) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.md) {
            EGuardCard {
                EGuardValueRow(label: "Apps used today", value: "\(detail.today.appsUsed)")
                Divider()
                EGuardValueRow(label: "Waiting for approval", value: "\(detail.pendingApprovals)")
            }
            Button(detail.pendingApprovals > 0 ? "Review \(detail.pendingApprovals) Request\(detail.pendingApprovals == 1 ? "" : "s")" : "Manage Apps") {
                router.push(.appsManagement(childId: childId, pending: detail.pendingApprovals > 0))
            }
            .buttonStyle(.eGuardPrimary)
        }
    }

    private func protection(_ detail: ChildDetail) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.md) {
            EGuardCard {
                ForEach(detail.health.checks) { check in
                    Button {
                        router.push(.protectionEditor(childId: childId, key: check.key))
                    } label: {
                        HStack {
                            ChecklistRow(title: check.name, detail: check.detail, status: check.displayStatus)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(EGuardColors.neutral)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if check.id != detail.health.checks.last?.id { Divider() }
                }
            }
            Button("Manage Protection") { router.push(.protections(childId: childId)) }
                .buttonStyle(.eGuardPrimary)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        switch history {
        case .loading:
            LoadingCard()
        case .failed(let message):
            ErrorCard(message: message) { Task { history = await load { try await model.api.history(childId: childId, before: nil) } } }
        case .loaded(let page):
            EGuardCard {
                if page.changes.isEmpty {
                    Text("No configuration changes yet.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                ForEach(page.changes) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.title).font(EGuardTypography.label)
                        if let from = change.fromValue, let to = change.toValue {
                            Text("\(from) → \(to)").font(EGuardTypography.caption).foregroundStyle(EGuardColors.textSecondary)
                        }
                        Text("\(change.actor) · \(change.timeLabel ?? change.createdAt.verifiedDescription())")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                    .padding(.vertical, EGuardSpacing.xxs)
                    if change.id != page.changes.last?.id { Divider() }
                }
            }
            // The server sends 30 at a time; older changes were unreachable without this
            if let before = page.nextBefore {
                Button(isLoadingMoreHistory ? "Loading…" : "Load more") { Task { await loadMoreHistory(page, before: before) } }
                    .buttonStyle(.eGuardSecondary)
                    .disabled(isLoadingMoreHistory)
                    .accessibilityIdentifier("child.history.loadMore")
            }
            InlineError(message: historyMoreError)
        }
    }

    private func loadMoreHistory(_ page: HistoryPage, before: Date) async {
        isLoadingMoreHistory = true
        historyMoreError = nil
        defer { isLoadingMoreHistory = false }
        do {
            let next = try await model.api.history(childId: childId, before: before)
            history = .loaded(HistoryPage(changes: page.changes + next.changes, nextBefore: next.nextBefore))
        } catch {
            historyMoreError = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ChildProfileView(childId: "child_1")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
#endif
