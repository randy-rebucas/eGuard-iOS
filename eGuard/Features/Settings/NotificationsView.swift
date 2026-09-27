import SwiftUI
import UserNotifications

/// Notification preferences from `/me/notifications`, plus the iOS permission.
struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var state: LoadState<NotificationPrefs> = .loading
    @State private var errorMessage: String?

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
                    toggle("Push alerts", detail: "Protection changes, device issues, approvals", symbol: "iphone.radiowaves.left.and.right", tint: EGuardColors.primary, value: prefs.notifyPush) { NotificationPrefsPatch(notifyPush: $0) }
                    Divider()
                    toggle("Email alerts", detail: "The same alerts by email", symbol: "envelope.fill", tint: EGuardColors.tileTeal, value: prefs.notifyEmail) { NotificationPrefsPatch(notifyEmail: $0) }
                    Divider()
                    toggle("App approval requests", detail: "When your child asks for an app", symbol: "square.grid.2x2.fill", tint: EGuardColors.tilePurple, value: prefs.notifyApproval) { NotificationPrefsPatch(notifyApproval: $0) }
                    Divider()
                    toggle("Weekly summary", detail: "A recap of screen time and health every week", symbol: "calendar", tint: EGuardColors.tileOrange, value: prefs.weeklySummary) { NotificationPrefsPatch(weeklySummary: $0) }
                }
            }
            InlineError(message: errorMessage)

            Text("Push delivery is being rolled out on the eGuard server. Alerts always appear in the Alerts tab.")
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
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Turned off in Settings"
        case .notDetermined: "Not requested yet"
        @unknown default: "Unknown"
        }
    }

    private func toggle(_ title: String, detail: String, symbol: String, tint: Color, value: Bool, patch: @escaping (Bool) -> NotificationPrefsPatch) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in
                Task {
                    do {
                        state = .loaded(try await model.api.updateNotificationPrefs(patch(newValue)))
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

#Preview {
    NavigationStack {
        NotificationsView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
