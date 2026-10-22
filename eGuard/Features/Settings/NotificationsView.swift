import SwiftUI
import UserNotifications

/// Notification preferences from `/me/notifications`, plus the iOS permission.
struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var state: LoadState<NotificationPrefs> = .loading
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        EGuardScreen {
            EGuardCard {
                HStack(spacing: EGuardSpacing.sm) {
                    IconTile(symbolName: "bell.badge.fill", tint: EGuardColors.tileOrange, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push notifications on this iPhone")
                            .font(EGuardTypography.headline)
                        Text(statusText)
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                    Spacer()
                }
                if status == .notDetermined {
                    Button("Allow Notifications") { request() }
                        .buttonStyle(.eGuardSecondary)
                } else if status == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.eGuardSecondary)
                }
            }

            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                ErrorCard(message: message) { Task { await loadPrefs() } }
            case .loaded(let prefs):
                EGuardCard {
                    SectionHeader(title: "What eGuard sends you")
                    // Off and locked on a plan without push, whatever the stored (default on) value says. The prefs
                    // carry `pushIncluded`; older servers don't, so fall back to the plan's entitlements.
                    let pushIncluded = prefs.pushIncluded ?? model.entitlements?.hasRealtimeAlerts ?? true
                    toggle("Push alerts", detail: pushIncluded ? "Protection changes, device issues, approvals" : "Not included in your plan. Alerts still show here and by email.",
                           symbol: "iphone.radiowaves.left.and.right", tint: pushIncluded ? EGuardColors.primary : EGuardColors.neutral, value: prefs.notifyPush && pushIncluded, enabled: pushIncluded) { NotificationPrefsPatch(notifyPush: $0) }
                    Divider()
                    toggle("Email alerts", detail: "The same alerts by email", symbol: "envelope.fill", tint: EGuardColors.tileTeal, value: prefs.notifyEmail) { NotificationPrefsPatch(notifyEmail: $0) }
                    Divider()
                    toggle("App approval requests", detail: "When your child asks for an app", symbol: "square.grid.2x2.fill", tint: EGuardColors.tilePurple, value: prefs.notifyApproval) { NotificationPrefsPatch(notifyApproval: $0) }
                    Divider()
                    toggle("Weekly summary", detail: "A recap of screen time and health every week", symbol: "calendar", tint: EGuardColors.tileOrange, value: prefs.weeklySummary) { NotificationPrefsPatch(weeklySummary: $0) }
                }
            }
            InlineError(message: errorMessage)

            Text(PushService.isAvailable
                 ? "Alerts that need attention are pushed to this iPhone within a few minutes. They always appear in the Alerts tab too."
                 : "Push delivery isn't set up in this build yet. Alerts always appear in the Alerts tab.")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        } actions: {
            EmptyView()
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadStatus()
            await loadPrefs()
        }
        // Another parent's or the web's change, or a plan change, shows on pull
        .refreshable {
            await loadStatus()
            await loadPrefs()
        }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Turned off in Settings"
        case .notDetermined: "Not requested yet"
        @unknown default: "Unknown"
        }
    }

    private func toggle(_ title: String, detail: String, symbol: String, tint: Color, value: Bool, enabled: Bool = true, patch: @escaping (Bool) -> NotificationPrefsPatch) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in
                // One change at a time, so answers can't arrive out of order and show an older state
                guard !isSaving else { return }
                isSaving = true
                Task {
                    defer { isSaving = false }
                    do {
                        state = .loaded(try await model.api.updateNotificationPrefs(patch(newValue)))
                        errorMessage = nil
                        await model.refreshUser()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )) {
            HStack(spacing: EGuardSpacing.sm) {
                IconTile(symbolName: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(EGuardTypography.label)
                    Text(detail).font(EGuardTypography.caption).foregroundStyle(EGuardColors.textSecondary)
                }
            }
        }
        .tint(EGuardColors.primary)
        .disabled(!enabled || isSaving)
    }

    private func loadPrefs() async {
        state = await load { try await model.api.notificationPrefs() }
    }

    private func loadStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func request() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await loadStatus()
            if status == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        NotificationsView()
    }
    .environment(AppModel.live())
    .environment(AppRouter())
}
#endif
