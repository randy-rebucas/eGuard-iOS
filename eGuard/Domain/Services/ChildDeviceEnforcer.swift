import Foundation

/// Facts the enforcer needs beyond the config itself.
nonisolated struct EnforcementContext: Sendable {
    var screenTimeSelection: ActivitySelectionSnapshot
    /// The family's zone, so weekends and school nights agree with what the parent sees.
    var timeZone: TimeZone
    var now: Date = .now
    /// `features.locationSharing` from the last sync: false on plans without location, so sharing reads back off.
    var locationSharingAllowed = true

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
    /// Requires automatic date and time while the saved policy depends on the clock (bedtime, limits).
    func updateClockLock(policy: [PolicyEntry])
}

extension ChildDeviceEnforcer {
    func updateClockLock(policy: [PolicyEntry]) {}
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
        // WEB (the adult-content filter) and DOWNLOADS (installs need a parent) are enforced through Managed Settings
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
            // One whole-device allowance over the apps the family chose to count, weekdays and weekends each with
            // their own limit (the schedule service switches between them itself, the app needn't be open).
            let weekday = config["dailyMinutes"]?.intValue ?? 0
            let weekend = config["weekendMinutes"]?.intValue ?? weekday
            guard weekday > 0 || weekend > 0 else {
                schedules.stopScreenTimeLimit()
                return
            }
            // No limit on one of them ("0") is the whole day
            try schedules.scheduleScreenTimeLimit(
                weekdayMinutes: weekday > 0 ? weekday : Self.wholeDay,
                weekendMinutes: weekend > 0 ? weekend : Self.wholeDay,
                selection: context.screenTimeSelection
            )

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
            // DOWNLOADS shares the switch: it stays on while either wants it.
            try restrictions.applyInstallApproval(.appApproval, required: config["enabled"]?.boolValue == true)

        case "CONTENT":
            try restrictions.applyContentRating(age: config["maxAgeRating"]?.intValue)

        case "WEB":
            // Apple exposes one adult-content filter. FILTER maps onto it; ALLOWLIST is reported as FILTER.
            let mode = config["mode"]?.stringValue ?? "OFF"
            try restrictions.applyWebContent(mode == "OFF" ? .unrestricted : .limited)

        case "DOWNLOADS":
            // "A parent must approve installs": Ask to Buy isn't available to apps, so App Store installation is
            // denied (shared with APP_APPROVAL) and purchases need the password.
            let requireApproval = config["requireApproval"]?.boolValue == true
            try restrictions.applyInstallApproval(.downloads, required: requireApproval)
            try restrictions.applyPurchaseProtection(requirePassword: requireApproval)

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
        // Screen Time access revoked (Settings, or the child's own passcode in self-approved mode): the stores can
        // still hold old values, but nothing is enforced. Report off, so the parent sees it.
        if key != "LOCATION", !isAuthorized { return Self.offReading(key: key, policy: policy) }
        let restriction = restrictions.snapshot()
        let schedule = schedules.snapshot()

        switch key {
        case "SCREEN_TIME":
            guard let weekday = schedule.screenTimeWeekdayMinutes, let weekend = schedule.screenTimeWeekendMinutes else {
                return .object(["dailyMinutes": .number(0), "weekendMinutes": .number(0)])
            }
            // What is registered, as the server words it ("the whole day" was "no limit")
            func reported(_ minutes: Int) -> JSONValue { .number(Double(minutes >= Self.wholeDay ? 0 : minutes)) }
            return .object(["dailyMinutes": reported(weekday), "weekendMinutes": reported(weekend)])

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
            // 21 is the reported range's ceiling: no cap on the device. Apple has fewer tiers than the server
            // (12 and 13 are both 12+), so the age asked for is reported when the device has its rating.
            let age = RatingTiers.reportedAge(requested: policy?["maxAgeRating"]?.intValue, rating: restriction.maximumAppRating, in: RatingTiers.appStore)
            return .object(["maxAgeRating": .number(Double(age ?? 21))])

        case "APP_APPROVAL":
            // Installs are denied and APP_APPROVAL is one of the reasons (DOWNLOADS alone doesn't make this on)
            let enabled = restriction.denyAppInstallation == true && restriction.installApprovalReasons.contains(.appApproval)
            return .object(["enabled": .bool(enabled)])

        case "CONTENT":
            // The most the device lets through: the higher of the two (no cap on one counts as 21), so either one
            // loosened shows as not matching
            let requested = policy?["maxAgeRating"]?.intValue
            let movies = RatingTiers.reportedAge(requested: requested, rating: restriction.movieRating, in: RatingTiers.movies) ?? 21
            let tv = RatingTiers.reportedAge(requested: requested, rating: restriction.tvRating, in: RatingTiers.tv) ?? 21
            return .object(["maxAgeRating": .number(Double(max(movies, tv)))])

        case "WEB":
            // Apple's filter has no site list of its own: no blocked sites are enforced here
            let filtered = restriction.webContentLimited == true
            return .object([
                "mode": .string(filtered ? "FILTER" : "OFF"),
                "blockedSites": .number(0),
            ])

        case "DOWNLOADS":
            let requireApproval = restriction.denyAppInstallation == true && restriction.installApprovalReasons.contains(.downloads)
            return .object(["requireApproval": .bool(requireApproval)])

        case "LOCATION":
            // Sharing needs the OS permission, the parent's setting and a plan that includes location
            let sharing = locationStatus.isAuthorized && policy?["sharing"]?.boolValue == true && context.locationSharingAllowed
            return .object(["sharing": .bool(sharing)])

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

    /// Bedtime and limits follow the device clock: while either is on, "Set Automatically" can't be turned off, so
    /// the child can't end bedtime or start a new day by changing the time.
    func updateClockLock(policy: [PolicyEntry]) {
        guard isAuthorized else { return }
        let bedtime = policy.first { $0.key == "BEDTIME" }?.config["enabled"]?.boolValue == true
        let limit = policy.first { $0.key == "SCREEN_TIME" }.map { ($0.config["dailyMinutes"]?.intValue ?? 0) > 0 || ($0.config["weekendMinutes"]?.intValue ?? 0) > 0 } ?? false
        try? restrictions.applyAutomaticDateAndTime(require: bedtime || limit)
    }

    /// Longer than any day: a "no limit" day inside a per-day schedule.
    static let wholeDay = 24 * 60

    /// What an unauthorized device has: nothing on, in the server's field shapes.
    static func offReading(key: String, policy: JSONValue?) -> JSONValue? {
        switch key {
        case "SCREEN_TIME": .object(["dailyMinutes": .number(0), "weekendMinutes": .number(0)])
        case "BEDTIME": .object([
            "enabled": .bool(false),
            "start": policy?["start"] ?? .string("22:00"),
            "end": policy?["end"] ?? .string("06:00"),
            "days": policy?["days"] ?? .string(BedtimeDays.everyDay.rawValue),
        ])
        case "APP_RESTRICTIONS", "CONTENT": .object(["maxAgeRating": .number(21)])
        case "APP_APPROVAL", "UNINSTALL_PROTECTION": .object(["enabled": .bool(false)])
        case "WEB": .object(["mode": .string("OFF"), "blockedSites": .number(0)])
        case "DOWNLOADS": .object(["requireApproval": .bool(false)])
        default: nil
        }
    }
}
