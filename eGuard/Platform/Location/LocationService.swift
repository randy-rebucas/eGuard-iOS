import CoreLocation
import MapKit
import Observation

/// Streams this device's location while the parent has location sharing on.
/// Uses the async location updates API, so no delegate is needed.
@Observable
final class LocationService {
    private(set) var currentLocation: CLLocation?
    private(set) var placeName: String?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var errorMessage: String?
    private(set) var isRunning = false

    /// Called when a new place is resolved, so the app can keep a local visit history.
    var onVisit: ((LocationVisit) -> Void)?

    private let manager = CLLocationManager()
    private var session: CLServiceSession?
    private var updatesTask: Task<Void, Never>?
    private var lastGeocode: Date?

    init() {
        authorizationStatus = manager.authorizationStatus
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func start() {
        guard updatesTask == nil else { return }
        isRunning = true
        errorMessage = nil
        session = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self, !Task.isCancelled else { return }
                    authorizationStatus = manager.authorizationStatus
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        errorMessage = "Location access is off. Allow it in Settings to see where the device is."
                        continue
                    }
                    if let location = update.location {
                        await handle(location)
                    }
                }
            } catch {
                self?.errorMessage = "Location updates stopped: \(error.localizedDescription)"
            }
            self?.isRunning = false
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        session?.invalidate()
        session = nil
        isRunning = false
    }

    /// Reverse geocodes sparingly: only after moving a meaningful distance or after a minute.
    private func handle(_ location: CLLocation) async {
        let moved = currentLocation.map { location.distance(from: $0) > 150 } ?? true
        let stale = lastGeocode.map { Date.now.timeIntervalSince($0) > 60 } ?? true
        currentLocation = location
        guard moved || (stale && placeName == nil) else { return }
        lastGeocode = .now

        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return }
        let name = item.addressRepresentations?.cityWithContext
            ?? item.address?.shortAddress
            ?? item.name
            ?? "Unknown place"
        placeName = name
        onVisit?(LocationVisit(
            name: item.name ?? name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))
    }
}
