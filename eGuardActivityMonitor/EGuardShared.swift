import DeviceActivity
import Foundation
import ManagedSettings

/// Names shared between the app and its Screen Time extensions.
/// This is a copy of the app target's file; keep them in sync.
enum EGuardShared {
    static let appGroupIdentifier = "group.devplaceholder.eguard"

    enum Store {
        static let downtime = ManagedSettingsStore.Name("eguard.downtime")
        static let dailyLimits = ManagedSettingsStore.Name("eguard.dailyLimits")
        static let restrictions = ManagedSettingsStore.Name("eguard.restrictions")
    }

    enum Activity {
        static let downtime = DeviceActivityName("eguard.downtime")
        static let dailyLimits = DeviceActivityName("eguard.dailyLimits")
    }

    enum Event {
        static let gaming = DeviceActivityEvent.Name("eguard.gaming")
        static let socialApps = DeviceActivityEvent.Name("eguard.socialApps")
    }

    enum DefaultsKey {
        static let gamingSelection = "eguard.selection.gaming"
        static let socialAppsSelection = "eguard.selection.socialApps"
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
