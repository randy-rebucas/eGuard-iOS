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

    func scheduleDowntime(_ window: DowntimeWindow, days: BedtimeDays) throws {
        // Replace whatever bedtime schedule exists so every-day and school-night registrations never overlap.
        center.stopMonitoring(Self.allDowntimeNames)
        do {
            switch days {
            case .everyDay:
                let schedule = DeviceActivitySchedule(
                    intervalStart: window.start.dateComponents,
                    intervalEnd: window.end.dateComponents,
                    repeats: true,
                    warningTime: DateComponents(minute: 5)
                )
                try center.startMonitoring(EGuardShared.Activity.downtime, during: schedule)
            case .schoolNights:
                // One weekly schedule per start night. A window ending before it starts runs into the next day.
                for weekday in days.startWeekdays {
                    var start = window.start.dateComponents
                    start.weekday = weekday
                    var end = window.end.dateComponents
                    end.weekday = window.end > window.start ? weekday : (weekday % 7) + 1
                    let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true, warningTime: DateComponents(minute: 5))
                    try center.startMonitoring(EGuardShared.Activity.downtime(weekday: weekday), during: schedule)
                }
            }
            EGuardLog.configuration.info("Downtime schedule registered.")
        } catch {
            throw ProtectionConfigurationError.platformError(Self.describe(error))
        }
    }

    private static var allDowntimeNames: [DeviceActivityName] {
        [EGuardShared.Activity.downtime] + (1...7).map { EGuardShared.Activity.downtime(weekday: $0) }
    }

    func stopDowntime() {
        center.stopMonitoring(Self.allDowntimeNames)
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

        do {
            try center.startMonitoring(EGuardShared.Activity.dailyLimits, during: Self.allDay, events: events)
            EGuardLog.configuration.info("Daily limit schedule registered.")
        } catch {
            throw ProtectionConfigurationError.platformError(Self.describe(error))
        }
    }

    /// One repeating all-day schedule; each event fires when its allowance is used up.
    private static let allDay = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0, minute: 0),
        intervalEnd: DateComponents(hour: 23, minute: 59),
        repeats: true
    )

    func stopDailyLimits() {
        center.stopMonitoring([EGuardShared.Activity.dailyLimits])
        ManagedSettingsStore(named: EGuardShared.Store.dailyLimits).clearAllSettings()
    }

    func scheduleScreenTimeLimit(minutes: Int, selection: ActivitySelectionSnapshot) throws {
        guard let resolved = ActivitySelectionCodec.selection(from: selection), !selection.isEmpty else {
            throw ProtectionConfigurationError.selectionRequired
        }
        func event(at threshold: Int) -> DeviceActivityEvent {
            DeviceActivityEvent(
                applications: resolved.applicationTokens,
                categories: resolved.categoryTokens,
                webDomains: resolved.webDomainTokens,
                threshold: DateComponents(hour: threshold / 60, minute: threshold % 60)
            )
        }
        // The limit event, plus a ladder of usage rungs below it so the extension can record a running total.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [EGuardShared.Event.screenTime: event(at: minutes)]
        for tick in UsageTicks.steps(limit: minutes) {
            events[EGuardShared.Event.usageTick(minutes: tick)] = event(at: tick)
        }
        let defaults = EGuardShared.sharedDefaults
        defaults?.set(selection.encodedSelection, forKey: EGuardShared.DefaultsKey.screenTimeSelection)
        defaults?.set(minutes, forKey: EGuardShared.DefaultsKey.screenTimeMinutes)
        do {
            try center.startMonitoring(EGuardShared.Activity.screenTime, during: Self.allDay, events: events)
            EGuardLog.configuration.info("Screen time limit registered.")
        } catch {
            throw ProtectionConfigurationError.platformError(Self.describe(error))
        }
    }

    func stopScreenTimeLimit() {
        center.stopMonitoring([EGuardShared.Activity.screenTime])
        EGuardShared.sharedDefaults?.removeObject(forKey: EGuardShared.DefaultsKey.screenTimeSelection)
        EGuardShared.sharedDefaults?.removeObject(forKey: EGuardShared.DefaultsKey.screenTimeMinutes)
    }

    func stopAll() {
        stopDowntime()
        stopDailyLimits()
        stopScreenTimeLimit()
        ManagedSettingsStore(named: EGuardShared.Store.dailyLimits).clearAllSettings()
    }

    func snapshot() -> ActivityScheduleSnapshot {
        var snapshot = ActivityScheduleSnapshot()
        let activities = center.activities

        let everyDay = activities.contains(EGuardShared.Activity.downtime)
        let schoolNights = BedtimeDays.schoolNights.startWeekdays.allSatisfy { activities.contains(EGuardShared.Activity.downtime(weekday: $0)) }
        snapshot.isDowntimeScheduled = everyDay || schoolNights
        if snapshot.isDowntimeScheduled {
            let name = everyDay ? EGuardShared.Activity.downtime : EGuardShared.Activity.downtime(weekday: 1)
            snapshot.downtimeDays = everyDay ? .everyDay : .schoolNights
            if let schedule = center.schedule(for: name) {
                snapshot.downtimeWindow = DowntimeWindow(
                    start: TimeOfDay(hour: schedule.intervalStart.hour ?? 0, minute: schedule.intervalStart.minute ?? 0),
                    end: TimeOfDay(hour: schedule.intervalEnd.hour ?? 0, minute: schedule.intervalEnd.minute ?? 0)
                )
            }
        }

        snapshot.isDailyLimitMonitoring = activities.contains(EGuardShared.Activity.dailyLimits)
        if snapshot.isDailyLimitMonitoring {
            let events = center.events(for: EGuardShared.Activity.dailyLimits)
            snapshot.gamingLimitMinutes = events[EGuardShared.Event.gaming].map { Self.minutes(from: $0.threshold) }
            snapshot.socialAppsLimitMinutes = events[EGuardShared.Event.socialApps].map { Self.minutes(from: $0.threshold) }
        }
        if activities.contains(EGuardShared.Activity.screenTime) {
            snapshot.screenTimeLimitMinutes = center.events(for: EGuardShared.Activity.screenTime)[EGuardShared.Event.screenTime].map { Self.minutes(from: $0.threshold) }
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

    func scheduleDowntime(_ window: DowntimeWindow, days: BedtimeDays) throws {
        if let errorToThrow { throw errorToThrow }
        state.isDowntimeScheduled = true
        state.downtimeWindow = window
        state.downtimeDays = days
    }

    func stopDowntime() {
        state.isDowntimeScheduled = false
        state.downtimeWindow = nil
        state.downtimeDays = nil
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

    func scheduleScreenTimeLimit(minutes: Int, selection: ActivitySelectionSnapshot) throws {
        if let errorToThrow { throw errorToThrow }
        guard !selection.isEmpty else { throw ProtectionConfigurationError.selectionRequired }
        state.screenTimeLimitMinutes = minutes
    }

    func stopScreenTimeLimit() {
        state.screenTimeLimitMinutes = nil
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
