import CoreLocation
import LibrePawKit

/// Wraps `CLLocationManager` to expose the user's own coordinate and compass
/// heading, needed for showing "you are here" on the map and for the
/// compass-based "Find Pet" screen (see ADR-0010).
@Observable
@MainActor
final class LocationService: NSObject {
    private(set) var coordinate: Coordinate?
    private(set) var headingDegrees: Double?
    private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager
    /// How many screens currently want updates (``startUpdating()`` calls
    /// not yet balanced by ``stopUpdating()``). GPS and compass only run
    /// while this is above zero.
    ///
    /// A count rather than a flag because screens overlap: switching from
    /// a pushed Find Pet to the Map tab can run the map's start before
    /// Find Pet's stop, and a single shared on/off switch then turned
    /// updates off right under the map.
    private var activeRequests = 0

    override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// `false` on devices (and always on the Simulator) with no magnetometer.
    /// Callers should fall back to showing direction relative to true north.
    var isHeadingAvailable: Bool {
        CLLocationManager.headingAvailable()
    }

    func requestAuthorizationIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Each call must be balanced by one ``stopUpdating()``, see
    /// `activeRequests`. Without authorization yet, updates start as soon
    /// as it's granted, as long as the request is still active then.
    func startUpdating() {
        activeRequests += 1
        startManagerIfWanted()
    }

    func stopUpdating() {
        activeRequests = max(0, activeRequests - 1)
        guard activeRequests == 0 else { return }
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func startManagerIfWanted() {
        guard activeRequests > 0, isAuthorized else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    /// Also called once right after the manager is created, i.e. at app
    /// launch, on the login screen. Only resumes updates some screen has
    /// actually asked for, previously this started best-accuracy GPS and
    /// the compass at launch whenever permission had been granted before,
    /// with nothing ever stopping them.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            startManagerIfWanted()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor in
            self.coordinate = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.headingDegrees = degrees
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Best-effort: keep showing the last known coordinate/heading rather
        // than surfacing transient location errors in the UI.
    }
}
