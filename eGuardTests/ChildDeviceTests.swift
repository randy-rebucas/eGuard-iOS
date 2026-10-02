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
        let batch = try await api.updateProtection(childId: childId, key: "BEDTIME", config: .object(["enabled": .bool(true), "start": .string("21:00"), "end": .string("06:30"), "days": .string("SCHOOL_NIGHTS")]))
        await device.syncNow()
        let updated = try await api.batch(id: batch.batchId)
        let request = try #require(updated.items.first?.devices.first { $0.deviceName == "Lucas's iPad" })
        #expect(request.status == .verified)
        #expect(device.protectionStatuses().first { $0.key == "BEDTIME" }?.isMatching == true)
        #expect((model.schedules as? MockActivityScheduleService)?.snapshot().downtimeDays == .schoolNights)
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

    @Test func removalByAParentWipesTheDevice() async throws {
        let (model, api, _) = try await pairedModel()
        await model.childDevice.syncNow()
        api.loginForTests()
        let device = try #require(try await api.devices().devices.first { $0.name == "Lucas's iPad" })
        try await api.unpairDevice(id: device.id, confirmation: .password("ChangeMe123!"))

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
        #expect(enforcer.capability(for: "WEB") == .guided)
        #expect(enforcer.capability(for: "LOCATION") == .guided)
        #expect(enforcer.capability(for: "DOWNLOADS") == .verifyOnly)
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
            "WEB": .object(["mode": .string("FILTER"), "blockedSites": .number(42)]),
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

    @Test func screenTimeNeedsAppsAndUsesTodaysLimit() {
        let (enforcer, _, schedules) = makeEnforcer()
        let config = JSONValue.object(["dailyMinutes": .number(120), "weekendMinutes": .number(200)])
        var noApps = context
        noApps.screenTimeSelection = .empty
        #expect(throws: ProtectionConfigurationError.self) {
            try enforcer.apply(PolicyEntry(key: "SCREEN_TIME", config: config), context: noApps)
        }
        try? enforcer.apply(PolicyEntry(key: "SCREEN_TIME", config: config), context: context)
        let expected = ScreenTimeEnforcer.todayLimit(config, context: context)
        #expect(schedules.snapshot().screenTimeLimitMinutes == expected)
        #expect([120, 200].contains(expected))
    }

    @Test func ratingTiersRoundTrip() {
        for age in [4, 9, 13, 16, 18] {
            #expect(RatingTiers.age(forRating: RatingTiers.rating(forAge: age, in: RatingTiers.appStore), in: RatingTiers.appStore) == age)
            #expect(RatingTiers.age(forRating: RatingTiers.rating(forAge: age, in: RatingTiers.movies), in: RatingTiers.movies) == age)
        }
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
