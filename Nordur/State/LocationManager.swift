import Foundation
import CoreLocation
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let geocoder = CLGeocoder()

    var coordinate: Coordinate?
    var placeName: String?
    var authorization: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let last = Self.lastKnown {
            coordinate = last
        }
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func request() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let newCoordinate = Coordinate(location.coordinate)
        // Avoid refetching everything for tiny GPS jitter.
        if let old = coordinate, Geo.distanceKm(old, newCoordinate) < 1, placeName != nil { return }
        coordinate = newCoordinate
        Self.lastKnown = newCoordinate
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let mark = placemarks?.first
            DispatchQueue.main.async {
                self?.placeName = mark?.locality ?? mark?.name ?? mark?.administrativeArea
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last known position; the UI falls back to the chosen place.
        ErrorLog.location(error)
    }

    private static let lastKnownKey = "lastKnownLocation"

    static var lastKnown: Coordinate? {
        get {
            guard let data = UserDefaults.standard.data(forKey: lastKnownKey) else { return nil }
            return try? JSONDecoder().decode(Coordinate.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: lastKnownKey)
            }
        }
    }
}

extension ErrorLog {
    /// A location error worth keeping: "position not known yet" (kCLErrorLocationUnknown)
    /// is temporary by Apple's definition, the system keeps trying on its own.
    static func location(_ error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        record("Posizione", error)
    }
}
