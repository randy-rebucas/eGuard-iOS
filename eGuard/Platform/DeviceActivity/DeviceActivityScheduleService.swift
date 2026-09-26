import DeviceActivity
import FamilyControls
import Foundation
import OSLog
import ManagedSettings

/// Registers downtime and daily allowance schedules with Device Activity.
/// The monitor extension enforces them; this service only schedules and verifies.
final class DeviceActivityScheduleService: ActivityScheduleService {
    private let center = DeviceActivityCenter()

    init() {}

    func scheduleDowntime(_ window: DowntimeWindow) throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: window.start.dateComponents,
            intervalEnd: window.end.dateComponents,
            repeats: true,
            warningTime: DateComponents(minute: 5)
        )
        do {
            try center.startMonitoring(EGuardShared.Activity.downtime, during: schedule)
            EGuardLog.configuration.info("Downtime schedule registered.")
        } catch {
            throw ProtectionConfigurationError.platformError(Self.describe(error))
        }
    }

    func stopDowntime() {
        center.stopMonitoring([EGuardShared.Activity.downtime])
        ManagedSettingsStore(named: EGuardShared.Store.downtime).clearAllSettings()
    }

    func scheduleDailyLimits(gaming: DailyLimit?, socialApps: DailyLimit?) throws {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let defaults = EGuardShared.sharedDefaults

        if let gaming, let selection = ActivitySelectionCodec.selection(from: gaming.selection) {
            events[EGuardShared.Event.gaming] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: gaming.minutes)
            )
            defaults?.set(gaming.selection.encodedSelection, forKey: EGuardShared.DefaultsKey.gamingSelection)
        } else {
            defaults?.removeObject(forKey: EGuardShared.DefaultsKey.gamingSelection)
        }

        if let socialApps, let selection = ActivitySelectionCodec.selection(from: socialApps.selection) {
            events[EGuardShared.Event.socialApps] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: socialApps.minutes)
            )
            defaults?.set(socialApps.selection.encodedSelection, forKey: EGuardShared.DefaultsKey.socialAppsSelection)
        } else {
            defaults?.removeObject(forKey: EGuardShared.DefaultsKey.socialAppsSelection)
        }

        guard !events.isEmpty else {
            stopDailyLimits()
            return
        }

        // One repeating all-day schedule; each event fires when its allowance is used up.
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        do {
            try center.startMonitoring(EGuardShared.Activity.dailyLimits, during: schedule, events: events)
            EGuardLog.configuration.info("Daily limit schedule registered.")
        } catch {
            throw ProtectionConfigurationError.platformError(Self.describe(error))
        }
    }

    func stopDailyLimits() {
        center.stopMonitoring([EGuardShared.Activity.dailyLimits])
        ManagedSettingsStore(named: EGuardShared.Store.dailyLimits).clearAllSettings()
    }

    func stopAll() {
        stopDowntime()
        stopDailyLimits()
    }

    func snapshot() -> ActivityScheduleSnapshot {
        var snapshot = ActivityScheduleSnapshot()
        let activities = center.activities

        snapshot.isDowntimeScheduled = activities.contains(EGuardShared.Activity.downtime)
        if snapshot.isDowntimeScheduled, let schedule = center.schedule(for: EGuardShared.Activity.downtime) {
            snapshot.downtimeWindow = DowntimeWindow(
                start: TimeOfDay(hour: schedule.intervalStart.hour ?? 0, minute: schedule.intervalStart.minute ?? 0),
                end: TimeOfDay(hour: schedule.intervalEnd.hour ?? 0, minute: schedule.intervalEnd.minute ?? 0)
            )
        }

        snapshot.isDailyLimitMonitoring = activities.contains(EGuardShared.Activity.dailyLimits)
        if snapshot.isDailyLimitMonitoring {
            let events = center.events(for: EGuardShared.Activity.dailyLimits)
            snapshot.gamingLimitMinutes = events[EGuardShared.Event.gaming].map { Self.minutes(from: $0.threshold) }
            snapshot.socialAppsLimitMinutes = events[EGuardShared.Event.socialApps].map { Self.minutes(from: $0.threshold) }
        }
        return snapshot
    }

    private static func minutes(from components: DateComponents) -> Int {
        (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func describe(_ error: Error) -> String {
        if let monitoringError = error as? DeviceActivityCenter.MonitoringError {
            switch monitoringError {
            case .intervalTooShort: return "The schedule must cover at least fifteen minutes."
            case .intervalTooLong: return "The schedule cannot be longer than one week."
            case .excessiveActivities: return "Too many schedules are registered on this device."
            case .invalidDateComponents: return "The schedule times are not valid."
            case .unauthorized: return "eGuard is not authorized to monitor device activity."
            @unknown default: break
            }
        }
        return error.localizedDescription
    }
}

/// In-memory implementation for previews, the simulator, and tests.
final class MockActivityScheduleService: ActivityScheduleService {
    private(set) var state = ActivityScheduleSnapshot()
    var errorToThrow: ProtectionConfigurationError?

    init(state: ActivityScheduleSnapshot = .empty) {
        self.state = state
    }

    func scheduleDowntime(_ window: DowntimeWindow) throws {
        if let errorToThrow { throw errorToThrow }
        state.isDowntimeScheduled = true
        state.downtimeWindow = window
    }

    func stopDowntime() {
        state.isDowntimeScheduled = false
        state.downtimeWindow = nil
    }

    func scheduleDailyLimits(gaming: DailyLimit?, socialApps: DailyLimit?) throws {
        if let errorToThrow { throw errorToThrow }
        state.isDailyLimitMonitoring = gaming != nil || socialApps != nil
        state.gamingLimitMinutes = gaming?.minutes
        state.socialAppsLimitMinutes = socialApps?.minutes
    }

    func stopDailyLimits() {
        state.isDailyLimitMonitoring = false
        state.gamingLimitMinutes = nil
        state.socialAppsLimitMinutes = nil
    }

    func stopAll() {
        state = .empty
    }

    func snapshot() -> ActivityScheduleSnapshot {
        state
    }

    /// Simulates the system dropping eGuard's schedules.
    func simulateDrift() {
        state = .empty
    }
}
