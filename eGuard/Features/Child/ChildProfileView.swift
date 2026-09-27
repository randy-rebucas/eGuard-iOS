import DeviceActivity
import SwiftUI

/// 11 Child Profile: photo header, status, and Overview / Activity / Apps / Protection tabs.
struct ChildProfileView: View {
    private enum Section: String, CaseIterable {
        case overview = "Overview"
        case activity = "Activity"
        case apps = "Apps"
        case protection = "Protection"
    }

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var section: Section = .overview

    private var report: ConfigurationHealthReport? { model.lastHealthReport }
    private var state: ProtectionState { report?.protectionState ?? .notConfigured }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
                if let child = model.childProfile {
                    header(child)
                    PillSegmentedControl(options: Section.allCases, selection: $section) { $0.rawValue }
                        .padding(.horizontal, EGuardSpacing.md)

                    Group {
                        switch section {
                        case .overview: overview(child)
                        case .activity: activity
                        case .apps: apps
                        case .protection: protection
                        }
                    }
                    .padding(.horizontal, EGuardSpacing.md)
                } else {
                    EmptyStateView(
                        symbolName: "person.crop.circle.badge.plus",
                        title: "No child added yet",
                        message: "Add the child who uses this device to see their profile."
                    )
                    Button("Add Child") { router.push(.childDevice) }
                        .buttonStyle(.eGuardPrimary)
                        .padding(.horizontal, EGuardSpacing.md)
                }
            }
            .padding(.bottom, EGuardSpacing.xl)
        }
        .background(EGuardColors.background)
        .navigationTitle(model.childProfile?.trimmedName ?? "Child")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit child & device", systemImage: "pencil") { router.push(.childDevice) }
                    Button("Change protection profile", systemImage: "shield.lefthalf.filled") { router.push(.protectionProfile) }
                    Button("Manage protection", systemImage: "slider.horizontal.3") { router.push(.manageProtection) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
    }

    // MARK: Header

    private func header(_ child: ChildProfile) -> some View {
        ZStack(alignment: .bottomLeading) {
            FamilyIllustration(height: 220)
                .overlay(
                    LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: EGuardShapes.cardRadius, style: .continuous))
            if let data = child.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: EGuardShapes.cardRadius, style: .continuous))
                    .overlay(
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: EGuardShapes.cardRadius, style: .continuous))
                    )
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.trimmedName)
                        .font(EGuardTypography.title)
                        .foregroundStyle(child.photoData == nil ? EGuardColors.textPrimary : .white)
                    Text(child.ageDescription)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(child.photoData == nil ? EGuardColors.textSecondary : .white.opacity(0.9))
                }
                Spacer()
                StatusPill(
                    text: state == .active ? "Protected" : (state == .needsAttention ? "Attention" : "Not set up"),
                    tint: EGuardTheme.color(for: state)
                )
                .background(.white.opacity(0.9), in: Capsule())
            }
            .padding(EGuardSpacing.md)
        }
        .padding(.horizontal, EGuardSpacing.md)
    }

    // MARK: Sections

    private func overview(_ child: ChildProfile) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.md) {
            EGuardCard {
                Text("Screen time today")
                    .font(EGuardTypography.label)
                    .foregroundStyle(EGuardColors.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: EGuardSpacing.xs) {
                    if model.authorizationStatus.isAuthorized && !model.environment.isSimulator {
                        DeviceActivityReport(.eGuardToday, filter: DashboardViewModel().todayFilter())
                            .frame(height: 36)
                    } else {
                        Text("—")
                            .font(EGuardTypography.metric)
                    }
                    if let allowance = totalAllowanceText {
                        Text("/ \(allowance)")
                            .font(EGuardTypography.callout)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                }
                ProgressView(value: report.map { Double($0.passedCount) / Double(max($0.evaluatedCount, 1)) } ?? 0)
                    .tint(EGuardColors.primary)
                    .accessibilityLabel("Protection coverage")
                Text(model.authorizationStatus.isAuthorized && !model.environment.isSimulator
                     ? "Screen time is measured by Apple and shown here without leaving the device."
                     : "Screen time appears on a real, authorized device.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }

            EGuardCard {
                EGuardNavRow(title: "App usage", subtitle: appUsageSubtitle, symbolName: "square.grid.2x2.fill", tint: EGuardColors.success) {
                    router.push(.appsManagement)
                }
                Divider()
                EGuardNavRow(title: "Bedtime", subtitle: model.settings.downtime?.formatted ?? "Off", symbolName: ProtectionFeature.downtime.symbolName, tint: EGuardTheme.tint(for: .downtime)) {
                    router.push(.featureDetail(.downtime))
                }
                Divider()
                EGuardNavRow(title: "Location", subtitle: model.preferences.isLocationSharingEnabled ? "Sharing enabled" : "Sharing off", symbolName: "location.fill", tint: EGuardColors.success) {
                    router.push(.location)
                }
                Divider()
                EGuardNavRow(title: "Device protection", subtitle: EGuardTheme.grade(passed: report?.passedCount ?? 0, total: report?.evaluatedCount ?? 0), symbolName: "checkmark.shield.fill", tint: EGuardTheme.color(for: state)) {
                    router.push(.healthReview)
                }
            }
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.md) {
            EGuardCard {
                SectionHeader(title: "Daily allowances")
                if model.settings.gamingLimitMinutes == nil && model.settings.socialAppsLimitMinutes == nil {
                    Text("No daily allowances are set.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                if let minutes = model.settings.gamingLimitMinutes {
                    EGuardNavRow(title: "Gaming", subtitle: ProtectionSettings.formatDailyAllowance(minutes), symbolName: ProtectionFeature.gaming.symbolName, tint: EGuardTheme.tint(for: .gaming)) {
                        router.push(.featureDetail(.gaming))
                    }
                }
                if let minutes = model.settings.socialAppsLimitMinutes {
                    Divider()
                    EGuardNavRow(title: "Social apps", subtitle: ProtectionSettings.formatDailyAllowance(minutes), symbolName: ProtectionFeature.socialApps.symbolName, tint: EGuardTheme.tint(for: .socialApps)) {
                        router.push(.featureDetail(.socialApps))
                    }
                }
            }
            Button("Open Screen Time") { router.push(.screenTime) }
                .buttonStyle(.eGuardPrimary)
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.md) {
            EGuardCard {
                EGuardValueRow(label: "Gaming apps", value: model.selections.gaming.summary)
                Divider()
                EGuardValueRow(label: "Social apps", value: model.selections.socialApps.summary)
                Divider()
                EGuardValueRow(label: "Always blocked", value: model.selections.restrictedApps.summary)
                Divider()
                EGuardValueRow(label: "New app downloads", value: model.settings.appInstallation.title)
            }
            Button("Manage Apps") { router.push(.appsManagement) }
                .buttonStyle(.eGuardPrimary)
        }
    }

    private var protection: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.md) {
            EGuardCard {
                if let report, !report.checks.isEmpty {
                    ForEach(report.checks) { check in
                        Button {
                            router.push(.featureDetail(check.feature))
                        } label: {
                            HStack {
                                ChecklistRow(title: check.feature.title, detail: model.settings.summary(for: check.feature), status: check.status)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(EGuardColors.neutral)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if check.id != report.checks.last?.id { Divider() }
                    }
                } else {
                    Text("No protections are configured yet.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            Button("Manage Protection") { router.push(.manageProtection) }
                .buttonStyle(.eGuardPrimary)
        }
    }

    // MARK: Helpers

    private var totalAllowanceText: String? {
        let total = (model.settings.gamingLimitMinutes ?? 0) + (model.settings.socialAppsLimitMinutes ?? 0)
        guard total > 0 else { return nil }
        return ProtectionSettings.formatDailyAllowance(total).replacingOccurrences(of: " / day", with: "")
    }

    private var appUsageSubtitle: String {
        let count = model.selections.gaming.applicationCount + model.selections.socialApps.applicationCount + model.selections.restrictedApps.applicationCount
        return count == 0 ? "No apps managed yet" : (count == 1 ? "1 app managed" : "\(count) apps managed")
    }
}

#Preview {
    NavigationStack {
        ChildProfileView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
