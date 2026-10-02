import Foundation
import OSLog

/// Everything the child device keeps locally so enforcement continues offline and retries survive relaunch.
nonisolated struct ChildDeviceState: Codable, Equatable, Sendable {
    /// The child's current settings from `/sync`. The source of truth for enforcement.
    var policy: [PolicyEntry] = []
    var apps: [AppRule] = []
    var timezone: String?
    /// `features.locationSharing` from the last sync. False on plans without location.
    var locationSharingAllowed = true
    var nextSyncSeconds = 300
    var lastSyncAt: Date?
    /// The apps and categories the daily screen-time allowance counts. Chosen during setup.
    var screenTimeSelection = ActivitySelectionSnapshot.empty
    /// Events waiting to be sent, newest last. Each keeps its `eventId` across retries.
    var pendingEvents: [DeviceEvent] = []
    /// What the device last told the server, so only changes are reported between syncs.
    var lastReported: [ReportEntry] = []
    /// False until the permissions step of child setup finished.
    var setupComplete = false
    /// The last `/usage` total sent, so unchanged totals aren't resent every sync.
    var lastUsageSent: UsageRequest?

    func policyConfig(_ key: String) -> JSONValue? {
        policy.first { $0.key == key }?.config
    }
}

/// Persists `ChildDeviceState` in a protected file, separate from the parent side's data.
final class ChildDeviceStore {
    private static let key = "childDeviceState"
    private let store: CodableStore

    init(store: CodableStore) {
        self.store = store
    }

    static func live() -> ChildDeviceStore {
        do {
            return ChildDeviceStore(store: try ProtectedFileStore(directoryName: "eGuardChild"))
        } catch {
            EGuardLog.app.error("Child device store unavailable; falling back to memory.")
            return ChildDeviceStore(store: InMemoryStore())
        }
    }

    static func inMemory() -> ChildDeviceStore {
        ChildDeviceStore(store: InMemoryStore())
    }

    func load() -> ChildDeviceState {
        (try? store.load(ChildDeviceState.self, forKey: Self.key)) ?? ChildDeviceState()
    }

    func save(_ state: ChildDeviceState) {
        do {
            try store.save(state, forKey: Self.key)
        } catch {
            EGuardLog.app.error("Saving child device state failed.")
        }
    }

    /// Nothing from the device's past is kept once a parent removes it.
    func erase() {
        try? store.removeAll()
    }
}
