import SwiftUI
import UserNotifications

/// App settings: authorization, child profile, privacy, and reset.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var isConfirmingReset = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section("Authorization") {
                EGuardValueRow(label: "Family Controls", value: model.authorizationStatus.title)
                if !model.authorizationStatus.isAuthorized {
                    Button("Grant Authorization") { router.push(.authorization) }
                        .accessibilityIdentifier("settings.authorize")
                }
            }

            Section("Child & Device") {
                if let child = model.childProfile {
                    EGuardValueRow(label: "Child", value: "\(child.trimmedName), \(child.ageDescription)")
                    EGuardValueRow(label: "Device", value: "\(child.device.displayName) · \(child.device.operatingSystemName)")
                    EGuardValueRow(label: "Account", value: child.relationship.title)
                }
                Button("Edit Child & Device") { router.push(.childDevice) }
                Button("Change Protection Profile") { router.push(.protectionProfile) }
            }

            Section {
                Button("Protection alerts") { requestNotifications() }
                    .disabled(notificationStatus == .authorized)
            } header: {
                Text("Notifications")
            } footer: {
                Text(notificationStatus == .authorized
                     ? "eGuard can notify you when downtime starts or an allowance runs out."
                     : "Allow notifications so eGuard can tell you when downtime starts or an allowance runs out.")
            }

            Section {
                Label("eGuard configures Apple's Screen Time protections and verifies they are active.", systemImage: "checkmark.shield")
                Label("eGuard does not read messages, track location, record audio or video, or collect passwords.", systemImage: "eye.slash")
                Label("App and website choices are stored as Apple's privacy-preserving tokens.", systemImage: "lock")
            } header: {
                Text("Privacy")
            }
            .font(EGuardTypography.callout)

            Section {
                Button("Remove All Protections and Reset", role: .destructive) {
                    isConfirmingReset = true
                }
                .accessibilityIdentifier("settings.reset")
            } footer: {
                Text("Removes every restriction eGuard applied and deletes the child's profile from this device.")
            }

            Section {
                EGuardValueRow(
                    label: "Version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                )
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove all protections?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Remove and Reset", role: .destructive) {
                model.resetEverything()
                router.popToRoot()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downtime, limits, and restrictions applied by eGuard will be removed immediately.")
        }
        .task { await loadNotificationStatus() }
    }

    private func loadNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func requestNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await loadNotificationStatus()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppModel.make(arguments: ["-uiTesting", "-setupComplete"]))
    .environment(AppRouter())
}
