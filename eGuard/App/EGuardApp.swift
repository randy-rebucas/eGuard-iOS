import Observation
import OSLog
import SwiftUI
import UIKit
import UserNotifications

/// Receives the APNs device token so it can be registered with `POST /me/push-tokens`.
final class PushRegistrationDelegate: NSObject, UIApplicationDelegate {
    /// The latest hex-encoded APNs token, observed by the app scene.
    static let relay = PushTokenRelay()

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.relay.token = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        EGuardLog.app.error("Push registration failed: \(error.localizedDescription)")
    }
}

@Observable
final class PushTokenRelay {
    var token: String?
}

@main
struct EGuardApp: App {
    @UIApplicationDelegateAdaptor(PushRegistrationDelegate.self) private var delegate
    @State private var model = AppModel.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: PushRegistrationDelegate.relay.token) { _, token in
                    if let token { model.updatePushToken(token) }
                }
                .task {
                    // Registration is silent when notifications were already allowed; the token arrives via the delegate.
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    if settings.authorizationStatus == .authorized {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
        }
    }
}
