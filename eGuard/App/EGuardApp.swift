import Observation
import OSLog
import SwiftUI
import UIKit
import UserNotifications

/// Starts Firebase and hands the APNs token to it. The FCM token Firebase returns is what the server
/// registers with `POST /me/push-tokens`.
final class PushRegistrationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            PushService.shared.configure()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushService.shared.didReceiveAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        EGuardLog.app.error("Push registration failed: \(error.localizedDescription)")
    }
}

@main
struct EGuardApp: App {
    @UIApplicationDelegateAdaptor(PushRegistrationDelegate.self) private var delegate
    @State private var model = AppModel.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in model.open(url) }
                .onChange(of: PushService.shared.fcmToken) { _, token in
                    if let token { model.updatePushToken(token) }
                }
                .onChange(of: PushService.shared.openedAlert) { _, alert in
                    guard let alert else { return }
                    PushService.shared.openedAlert = nil
                    model.pendingPushAlert = alert
                }
                .task {
                    // Pushes are for parents. A child's device never registers.
                    guard model.mode != .child else { return }
                    // Registration is silent when notifications were already allowed; the token arrives via the delegate.
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    if settings.authorizationStatus == .authorized {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
        }
    }
}
