import Foundation

/// A child device API backed by the same in-memory server as `MockEGuardAPI`, so a paired mock device
/// shows up on the parent side and its reports verify the parent's changes.
final class MockDeviceAPI: DeviceAPIService {
    private let server: MockEGuardAPI
    /// Set by `pair`; the device token encodes it so a relaunch isn't needed in tests.
    private(set) var deviceId: String?
    /// Thrown by the next call, then cleared.
    var nextError: DeviceAPIError?
    private(set) var reports: [ReportRequest] = []
    private(set) var fixes: [LocationFix] = []
    private(set) var events: [DeviceEvent] = []

    init(server: MockEGuardAPI) {
        self.server = server
    }

    private func gate() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    private func requireDevice() throws -> String {
        guard let deviceId, !server.isDeviceRemoved(deviceId) else {
            throw DeviceAPIError.server(status: 401, message: "Invalid or missing device token")
        }
        return deviceId
    }

    func pair(_ request: PairRequest) async throws -> PairResponse {
        try gate()
        guard (1...60).contains(request.name.count) else { throw DeviceAPIError.server(status: 400, message: "name must be 1 to 60 characters") }
        do {
            let paired = try server.redeemPairingCode(request.code, name: request.name, platform: .ios, model: request.model, kind: request.kind, osVersion: request.osVersion)
            deviceId = paired.deviceId
            return PairResponse(deviceId: paired.deviceId, token: "device-token-\(paired.deviceId)", childName: paired.childName)
        } catch let error as APIError {
            throw DeviceAPIError.server(status: error.status ?? 400, message: error.localizedDescription)
        }
    }

    func sync(_ status: DeviceStatus) async throws -> SyncResponse {
        try gate()
        return try server.deviceSync(deviceId: try requireDevice())
    }

    func report(_ request: ReportRequest) async throws -> ReportResponse {
        try gate()
        let deviceId = try requireDevice()
        reports.append(request)
        let ignored = server.recordDeviceReport(deviceId: deviceId, entries: request.protections, full: request.full == true)
        return ReportResponse(ok: true, ignored: ignored.isEmpty ? nil : ignored)
    }

    func usage(_ request: UsageRequest) async throws {
        try gate()
        server.recordDeviceUsage(deviceId: try requireDevice(), usage: request)
    }

    func location(_ fix: LocationFix) async throws {
        try gate()
        fixes.append(fix)
        server.recordDeviceLocation(deviceId: try requireDevice(), fix: fix)
    }

    func event(_ event: DeviceEvent) async throws -> EventResponse {
        try gate()
        let deviceId = try requireDevice()
        if events.contains(where: { $0.eventId == event.eventId }) {
            return EventResponse(ok: true, approval: nil, duplicate: true)
        }
        events.append(event)
        return server.recordDeviceEvent(deviceId: deviceId, event: event)
    }
}
