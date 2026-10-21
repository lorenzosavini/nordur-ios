import Foundation
import Observation
import UserNotifications
import CoreLocation
import AVFoundation
import UIKit
import BackgroundTasks

/// Real-time alert system.
///
/// When it runs:
/// - every 5 minutes while the app is open;
/// - every 5 minutes while a drive is being recorded (the app stays alive in
///   the background thanks to continuous GPS);
/// - whenever you move, even without recording a drive: significant location
///   changes (~500 m+) plus a 2 km geofence around the last fix that is
///   re-centred each time you leave it. iOS relaunches the app for both when
///   location access is "Sempre";
/// - on iOS background refresh (best effort, roughly hourly).
///
/// Each condition has a stable key so it notifies once; repeating conditions
/// (e.g. strong gusts) re-arm after a few hours.
@MainActor
@Observable
final class AlertCenter: NSObject {
    static let shared = AlertCenter()
    static let refreshTaskID = "it.lorenzosavini.nordur.refresh"

    private(set) var events: [AlertEvent] = []
    private(set) var settings: AlertSettings
    private(set) var lastCheck: Date?
    private(set) var isChecking = false
    private(set) var notificationsAllowed = false
    /// Set when the user taps a notification; the UI opens the inbox.
    var openInbox = false
    /// The alert whose notification was tapped; the inbox opens on its detail.
    var focusedAlertID: String?
    /// True while DriveRecorder is recording (enables spoken alerts).
    var isDriving = false
    /// True when the last background fix was at driving speed.
    private(set) var isMoving = false

    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var fired: [String: Date] = [:]
    @ObservationIgnored private let significant = CLLocationManager()
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var lastPositionCheck: (date: Date, coordinate: Coordinate)?
    private static let fenceID = "nordur.here"

    private override init() {
        settings = AlertSettings.load()
        super.init()
        loadFromDisk()
        significant.delegate = self
        UNUserNotificationCenter.current().delegate = self
        applyBackgroundLocation()
        Task { await refreshPermissionState() }
    }

    /// Picks up an inbox and settings restored from the account backup.
    func reloadAfterRestore() {
        loadFromDisk()
        settings = AlertSettings.load()
        applyBackgroundLocation()
    }

    var unreadCount: Int { events.filter { !$0.read }.count }
    var latest: AlertEvent? { events.first }

    // MARK: - Settings

    func update(_ newSettings: AlertSettings) {
        settings = newSettings
        settings.save()
        applyBackgroundLocation()
        AuroraWatch.shared.update()
    }

    func toggleFollow(_ flightNumber: String) {
        var s = settings
        if let index = s.followedFlights.firstIndex(of: flightNumber) {
            s.followedFlights.remove(at: index)
        } else {
            s.followedFlights.append(flightNumber)
            s.enabled.insert(.flight)
        }
        update(s)
    }

    func isFollowing(_ flightNumber: String) -> Bool { settings.followedFlights.contains(flightNumber) }

    func requestNotificationPermission() async {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        notificationsAllowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }

    func refreshPermissionState() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status == .authorized || status == .provisional || status == .ephemeral
    }

    private func applyBackgroundLocation() {
        if settings.backgroundLocation {
            if significant.authorizationStatus == .authorizedWhenInUse || significant.authorizationStatus == .notDetermined {
                significant.requestAlwaysAuthorization()
            }
            significant.startMonitoringSignificantLocationChanges()
            if let last = LocationManager.lastKnown { recentreFence(on: last) }
        } else {
            significant.stopMonitoringSignificantLocationChanges()
            for region in significant.monitoredRegions where region.identifier == Self.fenceID {
                significant.stopMonitoring(for: region)
            }
        }
    }

    /// A small geofence around the current position: leaving it wakes the app
    /// sooner than significant-change monitoring alone, which on the road can lag.
    private func recentreFence(on c: Coordinate) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(center: c.clCoordinate, radius: 2000, identifier: Self.fenceID)
        region.notifyOnExit = true
        region.notifyOnEntry = false
        significant.startMonitoring(for: region)
    }

    /// Called for every background fix. Throttled so a fast drive doesn't
    /// download everything each minute.
    fileprivate func handleFix(_ location: CLLocation) async {
        let coordinate = Coordinate(location.coordinate)
        LocationManager.lastKnown = coordinate
        isMoving = location.speed > 8
        recentreFence(on: coordinate)
        if let last = lastPositionCheck,
           Date().timeIntervalSince(last.date) < 180,
           Geo.distanceKm(last.coordinate, coordinate) < 3 { return }
        lastPositionCheck = (Date(), coordinate)
        let task = UIApplication.shared.beginBackgroundTask(withName: "alert-check")
        await check(position: coordinate)
        UIApplication.shared.endBackgroundTask(task)
    }

    fileprivate func requestFix() { significant.requestLocation() }

    var backgroundLocationStatus: CLAuthorizationStatus { significant.authorizationStatus }

    // MARK: - Inbox

    func markAllRead() {
        for i in events.indices { events[i].read = true }
        UNUserNotificationCenter.current().setBadgeCount(0)
        save()
    }

    func markRead(_ event: AlertEvent) {
        guard let i = events.firstIndex(where: { $0.id == event.id }), !events[i].read else { return }
        events[i].read = true
        UNUserNotificationCenter.current().setBadgeCount(unreadCount)
        save()
    }

    func delete(_ event: AlertEvent) {
        events.removeAll { $0.id == event.id }
        save()
    }

    func clearAll() {
        events.removeAll()
        save()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Records an event raised elsewhere (e.g. speeding during a drive).
    func record(_ event: AlertEvent, notify: Bool, speak: Bool) {
        guard fired[event.id] == nil else { return }
        fired[event.id] = event.date
        Task {
            var event = event
            if Self.quotesWeb(event) { event = await Translator.shared.localize(event) }
            events.insert(event, at: 0)
            if notify { post(event) }
            if speak { say(event.title) }
            save()
        }
    }

    // MARK: - Checking

    /// Runs one pass over every source. `position` is the live GPS fix when known.
    func check(position: Coordinate? = nil) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let input = await buildInput(position: position)
        let candidates = AlertEngine.evaluate(input, settings: settings)
        await deliver(candidates)
        lastCheck = Date()
    }

    /// The place watched for "where you are": the place chosen by hand when there
    /// is one (a pin in Iceland while the phone is elsewhere), otherwise the GPS;
    /// and with the GPS outside Iceland, the trip stop of tonight if there is one.
    func auroraPlace(current: Coordinate?) -> Place {
        let useCurrent = model?.useCurrentLocation ?? (UserDefaults.standard.object(forKey: "useCurrentLocation") as? Bool ?? true)
        if !useCurrent { return model?.activePlace ?? AppModel.monitoredPlace }
        guard let current else { return AppModel.monitoredPlace }
        if !Coverage.iceland(current) {
            let now = Date()
            if let stop = TripStore.loadFromDisk().first(where: { $0.date <= now && now < $0.endDate }) { return stop.place }
        }
        return Place(name: String(localized: "la tua posizione"), coordinate: current)
    }

    private func buildInput(position: Coordinate?) async -> AlertInput {
        let now = Date()
        var input = AlertInput()
        input.now = now

        let current = position ?? model?.location.coordinate ?? LocationManager.lastKnown
        let currentPlace = auroraPlace(current: current)
        input.watched.append(.init(name: currentPlace.name, coordinate: currentPlace.coordinate,
                                   from: now, to: now.addingTimeInterval(12 * 3600), isCurrent: true))
        let horizon = now.addingTimeInterval(3 * 24 * 3600)
        for stop in TripStore.loadFromDisk() where stop.endDate >= now && stop.date <= horizon {
            input.watched.append(.init(name: stop.place.name, coordinate: stop.place.coordinate,
                                       from: stop.date.addingTimeInterval(-12 * 3600), to: stop.endDate, isCurrent: false))
        }

        if let model {
            await model.refreshGlobal()
            input.warnings = model.warnings?.value ?? []
            input.roads = model.roads?.value
            input.roadInfo = model.roadInfo?.value
            input.roadGeometry = model.roadGeometry?.value
            input.quakes = model.quakes?.value ?? []
            input.news = model.news?.value ?? []
        } else {
            async let w = attempt { try await IMO.warnings().value }
            async let r = attempt { try await Roads.network().value }
            async let q = attempt { try await IMO.quakes(hours: 6).value }
            async let n = attempt { try await SafeTravel.news().value }
            input.warnings = (try? await w.get()) ?? []
            input.roads = try? await r.get()
            input.roadInfo = try? await RoadInfoService.load().value
            input.roadGeometry = try? await RoadGeometry.load().value
            input.quakes = (try? await q.get()) ?? []
            input.news = (try? await n.get()) ?? []
        }

        if settings.isOn(.aurora) {
            // Space weather is checked at any hour (CMEs, Bz, NOAA alerts);
            // the observing conditions only matter after dark, which the engine knows.
            let state: AuroraState?
            if let model {
                await model.refreshAurora()
                state = model.aurora?.value
            } else {
                state = try? await AuroraStateService.load().value
            }
            let forecast = model?.activePlace.coordinate == currentPlace.coordinate ? model?.forecast?.value : nil
            let weather: Forecast?
            if let forecast { weather = forecast } else { weather = try? await WeatherService.forecast(currentPlace.coordinate).value }
            let inputs = AuroraInputs.make(place: currentPlace.coordinate, forecast: weather, state: state,
                                           kp: model?.kp?.value ?? [], ovation: model?.ovation?.value,
                                           horizon: model?.horizons[TerrainService.key(currentPlace.coordinate)], now: now)
            input.auroraSlots = AuroraEngine.forecast(inputs, hours: 12)
            input.auroraState = state
            input.auroraZone = weather?.timeZone ?? .iceland
            if let model {
                input.sightings = model.sightings?.value.recent ?? []
            } else {
                input.sightings = (try? await SightingsFeed.loadFetched().value.recent) ?? []
            }
        }

        if settings.isOn(.flight), !settings.followedFlights.isEmpty {
            input.flights = (try? await TransportService.kefFlights().value) ?? []
        }
        if settings.isOn(.ferry) {
            if let fetched = try? await TransportService.herjolfur() { input.ferry = fetched.value }
        }
        return input
    }

    private func deliver(_ candidates: [AlertEvent]) async {
        let fresh = candidates.filter { fired[$0.id] == nil }.sorted { $0.severity > $1.severity }
        guard !fresh.isEmpty else { return }
        for event in fresh { fired[event.id] = event.date }
        for original in fresh {
            // Alerts quoting web text (IMO, SafeTravel, Vegagerðin, Herjólfur, NOAA) in the app language.
            var event = original
            if Self.quotesWeb(original) { event = await Translator.shared.localize(original) }
            events.insert(event, at: 0)
            post(event)
            if (isDriving || isMoving) && settings.spoken && event.risk >= .warning {
                say(event.title)
            }
        }
        save()
    }

    private static func quotesWeb(_ event: AlertEvent) -> Bool {
        let prefix = event.id.split(separator: ":").first.map(String.init) ?? ""
        return ["w", "s", "h", "swpc", "ri", "rh", "rwh", "rwi", "r", "rw"].contains(prefix)
    }

    private func post(_ event: AlertEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.subtitle = event.category.shortLabel
        content.body = event.body
        content.sound = .default
        if let picture = NotificationIcon.attachment(for: event) { content.attachments = [picture] }
        content.threadIdentifier = event.category.rawValue
        content.interruptionLevel = event.risk >= .warning ? .timeSensitive : .active
        content.relevanceScore = Double(event.severity) / 3
        content.badge = NSNumber(value: unreadCount)
        content.userInfo = ["alertID": event.id]
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func say(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Bundle.main.preferredLocalizations.first == "en" ? "en-GB" : "it-IT")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speech.speak(utterance)
    }

    // MARK: - Background

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("alerts.json")
    }

    private struct Stored: Codable {
        var events: [AlertEvent]
        var fired: [String: Date]
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        events = stored.events
        fired = stored.fired
    }

    private func save() {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        fired = fired.filter { $0.value > weekAgo }
        if events.count > 300 { events = Array(events.prefix(300)) }
        if let data = try? JSONEncoder().encode(Stored(events: events, fired: fired)) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

extension AlertCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["alertID"] as? String
        await MainActor.run {
            AlertCenter.shared.focusedAlertID = id
            AlertCenter.shared.openInbox = true
        }
    }
}

extension AlertCenter: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await AlertCenter.shared.handleFix(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in AlertCenter.shared.requestFix() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if AlertCenter.shared.settings.backgroundLocation {
                manager.startMonitoringSignificantLocationChanges()
                if let last = LocationManager.lastKnown { AlertCenter.shared.recentreFence(on: last) }
            }
        }
    }
}
