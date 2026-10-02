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

    /// Calendar weekdays (Sunday = 1) on which the window starts. School nights are Sunday to Thursday.
    var startWeekdays: [Int] {
        switch self {
        case .everyDay: [1, 2, 3, 4, 5, 6, 7]
        case .schoolNights: [1, 2, 3, 4, 5]
        }
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
    /// The whole-device daily allowance registered for the child device, in minutes.
    var screenTimeLimitMinutes: Int?

    static let empty = ActivityScheduleSnapshot()

    var isMonitoringAnything: Bool {
        isDowntimeScheduled || isDailyLimitMonitoring || screenTimeLimitMinutes != nil
    }
}

/// Schedules and reads Device Activity monitoring, which enforces downtime and daily allowances.
@MainActor
protocol ActivityScheduleService: AnyObject {
    func scheduleDowntime(_ window: DowntimeWindow, days: BedtimeDays) throws
    func stopDowntime()
    func scheduleDailyLimits(gaming: DailyLimit?, socialApps: DailyLimit?) throws
    func stopDailyLimits()
    /// The child device's daily screen-time allowance over the apps the family chose to count.
    func scheduleScreenTimeLimit(minutes: Int, selection: ActivitySelectionSnapshot) throws
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
