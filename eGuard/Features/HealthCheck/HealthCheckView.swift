import SwiftUI

/// 08 Configuration Health, from `GET /health[?childId=]`. Also opened from the dashboard for the whole family.
struct HealthCheckView: View {
    let childId: String?
    let isOnboarding: Bool

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<HealthReport> = .loading
    @State private var isRunningCheck = false

    private var report: HealthReport? { state.value }

    var body: some View {
        EGuardScreen {
            if isOnboarding {
                OnboardingProgressIndicator(step: .healthCheck)
                ScreenHeader(title: "Configuration Health")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            switch state {
            case .loading:
                LoadingCard(message: "Checking every protection…")
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadReport() } }
            case .loaded(let report):
                scoreGauge(report)
                if let children = report.children, children.count > 1 {
                    childrenCard(children)
                }
                checksCard(report)
                if report.fixCount > 0 {
                    attentionCard(report)
                }
            }
        } actions: {
            if isOnboarding {
                Button(fixTitle ?? "Continue") {
                    if let fix = report?.toFix?.first {
                        router.push(.protectionEditor(childId: fix.childId, key: fix.key))
                    } else if let childId {
                        router.push(.complete(childId: childId, batchId: nil))
                    }
                }
                .buttonStyle(.eGuardPrimary)
                .disabled(report == nil)
                .accessibilityIdentifier(fixTitle == nil ? "health.continue" : "health.fix")
                if fixTitle != nil, let childId {
                    Button("Continue anyway") { router.push(.complete(childId: childId, batchId: nil)) }
                        .buttonStyle(.eGuardText)
                        .accessibilityIdentifier("health.continue")
                }
            } else {
                if let fixTitle {
                    Button(fixTitle) {
                        if let fix = report?.toFix?.first {
                            router.push(.protectionEditor(childId: fix.childId, key: fix.key))
                        }
                    }
                    .buttonStyle(.eGuardPrimary)
                    .accessibilityIdentifier("health.fix")
                }
                Button(isRunningCheck ? "Asking devices…" : "Check Again") { Task { await runCheck() } }
                    .buttonStyle(fixTitle == nil ? AnyButtonStyle(.eGuardPrimary) : AnyButtonStyle(.eGuardText))
                    .disabled(isRunningCheck)
                    .accessibilityIdentifier("health.checkAgain")
            }
        }
        .modifier(HealthTitle(isOnboarding: isOnboarding))
        .task { await loadReport() }
    }

    private var fixTitle: String? {
        guard let count = report?.fixCount, count > 0 else { return nil }
        return count == 1 ? "Fix 1 Setting" : "Fix \(count) Settings"
    }

    private func loadReport() async {
        state = .loading
        state = await load { try await model.api.health(childId: childId) }
    }

    /// Asks every device for a fresh report, waits for it, then reloads.
    private func runCheck() async {
        isRunningCheck = true
        defer { isRunningCheck = false }
        do {
            let runId = try await model.api.startCheck(deviceId: nil)
            let started = Date.now
            while Date.now.timeIntervalSince(started) < 15 {
                let run = try await model.api.check(runId: runId)
                if run.done { break }
                try? await Task.sleep(for: BatchPoller.interval)
            }
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        await loadReport()
        await model.refreshDashboard()
    }

    // MARK: Cards

    private func scoreGauge(_ report: HealthReport) -> some View {
        let score = report.healthScore
        let tint = tintColor(score)
        return VStack(spacing: EGuardSpacing.sm) {
            RingGauge(progress: score.fraction, tint: tint, lineWidth: 16, size: 170) {
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(score.score)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(EGuardColors.textPrimary)
                        Text("/ \(score.total)")
                            .font(EGuardTypography.title3)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                    Text(score.grade)
                        .font(EGuardTypography.label)
                        .foregroundStyle(tint)
                }
            }
            .accessibilityLabel("Health score \(score.text). \(score.grade)")
            .accessibilityIdentifier("health.score")

            Text("The score measures configuration, not your child's behavior. Unsupported settings never count against it.")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func tintColor(_ score: HealthScore) -> Color {
        if score.total == 0 { return EGuardColors.neutral }
        if score.score >= score.total { return EGuardColors.success }
        if score.score >= 8 { return EGuardColors.tileYellow }
        if score.score >= 5 { return EGuardColors.warning }
        return EGuardColors.danger
    }

    private func childrenCard(_ children: [ChildHealth]) -> some View {
        EGuardCard {
            SectionHeader(title: "By child")
            ForEach(children) { child in
                HStack {
                    Text(child.name).font(EGuardTypography.label)
                    Spacer()
                    Text("\(child.score) / \(child.total)").font(EGuardTypography.label).foregroundStyle(EGuardColors.textSecondary)
                    StatusPill(text: child.status.title, tint: child.status == .protected ? EGuardColors.success : (child.status == .attention ? EGuardColors.warning : EGuardColors.neutral))
                }
                .padding(.vertical, EGuardSpacing.xxs)
                if child.id != children.last?.id { Divider() }
            }
        }
    }

    private func checksCard(_ report: HealthReport) -> some View {
        EGuardCard {
            ForEach(report.checks) { check in
                Button {
                    if let fixChildId = check.fixChildId ?? childId {
                        router.push(.protectionEditor(childId: fixChildId, key: check.key))
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: EGuardSpacing.sm) {
                        Image(systemName: EGuardTheme.symbol(for: check.status.healthStatus))
                            .foregroundStyle(EGuardTheme.color(for: check.status.healthStatus))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name)
                                .font(EGuardTypography.label)
                                .foregroundStyle(EGuardColors.textPrimary)
                            if let detail = check.detail {
                                Text(detail)
                                    .font(EGuardTypography.caption)
                                    .foregroundStyle(EGuardColors.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer()
                        HealthStatusBadge(status: check.status.healthStatus)
                    }
                    .padding(.vertical, EGuardSpacing.xxs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(check.status == .unsupported || (check.fixChildId == nil && childId == nil))
                .accessibilityIdentifier("health.check.\(check.key.lowercased())")
                if check.id != report.checks.last?.id { Divider() }
            }
        }
    }

    private func attentionCard(_ report: HealthReport) -> some View {
        EGuardCard {
            Label(report.fixCount == 1 ? "One setting needs review" : "\(report.fixCount) settings need review", systemImage: "exclamationmark.triangle.fill")
                .font(EGuardTypography.headline)
                .foregroundStyle(EGuardColors.warning)
            ForEach(report.toFix ?? []) { fix in
                EGuardNavRow(title: fix.name, subtitle: fix.detail, symbolName: ProtectionKey.symbol(fix.key), tint: LucideIcon.tint(forKey: fix.key)) {
                    router.push(.protectionEditor(childId: fix.childId, key: fix.key))
                }
            }
        }
    }
}

private struct HealthTitle: ViewModifier {
    let isOnboarding: Bool

    func body(content: Content) -> some View {
        if isOnboarding {
            content.brandNavigationTitle()
        } else {
            content
                .navigationTitle("Configuration Health")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        HealthCheckView(childId: nil, isOnboarding: false)
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
