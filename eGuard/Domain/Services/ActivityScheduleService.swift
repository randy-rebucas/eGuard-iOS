import Foundation

/// A daily allowance for a set of apps or categories.
nonisolated struct DailyLimit: Equatable, Sendable {
    var minutes: Int
    var selection: ActivitySelectionSnapshot
}

/// Which nights a bedtime window covers. Shared vocabulary with the server's `BEDTIME.days`.
nonisolated enum BedtimeDays: String, Codable, CaseIterable, Sendable {
    case everyDay = "EVERY_DAY"
    case schoolNights = "SCHOOL_NIGHTS"

    var title: String {
        switch self {
        case .everyDay: "Every day"
        case .schoolNights: "School nights"
        }
    }

    /// Calendar weekdays (Sunday = 1) on which a window starting at `start` begins. School nights are Sunday to
    /// Thursday, and a window belongs to the night it starts on, or to the evening before when it starts after
    /// midnight (before 12:00), as the server's `bedtimeActive` defines it. So a school-nights window from 00:30
    /// starts on Monday to Friday mornings.
    func startWeekdays(startingAt start: TimeOfDay) -> [Int] {
        switch self {
        case .everyDay: [1, 2, 3, 4, 5, 6, 7]
        case .schoolNights: start.hour < 12 ? [2, 3, 4, 5, 6] : [1, 2, 3, 4, 5]
        }
    }

    /// The days a set of registered per-weekday schedules stands for, or nil when they match no setting for a
    /// window starting at `start` (e.g. registered by an older build with the other rule): reported as not set.
    static func registered(startWeekdays: Set<Int>, startingAt start: TimeOfDay) -> BedtimeDays? {
        guard !startWeekdays.isEmpty else { return nil }
        return Set(BedtimeDays.schoolNights.startWeekdays(startingAt: start)) == startWeekdays ? .schoolNights : nil
    }
}

/// What eGuard can read back from Device Activity monitoring.
nonisolated struct ActivityScheduleSnapshot: Equatable, Sendable {
    var isDowntimeScheduled = false
    var downtimeWindow: DowntimeWindow?
    var downtimeDays: BedtimeDays?
    var isDailyLimitMonitoring = false
    var gamingLimitMinutes: Int?
    var socialAppsLimitMinutes: Int?
    /// The whole-device daily allowance registered for the child device, in minutes: Monday to Friday, and
    /// Saturday and Sunday. The same value twice when one schedule covers every day.
    var screenTimeWeekdayMinutes: Int?
    var screenTimeWeekendMinutes: Int?

    static let empty = ActivityScheduleSnapshot()

    var isMonitoringAnything: Bool {
        isDowntimeScheduled || isDailyLimitMonitoring || screenTimeWeekdayMinutes != nil
    }
}

/// Schedules and reads Device Activity monitoring, which enforces downtime and daily allowances.
@MainActor
protocol ActivityScheduleService: AnyObject {
    func scheduleDowntime(_ window: DowntimeWindow, days: BedtimeDays) throws
    func stopDowntime()
    func scheduleDailyLimits(gaming: DailyLimit?, socialApps: DailyLimit?) throws
    func stopDailyLimits()
    /// The child device's daily screen-time allowance over the apps the family chose to count: one value for
    /// Monday to Friday, one for Saturday and Sunday. Doesn't re-register when nothing changed.
    func scheduleScreenTimeLimit(weekdayMinutes: Int, weekendMinutes: Int, selection: ActivitySelectionSnapshot) throws
    func stopScreenTimeLimit()
    func stopAll()

    /// Reads what the system currently monitors. Used for verification and drift detection.
    func snapshot() -> ActivityScheduleSnapshot
}

extension ActivityScheduleService {
    func scheduleDowntime(_ window: DowntimeWindow) throws {
        try scheduleDowntime(window, days: .everyDay)
    }
}
