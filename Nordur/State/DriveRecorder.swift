import Foundation
import Observation
import CoreLocation
import ActivityKit

/// Records car journeys with GPS: distance, times, speeds, altitude, stops,
/// odometer and fuel estimate. Keeps running with the screen locked (blue
/// location pill), shows a Live Activity and runs the alert checks while driving.
@MainActor
@Observable
final class DriveRecorder: NSObject {
    static let shared = DriveRecorder()

    private(set) var session: DriveSession?
    private(set) var isPaused = false
    private(set) var speedKmh: Double = 0
    private(set) var gpsAccuracy: Double?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Unfinished drive found at launch (app was killed while recording).
    private(set) var recoverable: DriveSession?
    /// Edited directly by the UI; persisted with `saveSettings()`.
    var settings = DriveSettings.load()

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var activity: Activity<DriveActivityAttributes>?
    @ObservationIgnored private var pauseStarted: Date?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var lastActivityUpdate = Date.distantPast
    @ObservationIgnored private var lastAlertCheck = Date.distantPast
    @ObservationIgnored private var lastSpeedWarning = Date.distantPast
    @ObservationIgnored private var speedingSince: Date?

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        recoverable = DriveStore.loadInProgress()
    }

    var isRecording: Bool { session != nil }

    func saveSettings() { settings.save() }

    /// Last points for the live mini map.
    var recentPoints: [TrackPoint] { session.map { DriveMath.downsample($0.points, maxPoints: 800) } ?? [] }

    // MARK: Controls

    func start(name: String? = nil) {
        guard session == nil else { return }
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        let now = Date()
        let title = name ?? String(localized: "Viaggio del \(Fmt.dayTime(now, in: .current))")
        var new = DriveSession(name: title, start: now)
        new.odometerStart = settings.odometer
        session = new
        isPaused = false
        beginUpdates()
        startLiveActivity()
        AlertCenter.shared.isDriving = true
        DriveStore.saveInProgress(new)
    }

    func resumeRecovered() {
        guard let recovered = recoverable, session == nil else { return }
        var s = recovered
        // Time between the crash and now counts as a pause.
        if let last = s.points.last?.t { s.pausedSeconds += Date().timeIntervalSince(last) }
        session = s
        recoverable = nil
        isPaused = false
        beginUpdates()
        startLiveActivity()
        AlertCenter.shared.isDriving = true
    }

    func saveRecovered() {
        guard var recovered = recoverable else { return }
        recovered.end = recovered.points.last?.t ?? recovered.start
        DriveStore.shared.save(recovered)
        if let odometer = recovered.odometerEnd { settings.odometer = odometer }
        settings.save()
        DriveStore.clearInProgress()
        recoverable = nil
    }

    func discardRecovered() {
        DriveStore.clearInProgress()
        recoverable = nil
    }

    func pause() {
        guard session != nil, !isPaused else { return }
        isPaused = true
        pauseStarted = Date()
        manager.stopUpdatingLocation()
        speedKmh = 0
        updateLiveActivity(force: true)
    }

    func resume() {
        guard session != nil, isPaused else { return }
        if let started = pauseStarted { session?.pausedSeconds += Date().timeIntervalSince(started) }
        pauseStarted = nil
        isPaused = false
        manager.startUpdatingLocation()
        updateLiveActivity(force: true)
    }

    @discardableResult
    func stop() -> DriveSession? {
        guard var finished = session else { return nil }
        if isPaused, let started = pauseStarted { finished.pausedSeconds += Date().timeIntervalSince(started) }
        finished.end = Date()
        endUpdates()
        endLiveActivity(finished)
        session = nil
        isPaused = false
        speedKmh = 0
        AlertCenter.shared.isDriving = false
        RoadWatch.shared.clear()
        DriveStore.clearInProgress()
        // Keep only drives with some movement.
        guard finished.stats.distanceMeters > 50 || finished.points.count > 10 else { return nil }
        DriveStore.shared.save(finished)
        if let odometer = finished.odometerEnd { settings.odometer = (odometer * 10).rounded() / 10 }
        settings.save()
        return finished
    }

    func discard() {
        endUpdates()
        if let s = session { endLiveActivity(s) }
        session = nil
        isPaused = false
        AlertCenter.shared.isDriving = false
        DriveStore.clearInProgress()
    }

    private func beginUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        backgroundSession = CLBackgroundActivitySession()
        manager.startUpdatingLocation()
    }

    private func endUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    // MARK: Location handling

    fileprivate func handle(_ location: CLLocation) {
        guard var current = session, !isPaused else { return }
        gpsAccuracy = location.horizontalAccuracy
        let point = TrackPoint(
            t: location.timestamp,
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            alt: location.verticalAccuracy > 0 ? location.altitude : nil,
            speed: location.speedAccuracy >= 0 || location.speed >= 0 ? location.speed : -1,
            course: location.course >= 0 ? location.course : nil,
            accuracy: location.horizontalAccuracy
        )
        guard DriveMath.append(point, to: &current, settings: settings) else { return }
        session = current
        speedKmh = point.kmh
        LocationManager.lastKnown = point.coordinate

        let now = Date()
        if now.timeIntervalSince(lastSave) > 20 {
            lastSave = now
            DriveStore.saveInProgress(current)
        }
        updateLiveActivity(force: false)
        checkSpeed(point, now: now)
        Task { await RoadWatch.shared.refresh(position: point.coordinate, course: point.course, speedKmh: point.kmh) }
        if now.timeIntervalSince(lastAlertCheck) > 5 * 60 {
            lastAlertCheck = now
            Task {
                await AlertCenter.shared.check(position: point.coordinate)
                self.updateLiveActivity(force: true)
            }
        }
    }

    private func checkSpeed(_ point: TrackPoint, now: Date) {
        guard settings.speedAlerts, AlertCenter.shared.settings.isOn(.speed) else { return }
        if point.kmh > settings.speedLimit + 5 {
            if speedingSince == nil { speedingSince = now }
            if let since = speedingSince, now.timeIntervalSince(since) > 10, now.timeIntervalSince(lastSpeedWarning) > 120 {
                lastSpeedWarning = now
                let event = AlertEvent(
                    id: "v:\(Int(now.timeIntervalSince1970))", date: now, category: .speed, severity: Risk.caution.rawValue,
                    title: String(localized: "Velocità \(Int(point.kmh)) km/h – limite \(Int(settings.speedLimit))"),
                    body: String(localized: "In Islanda le multe per eccesso di velocità sono molto alte. Su sterrato il limite è 80 km/h, nei centri abitati 50."),
                    coordinate: point.coordinate)
                AlertCenter.shared.record(event, notify: false, speak: settings.spokenAlerts)
            }
        } else {
            speedingSince = nil
        }
    }

    // MARK: Live Activity

    private func liveState() -> DriveActivityAttributes.ContentState? {
        guard let s = session else { return nil }
        let elapsed = s.durationSeconds() - (pauseStarted.map { Date().timeIntervalSince($0) } ?? 0)
        let alert = AlertCenter.shared.latest.flatMap { Date().timeIntervalSince($0.date) < 3 * 3600 ? $0 : nil }
        let hazard = RoadWatch.shared.nextHazard
        var hazardText: String?
        if let h = hazard {
            var text = String(localized: "Tra \(Int(h.kmAhead)) km: \(h.station.name), raffiche \(Fmt.ms(h.station.Vindhvida))")
            if let bad = h.segments.first(where: { ($0.risk ?? .ok) >= .warning }) { text += " · " + bad.conditionItalian }
            hazardText = text
        }
        return .init(
            km: s.stats.km,
            elapsedSeconds: elapsed,
            speedKmh: speedKmh,
            averageKmh: s.stats.averageKmh(totalSeconds: elapsed),
            odometer: s.odometerEnd,
            paused: isPaused,
            alertTitle: hazardText ?? alert?.title,
            alertSeverity: hazard?.risk.rawValue ?? alert?.severity ?? 0,
            updated: Date()
        )
    }

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let s = session, let state = liveState() else { return }
        let attributes = DriveActivityAttributes(name: s.name, start: s.start)
        activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: Date().addingTimeInterval(600)))
    }

    private func updateLiveActivity(force: Bool) {
        let now = Date()
        guard let activity, force || now.timeIntervalSince(lastActivityUpdate) > 10, let state = liveState() else { return }
        lastActivityUpdate = now
        Task { await activity.update(.init(state: state, staleDate: now.addingTimeInterval(600))) }
    }

    private func endLiveActivity(_ finished: DriveSession) {
        guard let activity else { return }
        let state = liveState() ?? .init(km: finished.stats.km, elapsedSeconds: finished.durationSeconds(), speedKmh: 0,
                                          averageKmh: finished.stats.averageKmh(totalSeconds: finished.durationSeconds()),
                                          odometer: finished.odometerEnd, paused: false, alertTitle: nil, alertSeverity: 0, updated: Date())
        Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(15 * 60))) }
        self.activity = nil
    }
}

extension DriveRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { DriveRecorder.shared.handle(location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { ErrorLog.location(error) }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in DriveRecorder.shared.authorization = status }
    }
}
