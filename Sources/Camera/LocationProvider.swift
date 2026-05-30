import CoreLocation

/// Supplies the most recent device location for embedding into photo metadata.
///
/// Only used when the "Location" capture-metadata toggle is on. Requests
/// when-in-use authorization and keeps the latest fix; capture reads
/// ``currentLocation`` (which may be `nil` until a fix arrives or if access is
/// denied — in which case GPS is simply omitted).
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var currentLocation: CLLocation?

    private let manager = CLLocationManager()
    private var updating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Requests permission (if needed) and begins receiving location updates.
    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        guard !updating else { return }
        updating = true
        manager.startUpdatingLocation()
    }

    func stop() {
        updating = false
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.currentLocation = location }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        Task { @MainActor in self.start() }
    }
}
