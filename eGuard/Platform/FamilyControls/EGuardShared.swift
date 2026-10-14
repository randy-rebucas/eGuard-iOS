import DeviceActivity
import Foundation
import ManagedSettings

/// Names shared between the app and its Screen Time extensions.
/// The extension targets carry an identical copy of this file; keep them in sync.
nonisolated enum EGuardShared {
    static let appGroupIdentifier = "group.com.devcom.eguard"

    enum Store {
        static let downtime = ManagedSettingsStore.Name("eguard.downtime")
        static let dailyLimits = ManagedSettingsStore.Name("eguard.dailyLimits")
        static let restrictions = ManagedSettingsStore.Name("eguard.restrictions")
    }

    enum Activity {
        static let downtime = DeviceActivityName("eguard.downtime")
        static let dailyLimits = DeviceActivityName("eguard.dailyLimits")
        static let screenTime = DeviceActivityName("eguard.screenTime")

        /// Downtime on school nights is one weekly schedule per start weekday (Sunday = 1).
        static func downtime(weekday: Int) -> DeviceActivityName {
            DeviceActivityName("eguard.downtime.\(weekday)")
        }

        static func isDowntime(_ name: DeviceActivityName) -> Bool {
            name.rawValue.hasPrefix(downtime.rawValue)
        }

        /// When weekdays and weekends have different limits: one weekly schedule per day (Sunday = 1), each
        /// with that day's limit, so the right one applies without the app being opened.
        static func screenTime(weekday: Int) -> DeviceActivityName {
            DeviceActivityName("eguard.screenTime.\(weekday)")
        }

        static func isScreenTime(_ name: DeviceActivityName) -> Bool {
            name.rawValue.hasPrefix(screenTime.rawValue)
        }
    }

    enum Event {
        static let gaming = DeviceActivityEvent.Name("eguard.gaming")
        static let socialApps = DeviceActivityEvent.Name("eguard.socialApps")
        static let screenTime = DeviceActivityEvent.Name("eguard.screenTime")

        /// "At least `minutes` of the counted apps used today". The ladder behind `/usage` on iOS.
        static func usageTick(minutes: Int) -> DeviceActivityEvent.Name {
            DeviceActivityEvent.Name("eguard.usage.\(minutes)")
        }

        static func usageMinutes(from name: DeviceActivityEvent.Name) -> Int? {
            let prefix = "eguard.usage."
            guard name.rawValue.hasPrefix(prefix) else { return nil }
            return Int(name.rawValue.dropFirst(prefix.count))
        }
    }

    enum DefaultsKey {
        static let gamingSelection = "eguard.selection.gaming"
        static let socialAppsSelection = "eguard.selection.socialApps"
        static let screenTimeSelection = "eguard.selection.screenTime"
        static let screenTimeMinutes = "eguard.screenTime.minutes"
        /// JSON array of events the monitor extension recorded for the app to send on its next sync.
        static let pendingEvents = "eguard.events.pending"
        /// The local `YYYY-MM-DD` and minutes of the last usage rung the monitor extension reached.
        static let usageDate = "eguard.usage.date"
        static let usageMinutes = "eguard.usage.minutes"
        /// JSON `{ "YYYY-MM-DD": minutes }` for the last 30 days, so days the app wasn't opened still reach the parent.
        static let usageByDate = "eguard.usage.byDate"
        /// The local `YYYY-MM-DD` on which a limit shield went up. A schedule re-registered that day (the app
        /// re-applying the policy) keeps the shield instead of lifting it.
        static let shieldedOn = "eguard.limits.shieldedOn"
        /// What the screen-time schedules were last registered with, to skip re-registering when nothing changed.
        static let screenTimeSignature = "eguard.screenTime.signature"
        /// The protections (APP_APPROVAL, DOWNLOADS) that last asked for App Store installs to be denied.
        static let installApprovalReasons = "eguard.installApproval.reasons"
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
