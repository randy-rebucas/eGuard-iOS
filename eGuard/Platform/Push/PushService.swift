import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications
#if canImport(FirebaseCore) && canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging
#endif

/// An alert push from the eGuard server. The payload's `data` carries `type: "alert"`, `alertId`,
/// `category` and an optional `childId`; the app opens the alert.
nonisolated struct PushAlert: Equatable, Sendable {
    var alertId: String
    var category: String?
    var childId: String?

    init(alertId: String, category: String? = nil, childId: String? = nil) {
        self.alertId = alertId
        self.category = category
        self.childId = childId
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard userInfo["type"] as? String == "alert", let alertId = userInfo["alertId"] as? String else { return nil }
        self.init(alertId: alertId, category: userInfo["category"] as? String, childId: userInfo["childId"] as? String)
    }
}

/// Firebase Cloud Messaging for the parent side. The server wants an FCM registration token, not the
/// raw APNs token, so this hands the APNs token to Firebase and publishes the FCM token it returns.
///
/// Setup, done in Xcode:
/// 1. File › Add Package Dependencies… › `https://github.com/firebase/firebase-ios-sdk`, add the
///    `FirebaseMessaging` product to the eGuard target.
/// 2. Add the `GoogleService-Info.plist` from the Firebase console to the eGuard target.
/// Until both are in place `isAvailable` is false, no token is registered, and everything else works.
@Observable
final class PushService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushService()

    /// The current FCM registration token, re-published whenever Firebase rotates it.
    private(set) var fcmToken: String?
    /// The alert the person tapped on, waiting for the UI to open it.
    var openedAlert: PushAlert?
    private(set) var isConfigured = false

    /// Whether this build links the Firebase SDK at all.
    static var isAvailable: Bool {
        #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
        true
        #else
        false
        #endif
    }

    /// Call once at launch. Safe to call when the SDK or its plist is missing.
    func configure() {
        guard !isConfigured else { return }
        UNUserNotificationCenter.current().delegate = self
        #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
        guard FirebaseOptions.defaultOptions() != nil else {
            EGuardLog.app.error("GoogleService-Info.plist is missing; push tokens won't be registered.")
            return
        }
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        isConfigured = true
        #else
        EGuardLog.app.error("Firebase Messaging isn't linked; push tokens won't be registered.")
        #endif
    }

    /// The APNs token from the app delegate. Firebase maps it to an FCM token.
    func didReceiveAPNsToken(_ token: Data) {
        guard isConfigured else { return }
        #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = token
        #endif
    }

    /// Forgets the token on this install, e.g. before the phone becomes a child's device.
    func deleteToken() {
        defer { fcmToken = nil }
        guard isConfigured else { return }
        #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
        Messaging.messaging().unregister { error in
            if let error { EGuardLog.app.error("Deleting the FCM token failed: \(error.localizedDescription)") }
        }
        #endif
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let alert = PushAlert(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { openedAlert = alert }
    }
}

#if canImport(FirebaseCore) && canImport(FirebaseMessaging)
extension PushService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.fcmToken = fcmToken
        }
    }
}
#endif
