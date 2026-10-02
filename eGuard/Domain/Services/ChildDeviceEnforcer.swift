import Foundation

/// Facts the enforcer needs beyond the config itself.
nonisolated struct EnforcementContext: Sendable {
    var screenTimeSelection: ActivitySelectionSnapshot
    /// The family's zone, so weekends and school nights agree with what the parent sees.
    var timeZone: TimeZone
    var now: Date = .now

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    var isWeekend: Bool { calendar.isDateInWeekend(now) }
}

/// Applies the server's protection configs on the child's device and reads the real values back.
/// Reports must come from the OS, never from the config that was asked for.
@MainActor
protocol ChildDeviceEnforcer: AnyObject {
    /// The protection keys this platform can report. iOS never reports `NOTIFICATIONS`.
    var supportedKeys: [String] { get }
    var isAuthorized: Bool { get }
    func capability(for key: String) -> Capability
    func requestAuthorization() async throws
    func apply(_ entry: PolicyEntry, context: EnforcementContext) throws
    /// The device's real value for `key`, in the exact field shape the server expects, or nil when unsupported.
    func readBack(key: String, policy: JSONValue?, context: EnforcementContext) -> JSONValue?
    /// Releases every restriction and schedule. Used when a parent removes the device.
    func clearAll()
}

/// Maps the ten server protections onto Apple's Screen Time frameworks.
/// Where Apple offers no exact match the mapping is documented inline and reported honestly.
final class ScreenTimeEnforcer: ChildDeviceEnforcer {
    private let restrictions: RestrictionService
    private let schedules: ActivityScheduleService
    private let authorization: ParentalControlAuthorizationService
    private let environment: PlatformEnvironment
    private let locationStatus: LocationReporting

    init(
        restrictions: RestrictionService,
        schedules: ActivityScheduleService,
        authorization: ParentalControlAuthorizationService,
        environment: PlatformEnvironment,
        locationStatus: LocationReporting
    ) {
        self.restrictions = restrictions
        self.schedules = schedules
        self.authorization = authorization
        self.environment = environment
        self.locationStatus = locationStatus
    }

    var supportedKeys: [String] { ProtectionKey.all.filter { capability(for: $0) != .unsupported } }

    var isAuthorized: Bool {
        authorization.refreshAuthorizationStatus()
        return authorization.authorizationStatus.isAuthorized
    }

    /// The spec's iOS capability table.
    func capability(for key: String) -> Capability {
        switch key {
        case "NOTIFICATIONS": return .unsupported
        case "LOCATION": return .guided
        case "WEB": return environment.isFamilyControlsAvailable ? .guided : .unsupported
        case "DOWNLOADS": return environment.isFamilyControlsAvailable ? .verifyOnly : .unsupported
        default: return environment.isFamilyControlsAvailable ? .available : .unsupported
        }
    }

    func requestAuthorization() async throws {
        authorization.memberKind = .child
        do {
            try await authorization.requestAuthorization()
        } catch ParentalControlAuthorizationError.invalidAccountType {
            // Not a child account in Family Sharing: the device owner approves instead.
            authorization.memberKind = .individual
            try await authorization.requestAuthorization()
        }
    }

    func apply(_ entry: PolicyEntry, context: EnforcementContext) throws {
        let capability = capability(for: entry.key)
        guard capability != .unsupported else { throw ProtectionConfigurationError.unsupported }
        guard entry.key == "LOCATION" || isAuthorized else { throw ProtectionConfigurationError.notAuthorized }
        let config = entry.config

        switch entry.key {
        case "SCREEN_TIME":
            // One whole-device allowance over the apps the family chose to count, re-registered every sync
            // with the limit that applies today (weekday or weekend).
            let minutes = Self.todayLimit(config, context: context)
            guard minutes > 0 else {
                schedules.stopScreenTimeLimit()
                return
            }
            try schedules.scheduleScreenTimeLimit(minutes: minutes, selection: context.screenTimeSelection)

        case "BEDTIME":
            guard config["enabled"]?.boolValue == true,
                  let start = config["start"]?.stringValue, let end = config["end"]?.stringValue else {
                schedules.stopDowntime()
                return
            }
            let window = DowntimeWindow(start: ProtectionConfigFormatter.timeOfDay(start), end: ProtectionConfigFormatter.timeOfDay(end))
            guard window.isValid else { throw ProtectionConfigurationError.invalidSchedule }
            let days = BedtimeDays(rawValue: config["days"]?.stringValue ?? "") ?? .everyDay
            try schedules.scheduleDowntime(window, days: days)

        case "APP_RESTRICTIONS":
            try restrictions.applyMaximumAppRating(age: config["maxAgeRating"]?.intValue)

        case "APP_APPROVAL":
            // iOS can't hold a new app for approval. With approval on, only a parent can install apps
            // (App Store installation is denied); the parent adds apps ahead of time in App Management.
            try restrictions.applyAppInstallation(config["enabled"]?.boolValue == true ? .blocked : .allowed)

        case "CONTENT":
            try restrictions.applyContentRating(age: config["maxAgeRating"]?.intValue)

        case "WEB":
            // Apple exposes one adult-content filter. FILTER maps onto it; ALLOWLIST is reported as FILTER.
            let mode = config["mode"]?.stringValue ?? "OFF"
            try restrictions.applyWebContent(mode == "OFF" ? .unrestricted : .limited)

        case "DOWNLOADS":
            // Ask to Buy isn't readable by apps; requiring the App Store password is the closest verifiable equivalent.
            try restrictions.applyPurchaseProtection(requirePassword: config["requireApproval"]?.boolValue == true)

        case "LOCATION":
            // Nothing to apply: the person grants location access during setup; sync sends fixes while allowed.
            break

        case "UNINSTALL_PROTECTION":
            try restrictions.applyAppRemoval(deny: config["enabled"]?.boolValue == true)

        default:
            throw ProtectionConfigurationError.unsupported
        }
    }

    func readBack(key: String, policy: JSONValue?, context: EnforcementContext) -> JSONValue? {
        guard capability(for: key) != .unsupported else { return nil }
        let restriction = restrictions.snapshot()
        let schedule = schedules.snapshot()

        switch key {
        case "SCREEN_TIME":
            guard let registered = schedule.screenTimeLimitMinutes else {
                return .object(["dailyMinutes": .number(0), "weekendMinutes": .number(0)])
            }
            // The device enforces one value per day. When it matches today's policy limit, the configured
            // pair is what the device has; otherwise report the single value it really enforces.
            if let policy, Self.todayLimit(policy, context: context) == registered {
                return .object(["dailyMinutes": policy["dailyMinutes"] ?? .number(Double(registered)), "weekendMinutes": policy["weekendMinutes"] ?? .number(Double(registered))])
            }
            return .object(["dailyMinutes": .number(Double(registered)), "weekendMinutes": .number(Double(registered))])

        case "BEDTIME":
            if schedule.isDowntimeScheduled, let window = schedule.downtimeWindow {
                return .object([
                    "enabled": .bool(true),
                    "start": .string(ProtectionConfigFormatter.hhmm(window.start)),
                    "end": .string(ProtectionConfigFormatter.hhmm(window.end)),
                    "days": .string((schedule.downtimeDays ?? .everyDay).rawValue),
                ])
            }
            return .object([
                "enabled": .bool(false),
                "start": policy?["start"] ?? .string("22:00"),
                "end": policy?["end"] ?? .string("06:00"),
                "days": policy?["days"] ?? .string(BedtimeDays.everyDay.rawValue),
            ])

        case "APP_RESTRICTIONS":
            // 21 is the reported range's ceiling: no cap on the device.
            return .object(["maxAgeRating": .number(Double(restriction.maximumAppRatingAge ?? 21))])

        case "APP_APPROVAL":
            return .object(["enabled": .bool(restriction.denyAppInstallation == true)])

        case "CONTENT":
            return .object(["maxAgeRating": .number(Double(restriction.contentRatingAge ?? 21))])

        case "WEB":
            let filtered = restriction.webContentLimited == true
            return .object([
                "mode": .string(filtered ? "FILTER" : "OFF"),
                "blockedSites": filtered ? (policy?["blockedSites"] ?? .number(0)) : .number(0),
            ])

        case "DOWNLOADS":
            return .object(["requireApproval": .bool(restriction.requirePasswordForPurchases == true)])

        case "LOCATION":
            return .object(["sharing": .bool(locationStatus.isAuthorized && policy?["sharing"]?.boolValue == true)])

        case "UNINSTALL_PROTECTION":
            return .object(["enabled": .bool(restriction.denyAppRemoval == true)])

        default:
            return nil
        }
    }

    func clearAll() {
        restrictions.clearAllRestrictions()
        schedules.stopAll()
    }

    /// The allowance that applies today, in the family's time zone.
    static func todayLimit(_ config: JSONValue, context: EnforcementContext) -> Int {
        let daily = config["dailyMinutes"]?.intValue ?? 0
        let weekend = config["weekendMinutes"]?.intValue ?? daily
        return context.isWeekend ? weekend : daily
    }
}
