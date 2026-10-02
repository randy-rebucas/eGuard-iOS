import DeviceActivity
import Foundation
import ManagedSettings

/// Names shared between the app and its Screen Time extensions.
/// This is a copy of the app target's file; keep them in sync.
enum EGuardShared {
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
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
