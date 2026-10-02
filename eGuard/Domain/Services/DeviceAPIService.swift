import Foundation

/// The child device API: what the device sends and receives. Implemented by the live client and a mock.
@MainActor
protocol DeviceAPIService: AnyObject {
    /// Exchanges a pairing code for a device token. No auth.
    func pair(_ request: PairRequest) async throws -> PairResponse
    /// The heartbeat: policy, open changes, app rules and the next sync time.
    func sync(_ status: DeviceStatus) async throws -> SyncResponse
    /// What the device actually has, read back from the OS. The only way a setting becomes verified.
    func report(_ request: ReportRequest) async throws -> ReportResponse
    func usage(_ request: UsageRequest) async throws
    func location(_ fix: LocationFix) async throws
    func event(_ event: DeviceEvent) async throws -> EventResponse
}

/// Live client for `/api/device/v1`.
final class LiveDeviceAPI: DeviceAPIService {
    private let client: DeviceAPIClient

    init(client: DeviceAPIClient) {
        self.client = client
    }

    func pair(_ request: PairRequest) async throws -> PairResponse {
        try await client.post("pair", body: request, requiresAuth: false, as: PairResponse.self)
    }

    func sync(_ status: DeviceStatus) async throws -> SyncResponse {
        try await client.post("sync", body: status, as: SyncResponse.self)
    }

    func report(_ request: ReportRequest) async throws -> ReportResponse {
        try await client.post("report", body: request, as: ReportResponse.self)
    }

    func usage(_ request: UsageRequest) async throws {
        _ = try await client.post("usage", body: request, as: DeviceOK.self)
    }

    func location(_ fix: LocationFix) async throws {
        _ = try await client.post("location", body: fix, as: DeviceOK.self)
    }

    func event(_ event: DeviceEvent) async throws -> EventResponse {
        try await client.post("events", body: event, as: EventResponse.self)
    }
}
