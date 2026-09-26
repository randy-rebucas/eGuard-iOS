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

        switch activity {
        case EGuardShared.Activity.downtime:
            downtimeStore.shield.applicationCategories = .all()
            downtimeStore.shield.webDomainCategories = .all()
            notify(
                identifier: "downtime.started",
                title: "Downtime started",
                body: "Apps are shielded until the downtime schedule ends."
            )
        case EGuardShared.Activity.dailyLimits:
            // A new day begins: yesterday's used-up allowances are released.
            limitsStore.clearAllSettings()
        default:
            break
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        switch activity {
        case EGuardShared.Activity.downtime:
            downtimeStore.clearAllSettings()
        case EGuardShared.Activity.dailyLimits:
            limitsStore.clearAllSettings()
        default:
            break
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == EGuardShared.Activity.dailyLimits else { return }

        let key: String
        let title: String
        switch event {
        case EGuardShared.Event.gaming:
            key = EGuardShared.DefaultsKey.gamingSelection
            title = "Gaming allowance used"
        case EGuardShared.Event.socialApps:
            key = EGuardShared.DefaultsKey.socialAppsSelection
            title = "Social apps allowance used"
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
            body: "The selected apps are shielded until tomorrow."
        )
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        guard activity == EGuardShared.Activity.downtime else { return }
        notify(
            identifier: "downtime.warning",
            title: "Downtime starts soon",
            body: "Apps will be shielded in about five minutes."
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
