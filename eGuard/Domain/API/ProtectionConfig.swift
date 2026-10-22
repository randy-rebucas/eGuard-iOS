import Foundation

/// Static knowledge about the ten server-side protections: names, icons, and how to describe a config.
nonisolated enum ProtectionKey {
    static let all = ["SCREEN_TIME", "BEDTIME", "APP_RESTRICTIONS", "APP_APPROVAL", "CONTENT", "WEB", "DOWNLOADS", "LOCATION", "NOTIFICATIONS", "UNINSTALL_PROTECTION"]

    /// The six the design shows on Recommended Setup, in order.
    static let recommendedOrder = ["SCREEN_TIME", "BEDTIME", "APP_RESTRICTIONS", "CONTENT", "DOWNLOADS", "LOCATION"]

    static func name(_ key: String) -> String {
        switch key {
        case "SCREEN_TIME": "Daily screen time"
        case "BEDTIME": "Bedtime"
        case "APP_RESTRICTIONS": "App restrictions"
        case "APP_APPROVAL": "App approval"
        case "CONTENT": "Explicit content"
        case "WEB": "Web filtering"
        case "DOWNLOADS": "App downloads"
        case "LOCATION": "Location sharing"
        case "NOTIFICATIONS": "Notifications"
        case "UNINSTALL_PROTECTION": "Uninstall protection"
        default: key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func icon(_ key: String) -> String {
        switch key {
        case "SCREEN_TIME": "hourglass"
        case "BEDTIME": "moon"
        case "APP_RESTRICTIONS": "shield"
        case "APP_APPROVAL": "check-circle"
        case "CONTENT": "eye-off"
        case "WEB": "globe"
        case "DOWNLOADS": "download"
        case "LOCATION": "map-pin"
        case "NOTIFICATIONS": "bell"
        case "UNINSTALL_PROTECTION": "lock"
        default: "shield"
        }
    }

    static func symbol(_ key: String) -> String {
        LucideIcon.symbol(for: icon(key))
    }

    /// Whether a device's reported config is the one asked for, as the server compares them: exactly, except WEB,
    /// where only `mode` counts (`blockedSites` is the policy's own count; iOS has no site list and reports 0).
    static func reportMatches(key: String, reported: JSONValue?, policy: JSONValue?) -> Bool {
        guard let reported, let policy else { return reported == nil && policy == nil }
        let device = reported.removing("key")
        let asked = policy.removing("key")
        if key == "WEB" { return device["mode"] == asked["mode"] }
        return device == asked
    }

    /// One line explaining what the protection does.
    static func explanation(_ key: String) -> String {
        switch key {
        case "SCREEN_TIME": "A daily allowance for the whole device, with a separate weekend value."
        case "BEDTIME": "Apps are locked from the start time until the end time."
        case "APP_RESTRICTIONS": "Apps above this age rating can't be opened."
        case "APP_APPROVAL": "New apps wait for your approval before they can be used."
        case "CONTENT": "Movies, music, and books above this rating are hidden."
        case "WEB": "Adult websites are filtered, or only an allow list can be visited."
        case "DOWNLOADS": "New downloads need a parent's approval."
        case "LOCATION": "The device shares its location with you while eGuard runs."
        case "NOTIFICATIONS": "Notifications are silenced during bedtime."
        case "UNINSTALL_PROTECTION": "Stops the child from removing eGuard."
        default: ""
        }
    }
}

/// Builds parent-friendly labels for protection configs, matching the server's wording.
nonisolated enum ProtectionConfigFormatter {
    static func label(key: String, config: JSONValue) -> String {
        switch key {
        case "SCREEN_TIME":
            guard let minutes = config["dailyMinutes"]?.intValue else { return "Not set" }
            // Worded as the server's describeConfig (lib/protections.ts): weekends named only when they differ
            let weekend = config["weekendMinutes"]?.intValue
            guard let weekend, weekend != minutes else { return "\(duration(minutes)) / day" }
            return "\(duration(minutes)) / day, \(duration(weekend)) weekends"
        case "BEDTIME":
            guard config["enabled"]?.boolValue != false,
                  let start = config["start"]?.stringValue, let end = config["end"]?.stringValue else { return "Off" }
            let days = config["days"]?.stringValue == "SCHOOL_NIGHTS" ? ", school nights" : ""
            return "\(time(start)) – \(time(end))\(days)"
        case "APP_RESTRICTIONS":
            guard let rating = config["maxAgeRating"]?.intValue else { return "Not set" }
            return "Apps rated \(rating)+ and under"
        case "CONTENT":
            guard let rating = config["maxAgeRating"]?.intValue else { return "Not set" }
            return "Rated \(rating)+ and under"
        case "APP_APPROVAL":
            return config["enabled"]?.boolValue == true ? "Approval required" : "Off"
        case "WEB":
            // blockedSites isn't named: the policy's number is a placeholder
            switch config["mode"]?.stringValue {
            case "FILTER": return "Adult and unsafe sites filtered"
            case "ALLOWLIST": return "Allowed sites only"
            default: return "Off"
            }
        case "DOWNLOADS":
            return config["requireApproval"]?.boolValue == true ? "Parent approval" : "Unrestricted"
        case "LOCATION":
            return config["sharing"]?.boolValue == true ? "Sharing" : "Sharing off"
        case "NOTIFICATIONS":
            return config["quietDuringBedtime"]?.boolValue == true ? "Quiet during bedtime" : "Unrestricted"
        case "UNINSTALL_PROTECTION":
            return config["enabled"]?.boolValue == true ? "On" : "Off"
        default:
            return ""
        }
    }

    /// "3h", "45m", or "1h 30m".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    /// "21:30" → "9:30 PM".
    static func time(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hhmm }
        return TimeOfDay(hour: parts[0], minute: parts[1]).formatted
    }

    /// "HH:MM" from a `TimeOfDay`.
    static func hhmm(_ time: TimeOfDay) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    static func timeOfDay(_ hhmm: String) -> TimeOfDay {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return TimeOfDay(hour: 21, minute: 0) }
        return TimeOfDay(hour: parts[0], minute: parts[1])
    }
}

/// The `PROTECTED` defaults for an age, and the `BALANCED` variant derived from them.
nonisolated enum ProtectionDefaults {
    static let ratingTiers = [4, 9, 13, 16, 18]

    static func config(key: String, age: Int, profile: String) -> JSONValue {
        let balanced = profile == "BALANCED"
        let tier = ratingTier(for: age, bump: balanced ? 1 : 0)
        switch key {
        case "SCREEN_TIME":
            let daily = (age < 10 ? 120 : 180) + (balanced ? 60 : 0)
            return .object(["dailyMinutes": .number(Double(daily)), "weekendMinutes": .number(Double(daily + 60))])
        case "BEDTIME":
            let start = balanced ? "22:30" : "21:30"
            return .object(["enabled": .bool(true), "start": .string(start), "end": .string("06:00"), "days": .string("EVERY_DAY")])
        case "APP_RESTRICTIONS", "CONTENT":
            return .object(["maxAgeRating": .number(Double(tier))])
        case "APP_APPROVAL", "UNINSTALL_PROTECTION":
            return .object(["enabled": .bool(true)])
        case "WEB":
            return .object(["mode": .string("FILTER"), "blockedSites": .number(42)])
        case "DOWNLOADS":
            return .object(["requireApproval": .bool(true)])
        case "LOCATION":
            return .object(["sharing": .bool(true)])
        case "NOTIFICATIONS":
            return .object(["quietDuringBedtime": .bool(true)])
        default:
            return .object([:])
        }
    }

    static func ratingTier(for age: Int, bump: Int) -> Int {
        let base = ratingTiers.last { $0 <= max(age, 4) } ?? 4
        guard let index = ratingTiers.firstIndex(of: base) else { return base }
        return ratingTiers[min(index + bump, ratingTiers.count - 1)]
    }
}
