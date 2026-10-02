import Foundation

/// How the child device learns how much screen time was used today.
///
/// iOS doesn't let an app read usage totals, and Device Activity report extensions can't send data
/// anywhere. What Device Activity does offer is threshold events, so the app registers a ladder of
/// "N minutes used" events over the counted apps. The monitor extension records the last rung reached,
/// and the app reports that as today's total: a floor, in 15-minute steps, over the counted apps only.
@MainActor
protocol UsageSource: AnyObject {
    /// Today's (or yesterday's final) recorded total, or nil when nothing has been recorded yet.
    func pendingUsage() -> UsageRequest?
}

/// The rungs of the usage ladder: every 15 minutes up to the limit, coarser when the limit is long,
/// so the number of events stays reasonable.
nonisolated enum UsageTicks {
    static let stepMinutes = 15
    static let maximumTicks = 48

    /// Minutes at which a tick fires, strictly below `limit` (the limit itself fires the limit event).
    static func steps(limit: Int) -> [Int] {
        guard limit > stepMinutes else { return [] }
        let rawStep = Int((Double(limit) / Double(maximumTicks)).rounded(.up))
        let step = max(stepMinutes, Int((Double(rawStep) / Double(stepMinutes)).rounded(.up)) * stepMinutes)
        return Array(stride(from: step, to: limit, by: step))
    }

    /// `YYYY-MM-DD` in the device's local date, which is what `/usage` expects.
    static func localDate(_ date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Reads what the monitor extension recorded in the App Group.
final class AppGroupUsageSource: UsageSource {
    init() {}

    func pendingUsage() -> UsageRequest? {
        guard let defaults = EGuardShared.sharedDefaults,
              let date = defaults.string(forKey: EGuardShared.DefaultsKey.usageDate), !date.isEmpty else { return nil }
        let minutes = defaults.integer(forKey: EGuardShared.DefaultsKey.usageMinutes)
        return UsageRequest(date: date, totalMinutes: min(max(minutes, 0), 1440), apps: nil, hourly: nil)
    }
}

/// A controllable source for previews and tests.
final class MockUsageSource: UsageSource {
    var usage: UsageRequest?

    init(usage: UsageRequest? = nil) {
        self.usage = usage
    }

    func pendingUsage() -> UsageRequest? { usage }
}
