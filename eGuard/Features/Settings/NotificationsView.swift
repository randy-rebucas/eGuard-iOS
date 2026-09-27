import SwiftUI
import UserNotifications

/// Notification permission and which alerts the parent wants.
struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        EGuardScreen {
            EGuardCard {
                HStack(spacing: EGuardSpacing.sm) {
                    IconTile(symbolName: "bell.badge.fill", tint: EGuardColors.tileOrange, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System notifications")
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

            EGuardCard {
                SectionHeader(title: "Alert types")
                toggle("Protection alerts", detail: "A protection stopped working or needs setup", symbol: "shield.lefthalf.filled", tint: EGuardColors.primary, keyPath: \.protectionAlertsEnabled)
                Divider()
                toggle("App alerts", detail: "Apps need to be chosen or a limit was reached", symbol: "square.grid.2x2.fill", tint: EGuardColors.tilePurple, keyPath: \.appAlertsEnabled)
                Divider()
                toggle("Weekly summary", detail: "A recap of configuration health every week", symbol: "calendar", tint: EGuardColors.tileTeal, keyPath: \.weeklySummaryEnabled)
            }

            Text("eGuard shows these alerts inside the app. System notifications are sent by Apple's Screen Time when downtime starts or an allowance runs out.")
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        } actions: {
            EmptyView()
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Turned off in Settings"
        case .notDetermined: "Not requested yet"
        @unknown default: "Unknown"
        }
    }

    private func toggle(_ title: String, detail: String, symbol: String, tint: Color, keyPath: WritableKeyPath<AppPreferences, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } }
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

    private func load() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func request() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await load()
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
