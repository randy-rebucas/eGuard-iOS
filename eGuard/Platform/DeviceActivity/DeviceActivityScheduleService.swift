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
                for weekday in days.startWeekdays(startingAt: window.start) {
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

    func scheduleScreenTimeLimit(weekdayMinutes: Int, weekendMinutes: Int, selection: ActivitySelectionSnapshot) throws {
        guard let resolved = ActivitySelectionCodec.selection(from: selection), !selection.isEmpty else {
            throw ProtectionConfigurationError.selectionRequired
        }
        let defaults = EGuardShared.sharedDefaults
        // Every sync re-applies the policy. Re-registering restarts the interval, which would lift a limit already
        // reached today, so only register when the limits, the counted apps or the registered schedules changed.
        let signature = "\(weekdayMinutes)|\(weekendMinutes)|\(selection.encodedSelection?.base64EncodedString() ?? "")"
        let names = Self.screenTimeNames(weekdayMinutes: weekdayMinutes, weekendMinutes: weekendMinutes)
        let registered = center.activities
        if defaults?.string(forKey: EGuardShared.DefaultsKey.screenTimeSignature) == signature, names.allSatisfy({ registered.contains($0) }) {
            return
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
        func events(limit: Int) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [EGuardShared.Event.screenTime: event(at: limit)]
            for tick in UsageTicks.steps(limit: limit) {
                events[EGuardShared.Event.usageTick(minutes: tick)] = event(at: tick)
            }
            return events
        }
        defaults?.set(selection.encodedSelection, forKey: EGuardShared.DefaultsKey.screenTimeSelection)
        defaults?.set(weekdayMinutes, forKey: EGuardShared.DefaultsKey.screenTimeMinutes)
        // The parent changed the limit (or the apps that count): it applies now, even after today's old limit was
        // reached. Only a real change gets here, so the child can't use this to reset their allowance.
        defaults?.removeObject(forKey: EGuardShared.DefaultsKey.shieldedOn)
        ManagedSettingsStore(named: EGuardShared.Store.dailyLimits).clearAllSettings()
        center.stopMonitoring(Self.allScreenTimeNames.filter { !names.contains($0) })
        do {
            if weekdayMinutes == weekendMinutes {
                try center.startMonitoring(EGuardShared.Activity.screenTime, during: Self.allDay, events: events(limit: weekdayMinutes))
            } else {
                // Weekdays and weekends differ: a weekly schedule per day with that day's limit, so Saturday's
                // limit starts on Saturday whether or not the app is opened (nothing runs in the background).
                for weekday in 1...7 {
                    let limit = Self.isWeekend(weekday) ? weekendMinutes : weekdayMinutes
                    let schedule = DeviceActivitySchedule(
                        intervalStart: DateComponents(hour: 0, minute: 0, weekday: weekday),
                        intervalEnd: DateComponents(hour: 23, minute: 59, weekday: weekday),
                        repeats: true
                    )
                    try center.startMonitoring(EGuardShared.Activity.screenTime(weekday: weekday), during: schedule, events: events(limit: limit))
                }
            }
            defaults?.set(signature, forKey: EGuardShared.DefaultsKey.screenTimeSignature)
            EGuardLog.configuration.info("Screen time limit registered.")
        } catch {
            defaults?.removeObject(forKey: EGuardShared.DefaultsKey.screenTimeSignature)
            throw ProtectionConfigurationError.platformError(Self.describe(error))
        }
    }

    func stopScreenTimeLimit() {
        center.stopMonitoring(Self.allScreenTimeNames)
        let defaults = EGuardShared.sharedDefaults
        defaults?.removeObject(forKey: EGuardShared.DefaultsKey.screenTimeSelection)
        defaults?.removeObject(forKey: EGuardShared.DefaultsKey.screenTimeMinutes)
        defaults?.removeObject(forKey: EGuardShared.DefaultsKey.screenTimeSignature)
        // A limit reached today stays shielded otherwise: no interval starts again to lift it
        defaults?.removeObject(forKey: EGuardShared.DefaultsKey.shieldedOn)
        ManagedSettingsStore(named: EGuardShared.Store.dailyLimits).clearAllSettings()
    }

    private static func isWeekend(_ weekday: Int) -> Bool { weekday == 1 || weekday == 7 }

    private static var allScreenTimeNames: [DeviceActivityName] {
        [EGuardShared.Activity.screenTime] + (1...7).map { EGuardShared.Activity.screenTime(weekday: $0) }
    }

    private static func screenTimeNames(weekdayMinutes: Int, weekendMinutes: Int) -> [DeviceActivityName] {
        weekdayMinutes == weekendMinutes ? [EGuardShared.Activity.screenTime] : (1...7).map { EGuardShared.Activity.screenTime(weekday: $0) }
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

        func window(_ name: DeviceActivityName) -> DowntimeWindow? {
            guard let schedule = center.schedule(for: name) else { return nil }
            return DowntimeWindow(
                start: TimeOfDay(hour: schedule.intervalStart.hour ?? 0, minute: schedule.intervalStart.minute ?? 0),
                end: TimeOfDay(hour: schedule.intervalEnd.hour ?? 0, minute: schedule.intervalEnd.minute ?? 0)
            )
        }
        if activities.contains(EGuardShared.Activity.downtime) {
            snapshot.isDowntimeScheduled = true
            snapshot.downtimeDays = .everyDay
            snapshot.downtimeWindow = window(EGuardShared.Activity.downtime)
        } else {
            // School nights: one schedule per start weekday. Which weekdays depends on the start (after midnight
            // shifts them a day), so they're checked against the registered window's own start.
            let weekdays = Set((1...7).filter { activities.contains(EGuardShared.Activity.downtime(weekday: $0)) })
            if let first = weekdays.min(), let registered = window(EGuardShared.Activity.downtime(weekday: first)),
               BedtimeDays.registered(startWeekdays: weekdays, startingAt: registered.start) == .schoolNights {
                snapshot.isDowntimeScheduled = true
                snapshot.downtimeDays = .schoolNights
                snapshot.downtimeWindow = registered
            }
        }

        snapshot.isDailyLimitMonitoring = activities.contains(EGuardShared.Activity.dailyLimits)
        if snapshot.isDailyLimitMonitoring {
            let events = center.events(for: EGuardShared.Activity.dailyLimits)
            snapshot.gamingLimitMinutes = events[EGuardShared.Event.gaming].map { Self.minutes(from: $0.threshold) }
            snapshot.socialAppsLimitMinutes = events[EGuardShared.Event.socialApps].map { Self.minutes(from: $0.threshold) }
        }
        func limit(_ name: DeviceActivityName) -> Int? {
            guard activities.contains(name) else { return nil }
            return center.events(for: name)[EGuardShared.Event.screenTime].map { Self.minutes(from: $0.threshold) }
        }
        if let everyDay = limit(EGuardShared.Activity.screenTime) {
            snapshot.screenTimeWeekdayMinutes = everyDay
            snapshot.screenTimeWeekendMinutes = everyDay
        } else {
            // Per-day schedules: report them only when all seven are there (Monday stands for weekdays, Saturday for weekends)
            let days = (1...7).map { limit(EGuardShared.Activity.screenTime(weekday: $0)) }
            if days.allSatisfy({ $0 != nil }) {
                snapshot.screenTimeWeekdayMinutes = days[1]
                snapshot.screenTimeWeekendMinutes = days[6]
            }
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

    func scheduleScreenTimeLimit(weekdayMinutes: Int, weekendMinutes: Int, selection: ActivitySelectionSnapshot) throws {
        if let errorToThrow { throw errorToThrow }
        guard !selection.isEmpty else { throw ProtectionConfigurationError.selectionRequired }
        state.screenTimeWeekdayMinutes = weekdayMinutes
        state.screenTimeWeekendMinutes = weekendMinutes
    }

    func stopScreenTimeLimit() {
        state.screenTimeWeekdayMinutes = nil
        state.screenTimeWeekendMinutes = nil
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
