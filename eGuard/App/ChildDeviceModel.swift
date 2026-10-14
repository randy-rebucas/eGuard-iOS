import Foundation
import Observation
import OSLog

/// The child device side of eGuard: pairs once, then syncs the child's policy, applies it, and reports
/// what the OS really has. Enforcement keeps running offline from the saved policy.
@Observable
final class ChildDeviceModel {
    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(Date)
        /// The server couldn't be reached; the saved policy stays in force and the next sync retries.
        case offline(String)
        case failed(String)
    }

    /// One protection as the child's screen shows it: what the parent set and whether the device has it.
    struct ProtectionStatus: Identifiable, Equatable {
        let key: String
        let policyLabel: String
        let reportedLabel: String
        let capability: Capability
        let isMatching: Bool

        var id: String { key }
        var name: String { ProtectionKey.name(key) }
    }

    // MARK: Dependencies

    let api: DeviceAPIService
    let tokenStore: DeviceTokenStore
    let enforcer: ChildDeviceEnforcer
    let locationReporter: LocationReporting
    let usageSource: UsageSource
    private let store: ChildDeviceStore
    private let network: NetworkMonitor?

    // MARK: State

    private(set) var state: ChildDeviceState
    private(set) var syncState: SyncState = .idle
    /// `minAppVersion` from the last sync when this build is older. Syncing stops until updated.
    private(set) var updateRequired: String?
    /// A parent removed this device; the removed screen is showing.
    private(set) var wasRemoved = false
    /// Shown when a parent-only link (verify, reset, invite) is opened on the child's device.
    var deepLinkNotice: String?
    private var loopTask: Task<Void, Never>?
    private var isSyncing = false
    /// This install's FCM token, sent on every `/sync` so a parent's change can wake the device (silent push).
    private(set) var pushToken: String?
    /// Protections the last sync couldn't apply, by key, with the reason. Sent with the report (the parent sees why)
    /// and listed on the child's home screen.
    private(set) var applyProblems: [String: String] = [:]
    /// The config last applied per key in this sync: the policy's, or a newer open request's. The report reads
    /// back against it (e.g. which of two ages sharing one Apple rating was asked for).
    private var appliedConfigs: [String: JSONValue] = [:]

    /// [applyProblems] for the home screen, minus the one the "Choose the apps" card already explains.
    var applyProblemsToShow: [(name: String, reason: String)] {
        applyProblems
            .filter { !(needsScreenTimeApps && $0.key == "SCREEN_TIME") }
            .map { (ProtectionKey.name($0.key), $0.value) }
            .sorted { $0.name < $1.name }
    }

    init(
        api: DeviceAPIService,
        tokenStore: DeviceTokenStore,
        enforcer: ChildDeviceEnforcer,
        store: ChildDeviceStore,
        locationReporter: LocationReporting,
        usageSource: UsageSource,
        network: NetworkMonitor?
    ) {
        self.api = api
        self.tokenStore = tokenStore
        self.enforcer = enforcer
        self.store = store
        self.locationReporter = locationReporter
        self.usageSource = usageSource
        self.network = network
        state = store.load()
    }

    var isPaired: Bool { tokenStore.session != nil }
    var session: DeviceSession? { tokenStore.session }
    var isSetupComplete: Bool { state.setupComplete }
    var appVersion: String { DeviceFacts.appVersion }

    /// The parent turned location sharing on and the plan includes it. The OS permission is separate.
    var isLocationSharingRequested: Bool {
        state.policyConfig("LOCATION")?["sharing"]?.boolValue == true && state.locationSharingAllowed
    }

    var isLocationSharingActive: Bool { isLocationSharingRequested && locationReporter.isAuthorized }

    /// A screen time limit is set but no apps were chosen for it to count (setup skipped): it can't apply.
    var needsScreenTimeApps: Bool {
        guard state.screenTimeSelection.isEmpty, let config = state.policyConfig("SCREEN_TIME") else { return false }
        return (config["dailyMinutes"]?.intValue ?? 0) > 0 || (config["weekendMinutes"]?.intValue ?? 0) > 0
    }

    var lastSyncDescription: String {
        switch syncState {
        case .syncing: "Checking with eGuard…"
        case .synced(let date): "Updated \(date.relativeDescription())"
        case .offline(let message): message
        case .failed(let message): message
        case .idle: state.lastSyncAt.map { "Updated \($0.relativeDescription())" } ?? "Not synced yet"
        }
    }

    private var context: EnforcementContext {
        EnforcementContext(
            screenTimeSelection: state.screenTimeSelection,
            timeZone: state.timezone.flatMap(TimeZone.init(identifier:)) ?? .current,
            locationSharingAllowed: state.locationSharingAllowed
        )
    }

    // MARK: Pairing

    /// Exchanges the parent's code for a device token and stores it before anything else.
    func pair(code: String, deviceName: String) async throws -> DeviceSession {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        // The server takes up to 60 characters; a longer name was refused as if the code were wrong
        let name = String(deviceName.trimmingCharacters(in: .whitespaces).prefix(60))
        let response = try await api.pair(PairRequest(
            code: normalized,
            name: name,
            model: DeviceFacts.model,
            kind: DeviceFacts.kind,
            osVersion: DeviceFacts.osVersion,
            appVersion: DeviceFacts.appVersion
        ))
        let session = DeviceSession(deviceId: response.deviceId, token: response.token, childName: response.childName, deviceName: name, pairedAt: .now)
        tokenStore.save(session)
        wasRemoved = false
        state = ChildDeviceState()
        store.save(state)
        return session
    }

    /// The permissions step of setup is done; the child's home screen takes over.
    func completeSetup() {
        state.setupComplete = true
        store.save(state)
    }

    /// The apps and categories the daily allowance counts. Re-applies the limit straight away.
    func setScreenTimeSelection(_ selection: ActivitySelectionSnapshot) {
        state.screenTimeSelection = selection
        store.save(state)
        if let entry = state.policy.first(where: { $0.key == "SCREEN_TIME" }) {
            applyProblems["SCREEN_TIME"] = applyError(entry, context: context)
        }
    }

    // MARK: Sync

    /// A new or rotated FCM token: sync now so the server has it before a parent's next change.
    func setPushToken(_ token: String) {
        guard token != pushToken else { return }
        pushToken = token
        guard isPaired else { return }
        Task { await syncNow() }
    }

    /// Keeps syncing every `nextSyncSeconds` while the app is in the foreground.
    func startSyncLoop() {
        guard loopTask == nil, isPaired else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = self?.state.nextSyncSeconds ?? 300
                try? await Task.sleep(for: .seconds(max(60, seconds)))
                guard !Task.isCancelled else { return }
                await self?.syncNow()
            }
        }
    }

    func stopSyncLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// One sync cycle: policy and requests in, enforcement, report, events and location out.
    func syncNow() async {
        guard isPaired, !isSyncing, updateRequired == nil else { return }
        isSyncing = true
        defer { isSyncing = false }
        syncState = .syncing

        do {
            var status = DeviceFacts.status
            // PushService's own copy when launched in the background, before any view passed the token on
            status.pushToken = pushToken ?? PushService.shared.fcmToken
            let response = try await api.sync(status)
            if let minimum = response.minAppVersion, AppInfo.compare(DeviceFacts.appVersion, minimum) < 0 {
                updateRequired = minimum
                stopSyncLoop()
                syncState = .idle
                return
            }

            // Renamed, or moved to another child: greet them by the name the server has now, not the one from pairing
            if let name = response.childName, !name.isEmpty, var current = tokenStore.session, current.childName != name {
                current.childName = name
                tokenStore.save(current)
            }
            state.policy = response.policy
            state.apps = response.apps
            state.timezone = response.timezone
            state.locationSharingAllowed = response.isLocationSharingAllowed
            state.nextSyncSeconds = response.nextSyncSeconds
            store.save(state)

            // Reconcile the saved policy, then apply the parent's open changes in order. Applying the
            // same config twice is harmless, which the server relies on when it resends a request.
            let enforcement = context
            var problems: [String: String] = [:]
            var applied: [String: JSONValue] = [:]
            for entry in response.policy where enforcer.supportedKeys.contains(entry.key) {
                problems[entry.key] = applyError(entry, context: enforcement)
                applied[entry.key] = entry.config
            }
            var touched = Set<String>()
            for request in response.requests where enforcer.supportedKeys.contains(request.key) {
                problems[request.key] = applyError(PolicyEntry(key: request.key, config: request.config), context: enforcement)
                applied[request.key] = request.config
                touched.insert(request.key)
            }
            applyProblems = problems
            appliedConfigs = applied
            enforcer.updateClockLock(policy: response.policy)

            try await report(full: response.fullReportRequested, touched: touched)
            await flushEvents()
            await sendUsageIfChanged()
            await sendLocationIfAllowed()

            // Removed meanwhile (a 401 on one of the calls above wiped the device): nothing left to record
            guard isPaired else { return }
            let now = Date.now
            state.lastSyncAt = now
            store.save(state)
            syncState = .synced(now)
        } catch let error as DeviceAPIError where error.isUnauthorized {
            handleRemoved()
        } catch let error as DeviceAPIError {
            syncState = error.isRetryable ? .offline(error.localizedDescription) : .failed(error.localizedDescription)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    /// Applies one protection; the reason it failed, or nil. Never silent: the failure is logged, reported to the
    /// parent with the read-back value, and shown on the child's screen.
    private func applyError(_ entry: PolicyEntry, context: EnforcementContext) -> String? {
        do {
            try enforcer.apply(entry, context: context)
            return nil
        } catch {
            EGuardLog.configuration.error("Couldn't apply \(entry.key): \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// Reads every supported protection back from the OS and sends what the server asked for plus
    /// anything that changed since the last report.
    private func report(full: Bool, touched: Set<String>) async throws {
        let enforcement = context
        var entries: [ReportEntry] = []
        for key in enforcer.supportedKeys {
            // The newest config applied for the key (an open request overrides the saved policy)
            let hint = appliedConfigs[key] ?? state.policyConfig(key)
            guard let config = enforcer.readBack(key: key, policy: hint, context: enforcement) else { continue }
            let entry = ReportEntry(key: key, config: config, error: applyProblems[key])
            let previous = state.lastReported.first { $0.key == key }
            if full || touched.contains(key) || previous != entry {
                entries.append(entry)
            }
        }
        guard full || !entries.isEmpty else { return }

        let response = try await api.report(ReportRequest(full: full ? true : nil, protections: entries, battery: DeviceFacts.battery, osVersion: DeviceFacts.osVersion, appVersion: DeviceFacts.appVersion))
        if let ignored = response.ignored, !ignored.isEmpty {
            EGuardLog.configuration.error("The server ignored \(ignored.count) report entries.")
        }
        for entry in entries {
            state.lastReported.removeAll { $0.key == entry.key }
            state.lastReported.append(entry)
        }
        store.save(state)
    }

    /// Sends queued events in order. A 400 means a bug, so that event is dropped; anything retryable waits.
    private func flushEvents() async {
        drainExtensionEvents()
        while let event = state.pendingEvents.first {
            do {
                _ = try await api.event(event)
                state.pendingEvents.removeAll { $0.eventId == event.eventId }
            } catch let error as DeviceAPIError where error.isRetryable {
                break
            } catch let error as DeviceAPIError where error.isUnauthorized {
                // Removed: the device was wiped (pending events included); nothing to save
                return
            } catch {
                state.pendingEvents.removeAll { $0.eventId == event.eventId }
            }
        }
        guard isPaired else { return }
        store.save(state)
    }

    /// Picks up events the monitor extension recorded (it can't talk to the network itself). The extension is
    /// another process writing the same key: only the events taken here are removed, so one it adds meanwhile
    /// stays for the next sync, and one malformed entry doesn't lose the rest.
    private func drainExtensionEvents() {
        guard let defaults = EGuardShared.sharedDefaults,
              let data = defaults.data(forKey: EGuardShared.DefaultsKey.pendingEvents),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return }
        let taken = raw.compactMap { item -> DeviceEvent? in
            guard let itemData = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? JSONDecoder().decode(DeviceEvent.self, from: itemData)
        }
        state.pendingEvents.append(contentsOf: taken.filter { event in !state.pendingEvents.contains { $0.eventId == event.eventId } })
        store.save(state)
        // Re-read and drop only what was taken (and the malformed entries seen above)
        let takenIds = Set(taken.map(\.eventId))
        let seen = raw.count
        let now = (defaults.data(forKey: EGuardShared.DefaultsKey.pendingEvents))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [Any] } ?? []
        let left = now.dropFirst(min(seen, now.count)).filter { item in
            guard let id = (item as? [String: Any])?["eventId"] as? String else { return true }
            return !takenIds.contains(id)
        }
        if left.isEmpty {
            defaults.removeObject(forKey: EGuardShared.DefaultsKey.pendingEvents)
        } else if let leftData = try? JSONSerialization.data(withJSONObject: Array(left)) {
            defaults.set(leftData, forKey: EGuardShared.DefaultsKey.pendingEvents)
        }
    }

    /// Each day's total from the usage ladder (today's running total and earlier days the app wasn't opened on),
    /// sent when it changed. `/usage` is idempotent per day, so a resend is harmless; a day older than 30 days
    /// would be refused and is skipped.
    private func sendUsageIfChanged() async {
        var sent = state.usageSent ?? [:]
        if let last = state.lastUsageSent { sent[last.date] = sent[last.date] ?? last.totalMinutes }
        for usage in usageSource.pendingUsages() where sent[usage.date] != usage.totalMinutes {
            guard let day = Self.parseLocalDate(usage.date), Date.now.timeIntervalSince(day) < 30 * 86400 else { continue }
            do {
                try await api.usage(usage)
                sent[usage.date] = usage.totalMinutes
                state.lastUsageSent = usage
            } catch {
                EGuardLog.app.error("Sending usage failed; it is retried on the next sync.")
                break
            }
        }
        guard isPaired else { return }
        // Only the last month matters (older days are refused anyway)
        state.usageSent = sent.filter { key, _ in Self.parseLocalDate(key).map { Date.now.timeIntervalSince($0) < 31 * 86400 } ?? false }
        store.save(state)
    }

    private static func parseLocalDate(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// One fix per sync, only when the parent turned sharing on, the plan includes it and the OS allows it.
    private func sendLocationIfAllowed() async {
        guard isLocationSharingActive, let fix = await locationReporter.currentFix() else { return }
        try? await api.location(fix)
    }

    // MARK: Child actions

    /// "Ask a parent" for an app by name. Returns the parent's existing answer when the app already has a rule.
    func requestApp(named name: String) async throws -> AppApproval? {
        // The server takes up to 80 characters
        let event = DeviceEvent(type: .appRequested, app: String(name.trimmingCharacters(in: .whitespaces).prefix(80)))
        do {
            return try await api.event(event).approval
        } catch let error as DeviceAPIError where error.isRetryable {
            state.pendingEvents.append(event)
            store.save(state)
            throw error
        }
    }

    // MARK: Removal

    /// A parent removed the device (any 401). Stop enforcing, wipe everything, show the removed screen.
    func handleRemoved() {
        guard isPaired || !state.policy.isEmpty else { return }
        wipe()
        wasRemoved = true
    }

    /// Clears the device side without showing the removed screen, e.g. "Set up eGuard again".
    func forget() {
        wipe()
        wasRemoved = false
    }

    private func wipe() {
        stopSyncLoop()
        enforcer.clearAll()
        tokenStore.clear()
        state = ChildDeviceState()
        store.erase()
        appliedConfigs = [:]
        syncState = .idle
        updateRequired = nil
        for key in [
            EGuardShared.DefaultsKey.pendingEvents, EGuardShared.DefaultsKey.usageDate, EGuardShared.DefaultsKey.usageMinutes,
            EGuardShared.DefaultsKey.usageByDate, EGuardShared.DefaultsKey.shieldedOn, EGuardShared.DefaultsKey.screenTimeSignature,
        ] {
            EGuardShared.sharedDefaults?.removeObject(forKey: key)
        }
    }

    // MARK: Status for the child's screen

    func protectionStatuses() -> [ProtectionStatus] {
        let enforcement = context
        return state.policy.compactMap { entry in
            let capability = enforcer.capability(for: entry.key)
            guard capability != .unsupported else { return nil }
            let reported = enforcer.readBack(key: entry.key, policy: entry.config, context: enforcement)
            return ProtectionStatus(
                key: entry.key,
                policyLabel: ProtectionConfigFormatter.label(key: entry.key, config: entry.config),
                reportedLabel: reported.map { ProtectionConfigFormatter.label(key: entry.key, config: $0) } ?? "Unknown",
                capability: capability,
                // As the server compares them (WEB by mode only)
                isMatching: reported != nil && ProtectionKey.reportMatches(key: entry.key, reported: reported, policy: entry.config)
            )
        }
    }
}
