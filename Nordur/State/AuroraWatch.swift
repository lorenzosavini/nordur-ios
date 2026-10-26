import Foundation
import CoreLocation
import Observation

/// Keeps the aurora checked every few minutes with the app closed, at night.
///
/// Without notifications pushed from a server (they need a paid developer
/// account) iOS wakes an app only now and then, rarely at night with the phone
/// still. While the watch is on, low-accuracy location updates keep the app
/// running in the background (iOS shows the blue location indicator), and the
/// alert check (aurora now, Bz, NOAA, CMEs) runs every 3 minutes. The watch
/// turns itself off at dawn and on again after dusk, at the place watched.
@MainActor
@Observable
final class AuroraWatch: NSObject {
    static let shared = AuroraWatch()
    static let interval: TimeInterval = 3 * 60

    private(set) var isActive = false
    private(set) var lastRun: Date?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var loop: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 1000
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    /// Starts or stops the watch for the mode chosen and the hour at the place watched.
    func update() {
        let settings = AlertCenter.shared.settings
        let wanted: Bool
        switch settings.auroraWatch {
        case .off: wanted = false
        case .always: wanted = settings.isOn(.aurora)
        case .night: wanted = settings.isOn(.aurora) && Self.isDark(at: AlertCenter.shared.auroraPlace(current: LocationManager.lastKnown).coordinate)
        }
        wanted ? start() : stop()
    }

    /// Sun 6° below the horizon or lower (civil dusk), with half an hour of margin.
    static func isDark(at c: Coordinate, now: Date = Date()) -> Bool {
        Astro.sunAltitude(now, at: c) < -6 || Astro.sunAltitude(now.addingTimeInterval(1800), at: c) < -6
    }

    private func start() {
        guard !isActive else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            if status == .notDetermined { manager.requestWhenInUseAuthorization() }
            return
        }
        isActive = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await AlertCenter.shared.check()
                self?.lastRun = Date()
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
                self?.update()   // off at dawn
            }
        }
    }

    private func stop() {
        guard isActive else { return }
        isActive = false
        loop?.cancel()
        loop = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
}

extension AuroraWatch: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { ErrorLog.location(error) }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in AuroraWatch.shared.update() }
    }
}
