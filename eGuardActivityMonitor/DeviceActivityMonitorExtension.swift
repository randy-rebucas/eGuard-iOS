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
        guard activity == EGuardShared.Activity.dailyLimits || EGuardShared.Activity.isScreenTime(activity) else { return }
        // A new day begins: yesterday's used-up allowances are released. An interval restarting the same day keeps
        // them, or a restart would hand out a new allowance (a real limit change clears `shieldedOn` in the app).
        if EGuardShared.sharedDefaults?.string(forKey: EGuardShared.DefaultsKey.shieldedOn) != Self.today() {
            limitsStore.clearAllSettings()
        }
        if EGuardShared.Activity.isScreenTime(activity) { recordUsage(minutes: 0) }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        if EGuardShared.Activity.isDowntime(activity) {
            downtimeStore.clearAllSettings()
            return
        }
        // Limits are released when the next day's interval starts, not here: an interval also ends when the app
        // re-registers the schedule, which mustn't lift a limit reached today.
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
            // This day's limit: per-day schedules each carry their own
            let threshold = DeviceActivityCenter().events(for: activity)[event]?.threshold
            let minutes = threshold.map { ($0.hour ?? 0) * 60 + ($0.minute ?? 0) }
                ?? EGuardShared.sharedDefaults?.integer(forKey: EGuardShared.DefaultsKey.screenTimeMinutes) ?? 0
            recordLimitReached(minutes: minutes)
            recordUsage(minutes: minutes)
        default:
            return
        }

        guard let data = EGuardShared.sharedDefaults?.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }
        shield(selection)
        EGuardShared.sharedDefaults?.set(Self.today(), forKey: EGuardShared.DefaultsKey.shieldedOn)
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
    private func recordLimitReached(minutes: Int) {
        guard let defaults = EGuardShared.sharedDefaults else { return }
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
        let today = Self.today()
        let sameDay = defaults.string(forKey: EGuardShared.DefaultsKey.usageDate) == today
        let previous = sameDay ? defaults.integer(forKey: EGuardShared.DefaultsKey.usageMinutes) : 0
        let total = minutes == 0 && !sameDay ? 0 : max(previous, minutes)
        defaults.set(today, forKey: EGuardShared.DefaultsKey.usageDate)
        defaults.set(total, forKey: EGuardShared.DefaultsKey.usageMinutes)
        // Each day's total too (last 30), so days the app wasn't opened on still reach the parent
        var byDate = (defaults.data(forKey: EGuardShared.DefaultsKey.usageByDate))
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        byDate[today] = max(byDate[today] ?? 0, total)
        let kept = byDate.keys.sorted().suffix(30)
        byDate = byDate.filter { kept.contains($0.key) }
        if let data = try? JSONEncoder().encode(byDate) {
            defaults.set(data, forKey: EGuardShared.DefaultsKey.usageByDate)
        }
    }

    /// The device's local `YYYY-MM-DD`, what `/usage` and the shield bookkeeping use.
    private static func today() -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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
