import CoreLocation
import Foundation
import Observation

/// Reads the device's position for the child device API, only when the family asked for it.
@MainActor
protocol LocationReporting: AnyObject {
    /// Whether the OS lets eGuard read the location right now.
    var isAuthorized: Bool { get }
    /// Whether the person has never been asked.
    var isUndetermined: Bool { get }
    func requestPermission() async
    /// One fix, or nil when unavailable. Never reverse-geocodes on the device.
    func currentFix() async -> LocationFix?
}

/// The live Core Location implementation. "When in use" is enough: fixes are sent while eGuard syncs.
@Observable
final class CoreLocationReporter: NSObject, LocationReporting, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var permissionContinuation: CheckedContinuation<Void, Never>?
    private var fixContinuation: CheckedContinuation<LocationFix?, Never>?
    private(set) var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isUndetermined: Bool { status == .notDetermined }

    func requestPermission() async {
        guard isUndetermined else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            permissionContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentFix() async -> LocationFix? {
        guard isAuthorized else { return nil }
        if fixContinuation != nil { return nil }
        return await withCheckedContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.status = status
            if status != .notDetermined {
                permissionContinuation?.resume()
                permissionContinuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last.map { location in
            LocationFix(lat: location.coordinate.latitude, lng: location.coordinate.longitude, accuracyM: max(location.horizontalAccuracy, 0), placeLabel: nil)
        }
        Task { @MainActor in
            fixContinuation?.resume(returning: fix)
            fixContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            fixContinuation?.resume(returning: nil)
            fixContinuation = nil
        }
    }
}

/// A controllable implementation for previews, the simulator, and tests.
@Observable
final class MockLocationReporter: LocationReporting {
    var isAuthorized = false
    var isUndetermined = true
    var fix: LocationFix? = LocationFix(lat: 10.6785, lng: 124.8006, accuracyM: 25, placeLabel: nil)
    private(set) var fixesRequested = 0

    init() {}

    func requestPermission() async {
        isUndetermined = false
        isAuthorized = true
    }

    func currentFix() async -> LocationFix? {
        guard isAuthorized else { return nil }
        fixesRequested += 1
        return fix
    }
}
