import DeviceActivity
import FamilyControls
import ManagedSettings
import UserNotifications

/// Enforces the schedules the eGuard app registers.
/// Downtime shields every app category during its interval; daily limits shield the parent's
/// selected apps once their allowance is used up. Nothing here reads or records what the child does.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let downtimeStore = ManagedSettingsStore(named: EGuardShared.Store.downtime)
    private let limitsStore = ManagedSettingsStore(named: EGuardShared.Store.dailyLimits)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        if EGuardShared.Activity.isDowntime(activity) {
            downtimeStore.shield.applicationCategories = .all()
            downtimeStore.shield.webDomainCategories = .all()
            notify(
                identifier: "downtime.started",
                title: "Bedtime started",
                body: "Apps are paused until the bedtime schedule ends."
            )
            return
        }
        switch activity {
        case EGuardShared.Activity.dailyLimits:
            // A new day begins: yesterday's used-up allowances are released.
            limitsStore.clearAllSettings()
        case EGuardShared.Activity.screenTime:
            limitsStore.clearAllSettings()
            recordUsage(minutes: 0)
        default:
            break
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        if EGuardShared.Activity.isDowntime(activity) {
            downtimeStore.clearAllSettings()
            return
        }
        switch activity {
        case EGuardShared.Activity.dailyLimits, EGuardShared.Activity.screenTime:
            limitsStore.clearAllSettings()
        default:
            break
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        // A usage rung: the counted apps have been used for at least this long today. No shield, no notice.
        if let minutes = EGuardShared.Event.usageMinutes(from: event) {
            recordUsage(minutes: minutes)
            return
        }

        let key: String
        let title: String
        switch event {
        case EGuardShared.Event.gaming:
            key = EGuardShared.DefaultsKey.gamingSelection
            title = "Gaming allowance used"
        case EGuardShared.Event.socialApps:
            key = EGuardShared.DefaultsKey.socialAppsSelection
            title = "Social apps allowance used"
        case EGuardShared.Event.screenTime:
            key = EGuardShared.DefaultsKey.screenTimeSelection
            title = "Screen time limit reached"
            recordLimitReached()
            recordUsage(minutes: EGuardShared.sharedDefaults?.integer(forKey: EGuardShared.DefaultsKey.screenTimeMinutes) ?? 0)
        default:
            return
        }

        guard let data = EGuardShared.sharedDefaults?.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }
        shield(selection)
        notify(
            identifier: "limit.\(event.rawValue)",
            title: title,
            body: "The selected apps are paused until tomorrow."
        )
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        guard EGuardShared.Activity.isDowntime(activity) else { return }
        notify(
            identifier: "downtime.warning",
            title: "Bedtime starts soon",
            body: "Apps will be paused in about five minutes."
        )
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }

    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
    }

    // MARK: - Helpers

    /// Adds the selection to the shields already applied today so gaming and social limits stack.
    private func shield(_ selection: FamilyActivitySelection) {
        let existingApplications = limitsStore.shield.applications ?? []
        let applications = existingApplications.union(selection.applicationTokens)
        limitsStore.shield.applications = applications.isEmpty ? nil : applications

        var categories = selection.categoryTokens
        if case .specific(let existing, _)? = limitsStore.shield.applicationCategories {
            categories.formUnion(existing)
        }
        limitsStore.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)

        let existingDomains = limitsStore.shield.webDomains ?? []
        let domains = existingDomains.union(selection.webDomainTokens)
        limitsStore.shield.webDomains = domains.isEmpty ? nil : domains
    }

    /// Queues a `LIMIT_REACHED` event for the app to send to the eGuard server on its next sync.
    /// The extension itself never talks to the network.
    private func recordLimitReached() {
        guard let defaults = EGuardShared.sharedDefaults else { return }
        let minutes = defaults.integer(forKey: EGuardShared.DefaultsKey.screenTimeMinutes)
        var pending = (try? JSONSerialization.jsonObject(with: defaults.data(forKey: EGuardShared.DefaultsKey.pendingEvents) ?? Data("[]".utf8))) as? [[String: Any]] ?? []
        pending.append(["type": "LIMIT_REACHED", "minutes": minutes, "eventId": UUID().uuidString])
        if let data = try? JSONSerialization.data(withJSONObject: pending) {
            defaults.set(data, forKey: EGuardShared.DefaultsKey.pendingEvents)
        }
    }

    /// Stores today's usage floor for the app to send as `/usage` on its next sync. Only ever moves up
    /// within a day; a new day's interval start resets it to zero.
    private func recordUsage(minutes: Int) {
        guard let defaults = EGuardShared.sharedDefaults else { return }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let sameDay = defaults.string(forKey: EGuardShared.DefaultsKey.usageDate) == today
        let previous = sameDay ? defaults.integer(forKey: EGuardShared.DefaultsKey.usageMinutes) : 0
        defaults.set(today, forKey: EGuardShared.DefaultsKey.usageDate)
        defaults.set(minutes == 0 && !sameDay ? 0 : max(previous, minutes), forKey: EGuardShared.DefaultsKey.usageMinutes)
    }

    /// Posts a local notification if the parent allowed them. Content never includes app names.
    private func notify(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
