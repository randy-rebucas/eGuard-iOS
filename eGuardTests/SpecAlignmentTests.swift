import Foundation
import Testing
@testable import eGuard

/// The parts of the mobile API v1 spec added on 2026-10-10: protection versions, saving without a
/// device, category limits, saved places, device moves, family renames and first checks.
@Suite("Spec alignment: versions, places, categories, devices")
struct SpecAlignmentTests {
    private func mia(_ api: MockEGuardAPI) async throws -> ChildSummary {
        try #require(try await api.children().first { $0.name == "Mia" })
    }

    /// Lucas's seeded device shares its location; Mia's has sharing turned off.
    private func lucas(_ api: MockEGuardAPI) async throws -> ChildSummary {
        try #require(try await api.children().first { $0.name == "Lucas" })
    }

    // MARK: Protections

    @Test func aStaleBaseVersionIsRefusedAndTheCurrentOneAccepted() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await mia(api)
        let bedtime = try #require(try await api.protections(childId: child.id).first { $0.key == "BEDTIME" })
        let version = try #require(bedtime.version)
        let config: JSONValue = .object(["enabled": .bool(true), "start": .string("21:00"), "end": .string("06:30"), "days": .string("EVERY_DAY")])

        await #expect(throws: APIError.self) {
            _ = try await api.updateProtection(childId: child.id, key: "BEDTIME", config: config, baseVersion: "someone-elses-version")
        }
        let result = try await api.updateProtection(childId: child.id, key: "BEDTIME", config: config, baseVersion: version)
        #expect(result.batch != nil)
        // The save is a new version, so the old one is stale from now on.
        let after = try #require(try await api.protections(childId: child.id).first { $0.key == "BEDTIME" })
        #expect(after.version != version)
    }

    @Test func staleErrorsCarryTheSpecsCode() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await mia(api)
        do {
            _ = try await api.updateProtection(childId: child.id, key: "WEB", config: .object(["mode": .string("FILTER")]), baseVersion: "old")
            Issue.record("Expected a stale error")
        } catch let error as APIError {
            #expect(error.status == 409)
            #expect(error.code == "stale")
        }
    }

    @Test func aChildWithoutDevicesGetsSavedNotVerified() async throws {
        let api = MockEGuardAPI.empty()
        api.loginForTests()
        let child = try await api.createChild(name: "Noah", age: 8, profile: nil)
        let result = try await api.updateProtection(childId: child.id, key: "BEDTIME", config: .object(["enabled": .bool(true), "start": .string("20:00"), "end": .string("06:00"), "days": .string("EVERY_DAY")]))
        #expect(result.savedKeys == ["BEDTIME"])
        #expect(result.batch == nil)
        // The setting is the child's policy now, applied when a device pairs.
        let bedtime = try #require(try await api.protections(childId: child.id).first { $0.key == "BEDTIME" })
        #expect(bedtime.policy["start"]?.stringValue == "20:00")
    }

    @Test func savedWithoutDeviceDecodesFromTheWireShape() throws {
        let data = Data(#"{ "batchId": null, "saved": ["BEDTIME"] }"#.utf8)
        let result = try JSONDecoder().decode(ProtectionUpdateResult.self, from: data)
        #expect(result == .saved(["BEDTIME"]))
    }

    // MARK: Category limits

    @Test func categoryLimitsFollowThePlan() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await mia(api)
        let limits = try await api.categoryLimits(childId: child.id)
        #expect(limits.available)
        #expect(limits.categories.first { $0.category == "GAMES" }?.dailyLimitMinutes == 60)
        #expect(limits.categories.count == AppCategory.allCases.count)

        _ = try await api.setCategoryLimit(childId: child.id, category: "VIDEO", dailyLimitMinutes: 90)
        #expect(try await api.categoryLimits(childId: child.id).categories.first { $0.category == "VIDEO" }?.dailyLimitMinutes == 90)

        // Free keeps the limits but can only remove them.
        api.entitlements.childLimit = 1
        let free = try await api.categoryLimits(childId: child.id)
        #expect(!free.available)
        #expect(free.upgrade != nil)
        await #expect(throws: APIError.self) {
            _ = try await api.setCategoryLimit(childId: child.id, category: "SOCIAL", dailyLimitMinutes: 30)
        }
        _ = try await api.setCategoryLimit(childId: child.id, category: "VIDEO", dailyLimitMinutes: nil)
        #expect(try await api.categoryLimits(childId: child.id).categories.first { $0.category == "VIDEO" }?.dailyLimitMinutes == nil)
    }

    @Test func setupRefusesCategoryLimitsOnFreeBeforeChangingAnything() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await mia(api)
        api.entitlements.childLimit = 1
        do {
            _ = try await api.setup(childId: child.id, profile: "PROTECTED", overrides: [], categoryLimits: [CategoryLimitUpdate(category: "GAMES", dailyLimitMinutes: 45)])
            Issue.record("Expected plan_required")
        } catch let error as APIError {
            #expect(error.code == "plan_required")
        }
        // Without limits the same setup goes through.
        let response = try await api.setup(childId: child.id, profile: "PROTECTED", overrides: [], categoryLimits: nil)
        #expect(response.batchId != nil)
    }

    @Test func recommendationsIncludeGamingTime() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await mia(api)
        let protected = try await api.recommendations(childId: child.id, profile: "PROTECTED")
        #expect(protected.categoryLimits?.first?.dailyLimitMinutes == 60)
        let balanced = try await api.recommendations(childId: child.id, profile: "BALANCED")
        #expect(balanced.categoryLimits?.first?.dailyLimitMinutes == 90)
    }

    @Test func appCategoriesCanBeChosenAndResetToTheGuess() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await mia(api)
        let roblox = try #require(try await api.apps(childId: child.id, filter: nil).apps.first { $0.name == "Roblox" })
        #expect(roblox.category == "GAMES")
        #expect(roblox.categoryAuto == true)
        let changed = try await api.updateApp(id: roblox.id, patch: AppPatch(category: "EDUCATION"))
        #expect(changed.category == "EDUCATION")
        #expect(changed.categoryAuto == false)
        let reset = try await api.updateApp(id: roblox.id, patch: AppPatch(resetCategory: true))
        #expect(reset.category == "GAMES")
        #expect(reset.categoryAuto == true)
    }

    @Test func categoryPatchEncodesNullToReset() throws {
        let data = try JSONEncoder().encode(AppPatch(resetCategory: true))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["category"] is NSNull)
    }

    // MARK: Saved places

    @Test func placesAreManagedAndNameVisits() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await lucas(api)
        #expect(try await api.places().count == 2)
        let location = try await api.location(childId: child.id)
        #expect(location.current?.placeId == "place_home")
        #expect(location.history.visits.contains { $0.placeId == "place_school" })
        #expect(location.history.visits.contains { $0.isPassingBy })
        #expect(location.history.visits.contains { $0.placeLabel == nil && $0.canBeNamed })
        #expect(try await api.familyLocations().savedPlaces.count == 2)

        let park = try await api.createPlace(NewPlace(name: "Park", lat: 10.6740, lng: 124.8050, radiusM: nil, notifyArrive: true, notifyLeave: nil))
        #expect(park.radiusM == SavedPlace.defaultRadius)
        #expect(park.arrives)
        let renamed = try await api.updatePlace(id: park.id, patch: PlacePatch(name: "City Park", radiusM: 250))
        #expect(renamed.name == "City Park")
        #expect(renamed.radiusM == 250)
        try await api.deletePlace(id: park.id)
        #expect(try await api.places().count == 2)
    }

    @Test func placesAreReadOnlyOnFree() async throws {
        let api = MockEGuardAPI.seeded()
        api.entitlements.childLimit = 1
        let places = try await api.places()
        #expect(places.count == 2)
        await #expect(throws: APIError.self) {
            _ = try await api.createPlace(NewPlace(name: "Park", lat: 1, lng: 1))
        }
        try await api.deletePlace(id: places[0].id)
        #expect(try await api.places().count == 1)
    }

    @Test func aDaysRouteIsOldestFirst() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await lucas(api)
        let today = Date.now.formatted(.iso8601.year().month().day())
        let route = try await api.visits(childId: child.id, day: today)
        #expect(!route.visits.isEmpty)
        #expect(route.visits.allSatisfy { $0.day.key == today })
        #expect(route.visits == route.visits.sorted { $0.arrivedAt < $1.arrivedAt })
        #expect(!route.isThinned)
        await #expect(throws: APIError.self) {
            _ = try await api.visits(childId: child.id, day: "yesterday")
        }
    }

    @Test func aVisitWithoutANameStillDecodes() throws {
        let json = #"""
        { "id": "v1", "deviceName": "Galaxy A54", "lat": 11.29, "lng": 125.07, "placeLabel": null, "placeId": null,
          "arrivedAt": "2026-10-10T06:00:00Z", "lastSeenAt": null, "timeLabel": "2:00 PM",
          "day": { "key": "2026-10-10", "label": "Today" }, "stayed": false, "durationMinutes": 2, "spanLabel": null }
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let visit = try decoder.decode(Visit.self, from: Data(json.utf8))
        #expect(visit.isPassingBy)
        #expect(visit.displayLabel == "Passing by")
        #expect(!visit.canBeNamed)
    }

    // MARK: Devices

    @Test func movingADeviceClearsItsReportsAndChangesPrimary() async throws {
        let api = MockEGuardAPI.seeded()
        let children = try await api.children()
        let mia = try #require(children.first { $0.name == "Mia" })
        let lucas = try #require(children.first { $0.name == "Lucas" })
        let phone = try #require(try await api.child(id: mia.id).devices.first)

        await #expect(throws: APIError.self) {
            _ = try await api.moveDevice(id: phone.id, childId: lucas.id, confirmation: .password("wrong"))
        }
        await #expect(throws: APIError.self) {
            _ = try await api.moveDevice(id: phone.id, childId: mia.id, confirmation: .password("ChangeMe123!"))
        }
        let moved = try await api.moveDevice(id: phone.id, childId: lucas.id, confirmation: .password("ChangeMe123!"))
        #expect(moved.childId == lucas.id)
        #expect(moved.firstCheck == true)
        #expect(moved.isPrimary == false)
        #expect(try await api.child(id: mia.id).devices.isEmpty)
        #expect(try await api.alerts(filter: .devices, childId: lucas.id, includeResolved: false, before: nil).alerts.first?.title == "Device moved")

        let primary = try await api.updateDevice(id: phone.id, patch: DevicePatch(name: nil, isPrimary: true))
        #expect(primary.isPrimary)
        let summary = try #require(try await api.children().first { $0.id == lucas.id })
        #expect(summary.primaryDevice?.id == phone.id)
        #expect(try await api.child(id: lucas.id).devices.filter(\.isPrimary).count == 1)
    }

    @Test func removingADeviceCanDeleteWhatItRecorded() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await mia(api)
        let phone = try #require(try await api.child(id: child.id).devices.first)
        try await api.unpairDevice(id: phone.id, confirmation: .password("ChangeMe123!"), deleteHistory: true)
        #expect(try await api.child(id: child.id).devices.isEmpty)
        #expect(api.isDeviceRemoved(phone.id))
    }

    @Test func aFreshlyPairedDeviceWaitsForItsFirstCheck() async throws {
        let api = MockEGuardAPI.seeded()
        let child = try await mia(api)
        let code = try await api.pairingCode(childId: child.id)
        #expect(code.expiresInSeconds == 900)
        #expect(code.secondsRemaining == 900)
        let paired = try api.redeemPairingCode(code.code, name: "Mia's iPad", platform: .ios, model: "iPad", kind: "TABLET", osVersion: "iOS 26.0")
        let before = try await api.device(id: paired.deviceId)
        #expect(before.firstCheck == true)
        #expect(before.device.statusText == "Waiting for first check")
        _ = api.recordDeviceReport(deviceId: paired.deviceId, entries: [ReportEntry(key: "BEDTIME", config: .object(["enabled": .bool(false), "start": .string("22:00"), "end": .string("06:00"), "days": .string("EVERY_DAY")]))], full: true)
        let after = try await api.device(id: paired.deviceId)
        #expect(after.firstCheck == false)
    }

    @Test func pairingCodesCountDownFromTheServersSeconds() {
        let fromSeconds = PairingCode(code: "ABCD2345", expiresAt: .now, expiresInSeconds: 120, childName: "Mia", kind: "DEVICE")
        #expect(fromSeconds.secondsRemaining == 120)
        let fromDate = PairingCode(code: "ABCD2345", expiresAt: Date.now.addingTimeInterval(600), childName: "Mia", kind: "DEVICE")
        #expect((595...600).contains(fromDate.secondsRemaining))
    }

    @Test func confirmationBodiesCarryExtraFields() throws {
        let body = DeletionConfirmation.typedDelete.body(adding: ["deleteHistory": .bool(true)])
        #expect(body["confirm"]?.stringValue == "DELETE")
        #expect(body["deleteHistory"]?.boolValue == true)
        let move = DeletionConfirmation.password("secret").body(adding: ["childId": .string("c1")])
        #expect(move["password"]?.stringValue == "secret")
        #expect(move["childId"]?.stringValue == "c1")
    }

    // MARK: Family, dashboard and alerts

    @Test func theAdminRenamesTheFamily() async throws {
        let api = MockEGuardAPI.seeded()
        await #expect(throws: APIError.self) {
            _ = try await api.renameFamily(name: "X")
        }
        let family = try await api.renameFamily(name: "The Cruzes")
        #expect(family.name == "The Cruzes")
        #expect(try await api.me().family.name == "The Cruzes")
    }

    @Test func theDashboardCountsBrowsersAsSlots() async throws {
        let api = MockEGuardAPI.seeded()
        let dashboard = try await api.dashboard()
        #expect(dashboard.browserCount == 1)
        #expect(dashboard.slotsUsed == dashboard.deviceCount + 1)
        let browser = try #require(try await api.browsers().first)
        #expect(browser.stateLabel == "Protected")
    }

    @Test func unknownAlertActionsGetNoButton() {
        let known = AlertAction(type: "VIEW_FAMILY", label: "Open family", childId: nil, key: nil, deviceId: nil)
        let unknown = AlertAction(type: "SOMETHING_NEW", label: "Try it", childId: nil, key: nil, deviceId: nil)
        #expect(known.isKnown)
        #expect(!unknown.isKnown)
        let siteRequest = AlertAction(type: "REVIEW_SITE_REQUEST", label: "Review", childId: "c1", key: nil, deviceId: nil, requestId: "r1")
        #expect(siteRequest.isKnown)
        #expect(siteRequest.requestId == "r1")
    }
}
