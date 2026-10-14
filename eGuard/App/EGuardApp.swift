import Observation
import OSLog
import SwiftUI
import UIKit
import UserNotifications

/// Starts Firebase and hands the APNs token to it. The FCM token Firebase returns is what the server
/// registers with `POST /me/push-tokens` (a parent), or gets on `/sync` (a child's device, for silent syncs).
final class PushRegistrationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            PushService.shared.configure()
        }
        #else
        PushService.shared.configure()
        #endif
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushService.shared.didReceiveAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        EGuardLog.app.error("Push registration failed: \(error.localizedDescription)")
    }

    /// Background pushes (`content-available`): the server's "sync now" on a child's device.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await PushService.shared.handleRemoteNotification(userInfo)
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
                // `initial`: Firebase can hand over its cached token (or a tapped alert, on a cold start) before
                // this view attaches; without it that value is never seen
                .onChange(of: PushService.shared.fcmToken, initial: true) { _, token in
                    if let token { model.updatePushToken(token) }
                }
                .onChange(of: model.isSignedIn && model.mode == .parent, initial: true) { _, parent in
                    PushService.shared.presentsAlerts = parent
                }
                .onChange(of: model.mode == .child, initial: true) { _, child in
                    // A parent's change wakes the device to sync (AppModel.make sets the handler); without this
                    // it waits until the app is opened. Silent pushes need no notification permission.
                    guard child else { return }
                    UIApplication.shared.registerForRemoteNotifications()
                    if let token = PushService.shared.fcmToken { model.updatePushToken(token) }
                }
                .onChange(of: PushService.shared.openedAlert, initial: true) { _, alert in
                    guard let alert else { return }
                    PushService.shared.openedAlert = nil
                    model.pendingPushAlert = alert
                }
                .task {
                    // Alerts are for parents; a child's device registers for silent syncs above
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
