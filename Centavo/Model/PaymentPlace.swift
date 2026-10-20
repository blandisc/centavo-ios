import CoreLocation
import Foundation

/// Where a payment happened: the iPhone's own position the moment it was logged, the way
/// Wallet shows a map under each charge. Wallet does not hand its location to Atajos, so
/// this is where the person was: right for a payment in a shop, their own place for one
/// online. Only with «Guardar dónde pagas» on and the location permission given.
@MainActor
enum PaymentPlace {
    static let key = "guardarUbicacion"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static var isAllowed: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// Where the iPhone is now, or `nil` (off, no permission, no fix within a few seconds).
    static func current(timeout: Duration = .seconds(6)) async -> CLLocationCoordinate2D? {
        guard isOn, isAllowed else { return nil }
        return await OneShotLocation().fetch(timeout: timeout)?.coordinate
    }

    /// Asks for the permission, from the switch in «Más».
    static func requestPermission() {
        Permission.shared.request()
    }

    @MainActor
    private final class Permission: NSObject, CLLocationManagerDelegate {
        static let shared = Permission()
        private let manager = CLLocationManager()
        func request() {
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }
}

/// One position, then it stops: a recent one if the iPhone already has it, else a fresh one.
@MainActor
private final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func fetch(timeout: Duration) async -> CLLocation? {
        if let last = manager.location, Date.now.timeIntervalSince(last.timestamp) < 120 { return last }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                self.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
