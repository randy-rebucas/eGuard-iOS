import Foundation
import Testing
@testable import eGuard

/// The child device side against the shared mock server: pairing, sync, apply, report, removal.
@Suite("Child device mode")
struct ChildDeviceTests {
    private func pairedModel() async throws -> (AppModel, MockEGuardAPI, String) {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api, signedIn: true, authorizationStatus: .approved)
        let lucas = try #require(try await api.children().first { $0.name == "Lucas" })
        let code = try await api.pairingCode(childId: lucas.id)
        _ = try await model.childDevice.pair(code: code.code, deviceName: "Lucas's iPad")
        await model.enterChildMode()
        return (model, api, lucas.id)
    }

    @Test func pairingSwitchesTheInstallToChildModeAndEndsTheParentSession() async throws {
        let (model, api, childId) = try await pairedModel()
        #expect(model.mode == .child)
        #expect(!model.isSignedIn)
        #expect(model.childDevice.isPaired)
        #expect(model.childDevice.session?.childName == "Lucas")
        // The parent side sees the new device and the "New device synchronized" alert.
        api.loginForTests()
        #expect(try await api.child(id: childId).devices.contains { $0.name == "Lucas's iPad" })
        #expect(try await api.alerts(filter: .devices, childId: childId, includeResolved: false, before: nil).alerts.first?.title == "New device synchronized")
    }

    @Test func badCodesKeepTheParentSignedIn() async throws {
        let api = MockEGuardAPI.seeded()
        let model = AppModel.mock(api: api, signedIn: true)
        await #expect(throws: DeviceAPIError.self) {
            _ = try await model.childDevice.pair(code: "NOPE-0000", deviceName: "Phone")
        }
        #expect(model.isSignedIn)
        #expect(model.mode == .parent)
        #expect(!model.childDevice.isPaired)
        #expect(ChildSetupView.pairingMessage(for: .server(status: 409, message: "Device limit reached for this plan")).contains("No free device slots"))
    }

    @Test func syncAppliesThePolicyAndReportsVerifyTheParentsChange() async throws {
        let (model, api, childId) = try await pairedModel()
        let device = model.childDevice
        device.setScreenTimeSelection(ActivitySelectionSnapshot(encodedSelection: Data([0x01]), applicationCount: 4))
        await device.syncNow()
        guard case .synced = device.syncState else { Issue.record("Expected a successful sync, got \(device.syncState)"); return }
        #expect(device.state.policy.count == 10)
        #expect(device.state.timezone == "Asia/Manila")

        // The first full report verifies every protection iOS supports.
        api.loginForTests()
        let protections = try await api.protections(childId: childId)
        let bedtime = try #require(protections.first { $0.key == "BEDTIME" })
        #expect(bedtime.devices.first { $0.deviceName == "Lucas's iPad" }?.status == .pass)
        #expect(protections.first { $0.key == "NOTIFICATIONS" }?.devices.first { $0.deviceName == "Lucas's iPad" }?.status == .unsupported)

        // A parent changes bedtime; the device picks it up on its next sync and reports it back.
        let batch = try #require(try await api.updateProtection(childId: childId, key: "BEDTIME", config: .object(["enabled": .bool(true), "start": .string("21:00"), "end": .string("06:30"), "days": .string("SCHOOL_NIGHTS")])).batch)
        await device.syncNow()
        let updated = try await api.batch(id: batch.batchId)
        let request = try #require(updated.items.first?.devices.first { $0.deviceName == "Lucas's iPad" })
        #expect(request.status == .verified)
        #expect(device.protectionStatuses().first { $0.key == "BEDTIME" }?.isMatching == true)
        #expect((model.schedules as? MockActivityScheduleService)?.snapshot().downtimeDays == .schoolNights)
    }

    @Test func aProtectionThatCantBeAppliedIsKeptWithItsReasonNotSwallowed() async throws {
        let (model, _, _) = try await pairedModel()
        let device = model.childDevice
        // No apps chosen for screen time yet: the limit can't be registered
        await device.syncNow()
        #expect(device.applyProblems["SCREEN_TIME"] == ProtectionConfigurationError.selectionRequired.localizedDescription)
        // The "Choose the apps" card explains this one, so the general card doesn't repeat it
        #expect(!device.applyProblemsToShow.contains { $0.name == ProtectionKey.name("SCREEN_TIME") })

        device.setScreenTimeSelection(ActivitySelectionSnapshot(encodedSelection: Data([0x01]), applicationCount: 4))
        #expect(device.applyProblems["SCREEN_TIME"] == nil)
    }

    @Test func locationIsSentOnlyWhenEveryConditionHolds() async throws {
        let (model, api, childId) = try await pairedModel()
        let reporter = try #require(model.childDevice.locationReporter as? MockLocationReporter)
        let deviceAPI = try #require(model.childDevice.api as? MockDeviceAPI)
        await model.childDevice.syncNow()
        #expect(deviceAPI.fixes.isEmpty)

        await reporter.requestPermission()
        await model.childDevice.syncNow()
        #expect(deviceAPI.fixes.count == 1)

        api.loginForTests()
        _ = try await api.updateProtection(childId: childId, key: "LOCATION", config: .object(["sharing": .bool(false)]))
        await model.childDevice.syncNow()
        #expect(deviceAPI.fixes.count == 1)
    }

    @Test func appRequestsReachTheParentAndQueueWhileOffline() async throws {
        let (model, api, childId) = try await pairedModel()
        let deviceAPI = try #require(model.childDevice.api as? MockDeviceAPI)
        #expect(try await model.childDevice.requestApp(named: "Minecraft") == nil)
        api.loginForTests()
        #expect(try await api.apps(childId: childId, filter: .pending).apps.contains { $0.name == "Minecraft" })
        #expect(try await model.childDevice.requestApp(named: "Roblox") == .allowed)

        deviceAPI.nextError = .network("offline")
        await #expect(throws: DeviceAPIError.self) { _ = try await model.childDevice.requestApp(named: "Among Us") }
        #expect(model.childDevice.state.pendingEvents.count == 1)
        await model.childDevice.syncNow()
        #expect(model.childDevice.state.pendingEvents.isEmpty)
        #expect(try await api.apps(childId: childId, filter: .pending).apps.contains { $0.name == "Among Us" })
    }

    @Test func usageFromTheTickLadderReachesTheParentOnceADayPerTotal() async throws {
        let (model, api, childId) = try await pairedModel()
        let source = try #require(model.childDevice.usageSource as? MockUsageSource)
        let today = UsageTicks.localDate()
        source.usage = UsageRequest(date: today, totalMinutes: 45, apps: nil, hourly: nil)
        await model.childDevice.syncNow()
        api.loginForTests()
        #expect(try await api.children().first { $0.id == childId }?.todayMinutes == 45)
        #expect(model.childDevice.state.lastUsageSent?.totalMinutes == 45)

        // The same total isn't resent; a higher rung is.
        source.usage = UsageRequest(date: today, totalMinutes: 60, apps: nil, hourly: nil)
        await model.childDevice.syncNow()
        #expect(try await api.children().first { $0.id == childId }?.todayMinutes == 60)

        // A stale day is never sent.
        source.usage = UsageRequest(date: "2020-01-01", totalMinutes: 500, apps: nil, hourly: nil)
        await model.childDevice.syncNow()
        #expect(try await api.children().first { $0.id == childId }?.todayMinutes == 60)
    }

    @Test func usageLadderStaysSmallAndBelowTheLimit() {
        #expect(UsageTicks.steps(limit: 10).isEmpty)
        #expect(UsageTicks.steps(limit: 60) == [15, 30, 45])
        #expect(UsageTicks.steps(limit: 180).count == 11)
        let long = UsageTicks.steps(limit: 1440)
        #expect(long.count <= UsageTicks.maximumTicks)
        #expect(long.allSatisfy { $0 < 1440 && $0 % 15 == 0 })
        #expect(UsageTicks.localDate(Date(timeIntervalSince1970: 0), calendar: {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()) == "1970-01-01")
    }

    @Test func aMoveByAParentReachesTheChildsHomeScreen() async throws {
        let (model, api, lucasId) = try await pairedModel()
        await model.childDevice.syncNow()
        api.loginForTests()
        let other = try #require(try await api.children().first { $0.id != lucasId })
        let device = try #require(try await api.devices().devices.first { $0.name == "Lucas's iPad" })

        let moved = try await api.moveDevice(id: device.id, childId: other.id, confirmation: .password("ChangeMe123!"))
        #expect(moved.childId == other.id)
        #expect(moved.device.statusTitle == "Waiting for first check")
        await #expect(throws: APIError.self) {
            try await api.moveDevice(id: device.id, childId: other.id, confirmation: .password("ChangeMe123!"))
        }

        await model.childDevice.syncNow()
        #expect(model.childDevice.session?.childName == other.name)
    }

    @Test func removalByAParentWipesTheDevice() async throws {
        let (model, api, _) = try await pairedModel()
        await model.childDevice.syncNow()
        api.loginForTests()
        let device = try #require(try await api.devices().devices.first { $0.name == "Lucas's iPad" })
        try await api.unpairDevice(id: device.id, confirmation: .password("ChangeMe123!"), deleteHistory: false)

        await model.childDevice.syncNow()
        #expect(model.childDevice.wasRemoved)
        #expect(!model.childDevice.isPaired)
        #expect(model.childDevice.state.policy.isEmpty)
        #expect(model.restrictions.snapshot() == .empty)
        #expect(model.schedules.snapshot() == .empty)

        model.leaveChildMode()
        #expect(model.mode == .unset)
        #expect(!model.childDevice.wasRemoved)
    }

    @Test func androidRatingsAreSetByTheParentAndNeverVerified() async throws {
        let api = MockEGuardAPI.seeded()
        let lucas = try #require(try await api.children().first { $0.name == "Lucas" })
        // Seeded as confirmed on Lucas's Galaxy (Android): "Set by you", not "Not supported", not counted in health
        let content = try #require(try await api.protections(childId: lucas.id).first { $0.key == "CONTENT" })
        let galaxy = try #require(content.devices.first)
        #expect(galaxy.capability == .parentSet)
        #expect(galaxy.status == .unsupported)
        #expect(galaxy.statusTitle == "Set by you")
        #expect(content.displayStatus == .setByYou)
        #expect(try await api.health(childId: lucas.id).checks.first { $0.key == "CONTENT" }?.isParentSet == true)
        // iOS applies WEB and DOWNLOADS itself
        #expect(MockEGuardAPI.capability(key: "WEB", platform: .ios) == .available)
        #expect(MockEGuardAPI.capability(key: "DOWNLOADS", platform: .ios) == .available)

        // A change waits for the parent's steps in Google Play, then is saved as theirs, not verified
        let batch = try #require(try await api.updateProtection(childId: lucas.id, key: "CONTENT", config: .object(["maxAgeRating": .number(13)])).batch)
        let step = try #require(batch.items.first?.devices.first)
        #expect(step.isGuided && step.isParentSet && step.status == .awaitingParent)
        #expect(step.guide?.isEmpty == false)
        let confirmed = try await api.confirmBatch(id: batch.batchId, key: "CONTENT")
        #expect(confirmed.done)
        #expect(confirmed.items.first?.statusTitle == "Set by you, not verified")
        let after = try #require(try await api.protections(childId: lucas.id).first { $0.key == "CONTENT" })
        #expect(after.devices.first?.reportedLabel == "Set by you: Rated 13+ and under")
        #expect(after.openBatchId == nil)
    }

    @Test func launchRoutingRepairsInconsistentState() {
        let model = AppModel.mock(mode: .child)
        model.reconcileModeAtLaunch()
        #expect(model.mode == .unset)
    }
}

@Suite("Enforcer mapping")
struct EnforcerMappingTests {
    private func makeEnforcer() -> (ScreenTimeEnforcer, MockRestrictionService, MockActivityScheduleService) {
        let restrictions = MockRestrictionService()
        let schedules = MockActivityScheduleService()
        let enforcer = ScreenTimeEnforcer(
            restrictions: restrictions, schedules: schedules,
            authorization: MockAuthorizationService(status: .approved), environment: .iPhone, locationStatus: MockLocationReporter()
        )
        return (enforcer, restrictions, schedules)
    }

    private var context: EnforcementContext {
        EnforcementContext(screenTimeSelection: ActivitySelectionSnapshot(encodedSelection: Data([0x01]), applicationCount: 2), timeZone: TimeZone(identifier: "Asia/Manila")!, now: Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func capabilitiesMatchTheSpecTable() {
        let (enforcer, _, _) = makeEnforcer()
        // WEB (Screen Time's adult-website filter) and DOWNLOADS (installs need a parent) are applied directly
        #expect(enforcer.capability(for: "WEB") == .available)
        #expect(enforcer.capability(for: "LOCATION") == .guided)
        #expect(enforcer.capability(for: "DOWNLOADS") == .available)
        #expect(enforcer.capability(for: "NOTIFICATIONS") == .unsupported)
        #expect(enforcer.capability(for: "BEDTIME") == .available)
        #expect(!enforcer.supportedKeys.contains("NOTIFICATIONS"))
    }

    @Test func reportsReturnExactlyTheFieldsTheServerExpects() throws {
        let (enforcer, _, _) = makeEnforcer()
        let configs: [String: JSONValue] = [
            "BEDTIME": .object(["enabled": .bool(true), "start": .string("21:30"), "end": .string("06:00"), "days": .string("EVERY_DAY")]),
            "APP_RESTRICTIONS": .object(["maxAgeRating": .number(13)]),
            "CONTENT": .object(["maxAgeRating": .number(16)]),
            "APP_APPROVAL": .object(["enabled": .bool(true)]),
            "WEB": .object(["mode": .string("FILTER"), "blockedSites": .number(0)]),
            "DOWNLOADS": .object(["requireApproval": .bool(true)]),
            "UNINSTALL_PROTECTION": .object(["enabled": .bool(true)]),
            "SCREEN_TIME": .object(["dailyMinutes": .number(180), "weekendMinutes": .number(240)]),
        ]
        for (key, config) in configs {
            try enforcer.apply(PolicyEntry(key: key, config: config), context: context)
            let reported = enforcer.readBack(key: key, policy: config, context: context)
            #expect(reported == config, "\(key) should read back as applied")
        }
        // Before anything is applied the device reports its real, unset state.
        let fresh = makeEnforcer().0
        #expect(fresh.readBack(key: "BEDTIME", policy: configs["BEDTIME"], context: context)?["enabled"]?.boolValue == false)
        #expect(fresh.readBack(key: "APP_RESTRICTIONS", policy: nil, context: context)?["maxAgeRating"]?.intValue == 21)
        #expect(fresh.readBack(key: "SCREEN_TIME", policy: nil, context: context)?["dailyMinutes"]?.intValue == 0)
        #expect(fresh.readBack(key: "NOTIFICATIONS", policy: nil, context: context) == nil)
    }

    @Test func webReportsNoBlockedSitesOfItsOwnAndMatchesByMode() throws {
        let (enforcer, _, _) = makeEnforcer()
        let policy = JSONValue.object(["mode": .string("FILTER"), "blockedSites": .number(42)])
        try enforcer.apply(PolicyEntry(key: "WEB", config: policy), context: context)
        let reported = try #require(enforcer.readBack(key: "WEB", policy: policy, context: context))
        // Apple's filter has no site list: the policy's count isn't copied back
        #expect(reported == .object(["mode": .string("FILTER"), "blockedSites": .number(0)]))
        // The server compares WEB by mode only
        #expect(ProtectionKey.reportMatches(key: "WEB", reported: reported, policy: policy))
        #expect(!ProtectionKey.reportMatches(key: "WEB", reported: reported, policy: .object(["mode": .string("OFF"), "blockedSites": .number(0)])))
        #expect(!ProtectionKey.reportMatches(key: "DOWNLOADS", reported: .object(["requireApproval": .bool(false)]), policy: .object(["requireApproval": .bool(true)])))
    }

    @Test func appApprovalAndDownloadsShareTheInstallSwitchButReadBackApart() throws {
        let (enforcer, restrictions, _) = makeEnforcer()
        let on = JSONValue.object(["enabled": .bool(true)]), off = JSONValue.object(["enabled": .bool(false)])
        let approve = JSONValue.object(["requireApproval": .bool(true)]), free = JSONValue.object(["requireApproval": .bool(false)])
        /// [APP_APPROVAL enabled, DOWNLOADS requireApproval] as read back
        func reading() -> [Bool?] {
            [enforcer.readBack(key: "APP_APPROVAL", policy: nil, context: context)?["enabled"]?.boolValue,
             enforcer.readBack(key: "DOWNLOADS", policy: nil, context: context)?["requireApproval"]?.boolValue]
        }

        // DOWNLOADS alone denies installs, but App Approval doesn't claim to be on
        try enforcer.apply(PolicyEntry(key: "APP_APPROVAL", config: off), context: context)
        try enforcer.apply(PolicyEntry(key: "DOWNLOADS", config: approve), context: context)
        #expect(restrictions.snapshot().denyAppInstallation == true)
        #expect(restrictions.snapshot().requirePasswordForPurchases == true)
        #expect(reading() == [false, true])

        // Turning App Approval on and off again doesn't lift what DOWNLOADS needs
        try enforcer.apply(PolicyEntry(key: "APP_APPROVAL", config: on), context: context)
        #expect(reading() == [true, true])
        try enforcer.apply(PolicyEntry(key: "APP_APPROVAL", config: off), context: context)
        #expect(restrictions.snapshot().denyAppInstallation == true)
        #expect(reading() == [false, true])

        // A newer request for DOWNLOADS overrides the policy applied before it in the same sync
        try enforcer.apply(PolicyEntry(key: "APP_APPROVAL", config: on), context: context)
        try enforcer.apply(PolicyEntry(key: "DOWNLOADS", config: free), context: context)
        #expect(restrictions.snapshot().denyAppInstallation == true)
        #expect(reading() == [true, false])

        // Neither wants it: installs are allowed again
        try enforcer.apply(PolicyEntry(key: "APP_APPROVAL", config: off), context: context)
        #expect(restrictions.snapshot().denyAppInstallation == nil)
        #expect(reading() == [false, false])

        // The switch on without eGuard's record of why (e.g. set by an older build) isn't claimed by either
        let unexplained = MockRestrictionService(state: RestrictionSnapshot(denyAppInstallation: true))
        let other = ScreenTimeEnforcer(restrictions: unexplained, schedules: MockActivityScheduleService(), authorization: MockAuthorizationService(status: .approved), environment: .iPhone, locationStatus: MockLocationReporter())
        #expect(other.readBack(key: "APP_APPROVAL", policy: nil, context: context)?["enabled"]?.boolValue == false)
        #expect(other.readBack(key: "DOWNLOADS", policy: nil, context: context)?["requireApproval"]?.boolValue == false)
    }

    @Test func contentReadsBackTheMostEitherMoviesOrTVLetThrough() {
        // TV loosened to 16 while movies stay at 9: the device lets 16 through, so it reports 16 (not matching 9)
        let state = RestrictionSnapshot(
            movieRating: RatingTiers.rating(forAge: 9, in: RatingTiers.movies),
            tvRating: RatingTiers.rating(forAge: 16, in: RatingTiers.tv)
        )
        let enforcer = ScreenTimeEnforcer(restrictions: MockRestrictionService(state: state), schedules: MockActivityScheduleService(), authorization: MockAuthorizationService(status: .approved), environment: .iPhone, locationStatus: MockLocationReporter())
        let policy = JSONValue.object(["maxAgeRating": .number(9)])
        #expect(enforcer.readBack(key: "CONTENT", policy: policy, context: context)?["maxAgeRating"]?.intValue == 16)
        // Only movies capped: TV has no cap (21), so nothing is limited for TV and it can't match
        let moviesOnly = ScreenTimeEnforcer(restrictions: MockRestrictionService(state: RestrictionSnapshot(movieRating: 400)), schedules: MockActivityScheduleService(), authorization: MockAuthorizationService(status: .approved), environment: .iPhone, locationStatus: MockLocationReporter())
        #expect(moviesOnly.readBack(key: "CONTENT", policy: JSONValue.object(["maxAgeRating": .number(16)]), context: context)?["maxAgeRating"]?.intValue == 21)
    }

    @Test func locationSharingReadsBackOnlyWhenThePlanIncludesIt() async {
        let reporter = MockLocationReporter()
        await reporter.requestPermission()
        let enforcer = ScreenTimeEnforcer(restrictions: MockRestrictionService(), schedules: MockActivityScheduleService(), authorization: MockAuthorizationService(status: .approved), environment: .iPhone, locationStatus: reporter)
        let policy = JSONValue.object(["sharing": .bool(true)])
        #expect(enforcer.readBack(key: "LOCATION", policy: policy, context: context)?["sharing"]?.boolValue == true)
        var noPlan = context
        noPlan.locationSharingAllowed = false
        #expect(enforcer.readBack(key: "LOCATION", policy: policy, context: noPlan)?["sharing"]?.boolValue == false)
    }

    @Test func schoolNightWindowsAfterMidnightBelongToTheEveningBefore() throws {
        // As the server's bedtimeActive: a window starting before 12:00 is the previous night's
        let evening = TimeOfDay(hour: 21, minute: 30), afterMidnight = TimeOfDay(hour: 0, minute: 30)
        #expect(BedtimeDays.schoolNights.startWeekdays(startingAt: evening) == [1, 2, 3, 4, 5])
        // Sunday to Thursday nights after midnight are Monday to Friday mornings
        #expect(BedtimeDays.schoolNights.startWeekdays(startingAt: afterMidnight) == [2, 3, 4, 5, 6])
        #expect(BedtimeDays.schoolNights.startWeekdays(startingAt: TimeOfDay(hour: 11, minute: 59)) == [2, 3, 4, 5, 6])
        #expect(BedtimeDays.schoolNights.startWeekdays(startingAt: TimeOfDay(hour: 12, minute: 0)) == [1, 2, 3, 4, 5])
        #expect(BedtimeDays.everyDay.startWeekdays(startingAt: afterMidnight) == [1, 2, 3, 4, 5, 6, 7])

        // Registered schedules read back as school nights only when they match the rule for their own start
        #expect(BedtimeDays.registered(startWeekdays: [2, 3, 4, 5, 6], startingAt: afterMidnight) == .schoolNights)
        #expect(BedtimeDays.registered(startWeekdays: [1, 2, 3, 4, 5], startingAt: afterMidnight) == nil)
        #expect(BedtimeDays.registered(startWeekdays: [1, 2, 3, 4, 5], startingAt: evening) == .schoolNights)
        #expect(BedtimeDays.registered(startWeekdays: [], startingAt: evening) == nil)

        // The enforcer reports the days it applied
        let (enforcer, _, schedules) = makeEnforcer()
        let config = JSONValue.object(["enabled": .bool(true), "start": .string("00:30"), "end": .string("06:00"), "days": .string("SCHOOL_NIGHTS")])
        try enforcer.apply(PolicyEntry(key: "BEDTIME", config: config), context: context)
        #expect(schedules.snapshot().downtimeDays == .schoolNights)
        #expect(enforcer.readBack(key: "BEDTIME", policy: config, context: context) == config)
    }

    @Test func screenTimeNeedsAppsAndRegistersBothLimits() throws {
        let (enforcer, _, schedules) = makeEnforcer()
        let config = JSONValue.object(["dailyMinutes": .number(120), "weekendMinutes": .number(200)])
        var noApps = context
        noApps.screenTimeSelection = .empty
        #expect(throws: ProtectionConfigurationError.self) {
            try enforcer.apply(PolicyEntry(key: "SCREEN_TIME", config: config), context: noApps)
        }
        // Both limits are registered, so Saturday's applies on Saturday without the app being opened
        try enforcer.apply(PolicyEntry(key: "SCREEN_TIME", config: config), context: context)
        #expect(schedules.snapshot().screenTimeWeekdayMinutes == 120)
        #expect(schedules.snapshot().screenTimeWeekendMinutes == 200)
        #expect(enforcer.readBack(key: "SCREEN_TIME", policy: config, context: context) == config)
        // No limit on weekends: the whole day there, reported back as 0
        let weekdaysOnly = JSONValue.object(["dailyMinutes": .number(90), "weekendMinutes": .number(0)])
        try enforcer.apply(PolicyEntry(key: "SCREEN_TIME", config: weekdaysOnly), context: context)
        #expect(schedules.snapshot().screenTimeWeekendMinutes == ScreenTimeEnforcer.wholeDay)
        #expect(enforcer.readBack(key: "SCREEN_TIME", policy: weekdaysOnly, context: context) == weekdaysOnly)
    }

    @Test func ratingTiersReadBackTheAgeAskedFor() throws {
        // The web offers 12 and 17 too; Apple has no tier of its own for them
        for age in [4, 9, 12, 13, 16, 17, 18] {
            let (enforcer, _, _) = makeEnforcer()
            let config = JSONValue.object(["maxAgeRating": .number(Double(age))])
            for key in ["APP_RESTRICTIONS", "CONTENT"] {
                try enforcer.apply(PolicyEntry(key: key, config: config), context: context)
                #expect(enforcer.readBack(key: key, policy: config, context: context) == config, "\(key) \(age)")
            }
        }
        // 12 is Apple's 12+, not 9+
        #expect(RatingTiers.rating(forAge: 12, in: RatingTiers.appStore) == 300)
        #expect(RatingTiers.rating(forAge: 17, in: RatingTiers.appStore) == 600)
    }

    @Test func revokedScreenTimeAccessReportsEverythingOff() async throws {
        let restrictions = MockRestrictionService()
        let authorization = MockAuthorizationService(status: .approved)
        let enforcer = ScreenTimeEnforcer(restrictions: restrictions, schedules: MockActivityScheduleService(), authorization: authorization, environment: .iPhone, locationStatus: MockLocationReporter())
        try enforcer.apply(PolicyEntry(key: "UNINSTALL_PROTECTION", config: .object(["enabled": .bool(true)])), context: context)
        try await authorization.revokeAuthorization()
        // The store still holds the old value, but nothing is enforced any more
        #expect(enforcer.readBack(key: "UNINSTALL_PROTECTION", policy: nil, context: context)?["enabled"]?.boolValue == false)
        #expect(enforcer.readBack(key: "APP_RESTRICTIONS", policy: nil, context: context)?["maxAgeRating"]?.intValue == 21)
    }

    @Test func clockIsLockedWhileBedtimeOrALimitIsOn() {
        let (enforcer, restrictions, _) = makeEnforcer()
        enforcer.updateClockLock(policy: [PolicyEntry(key: "BEDTIME", config: .object(["enabled": .bool(true)]))])
        #expect(restrictions.snapshot().requiresAutomaticDateAndTime == true)
        enforcer.updateClockLock(policy: [PolicyEntry(key: "SCREEN_TIME", config: .object(["dailyMinutes": .number(0), "weekendMinutes": .number(60)]))])
        #expect(restrictions.snapshot().requiresAutomaticDateAndTime == true)
        enforcer.updateClockLock(policy: [PolicyEntry(key: "BEDTIME", config: .object(["enabled": .bool(false)]))])
        #expect(restrictions.snapshot().requiresAutomaticDateAndTime == nil)
    }

    @Test func unauthorizedDevicesNeverClaimToApply() {
        let restrictions = MockRestrictionService()
        let enforcer = ScreenTimeEnforcer(restrictions: restrictions, schedules: MockActivityScheduleService(), authorization: MockAuthorizationService(status: .denied), environment: .iPhone, locationStatus: MockLocationReporter())
        #expect(throws: ProtectionConfigurationError.self) {
            try enforcer.apply(PolicyEntry(key: "CONTENT", config: .object(["maxAgeRating": .number(13)])), context: context)
        }
        #expect(restrictions.snapshot() == .empty)
    }
}
