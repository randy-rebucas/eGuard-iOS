import Foundation

/// A daily allowance for a set of apps or categories.
nonisolated struct DailyLimit: Equatable, Sendable {
    var minutes: Int
    var selection: ActivitySelectionSnapshot
}

/// What eGuard can read back from Device Activity monitoring.
nonisolated struct ActivityScheduleSnapshot: Equatable, Sendable {
    var isDowntimeScheduled = false
    var downtimeWindow: DowntimeWindow?
    var isDailyLimitMonitoring = false
    var gamingLimitMinutes: Int?
    var socialAppsLimitMinutes: Int?

    static let empty = ActivityScheduleSnapshot()

    var isMonitoringAnything: Bool {
        isDowntimeScheduled || isDailyLimitMonitoring
    }
}

/// Schedules and reads Device Activity monitoring, which enforces downtime and daily allowances.
@MainActor
protocol ActivityScheduleService: AnyObject {
    func scheduleDowntime(_ window: DowntimeWindow) throws
    func stopDowntime()
    func scheduleDailyLimits(gaming: DailyLimit?, socialApps: DailyLimit?) throws
    func stopDailyLimits()
    func stopAll()

    /// Reads what the system currently monitors. Used for verification and drift detection.
    func snapshot() -> ActivityScheduleSnapshot
}
