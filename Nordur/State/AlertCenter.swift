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
    /// What is going on now at each followed place (by coordinate key), from the last check.
    private(set) var followedStatus: [String: [AlertEvent]] = [:]
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
    /// The alerts seen lately by group (AlertLifecycle): their worst level and earliest start.
    @ObservationIgnored private var seen: [String: AlertLifecycle.Seen] = [:]
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
        // Without push (no Apple developer account yet) a notice from the admin panel
        // arrives when iOS wakes the app: moving a few hundred metres is one of those times.
        // Side by side: the alert check never waits for it.
        async let notice: Void = Entitlements.shared.loadConfig()
        await check(position: coordinate)
        await notice
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
        // Each followed place on its own, for its status line (warnings, closed roads, quakes there).
        var status: [String: [AlertEvent]] = [:]
        for place in settings.followed {
            var only = input
            only.watched = [.init(name: place.name, coordinate: place.coordinate, from: input.now, to: input.now.addingTimeInterval(24 * 3600), isCurrent: false)]
            only.legs = []
            only.hereHours = []
            only.auroraSlots = []
            status[place.coordinate.key] = AlertEngine.evaluate(only, settings: settings)
                .filter { [.weatherWarning, .road, .quake].contains($0.category) }
        }
        followedStatus = status
        // A place chosen by hand (browsing Akureyri from home): what is going on
        // there now goes in the inbox without a banner; only what starts after that
        // is notified. Moving with the GPS is not affected.
        let useCurrent = model?.useCurrentLocation ?? (UserDefaults.standard.object(forKey: "useCurrentLocation") as? Bool ?? true)
        let pinned = !useCurrent && settings.followsChosenPlace
        let here = input.watched.first { $0.isCurrent }.map { "\(pinned ? "pin" : "gps"):\(pinned ? $0.coordinate.key : "")" } ?? ""
        let previous = UserDefaults.standard.string(forKey: "alerts.watchedPlace")
        let quiet = pinned && previous != nil && previous != here
        UserDefaults.standard.set(here, forKey: "alerts.watchedPlace")
        await deliver(candidates, quiet: quiet)
        await sendEveningSummary(input)
        lastCheck = Date()
    }

    /// The place watched for "where you are": the place chosen by hand when there
    /// is one (a pin in Iceland while the phone is elsewhere), otherwise the GPS;
    /// and with the GPS outside Iceland, the trip stop of tonight if there is one.
    /// CI only (screenshots of the notifications): one alert of each kind, as they arrive.
    func demoNotifications() {
        guard UserDefaults.standard.bool(forKey: "ciDemoTrip") else { return }
        let now = Date()
        let samples: [AlertEvent] = [
            AlertEvent(id: "demo:w", date: now, category: .weatherWarning, severity: Risk.warning.rawValue,
                       title: String(localized: "Allerta arancione: tempesta da sud-est"),
                       body: String(localized: "Vík · Suðurland · dalle 14:00 fino alle 23:00. Raffiche fino a 35 m/s sotto Eyjafjöll."),
                       expires: now.addingTimeInterval(9 * 3600)),
            AlertEvent(id: "demo:r", date: now.addingTimeInterval(-60), category: .road, severity: Risk.danger.rawValue,
                       title: String(localized: "Strada chiusa: Hringvegur (1) a Mýrdalssandur"),
                       body: String(localized: "A 12 km da te. Fonte: Vegagerðin (umferdin.is), informazioni 1777.")),
            AlertEvent(id: "demo:a", date: now.addingTimeInterval(-120), category: .aurora, severity: Risk.caution.rawValue,
                       title: String(localized: "Condizioni buone per l'aurora, adesso"),
                       body: String(localized: "OVATION 32 nel tuo cielo, cielo sereno al 80%. Guarda verso nord."),
                       expires: now.addingTimeInterval(90 * 60)),
            AlertEvent(id: "demo:s", date: now.addingTimeInterval(-180), category: .summary, severity: Risk.caution.rawValue,
                       title: String(localized: "Riepilogo di domani: Vík → Höfn"),
                       body: String(localized: "Raffiche fino a 22 m/s verso le 14 · Nessuna strada chiusa sul percorso · Stanotte aurora: condizioni buone verso le 23"),
                       expires: now.addingTimeInterval(36 * 3600)),
            AlertEvent(id: "demo:q", date: now.addingTimeInterval(-240), category: .quake, severity: Risk.warning.rawValue,
                       title: String(localized: "Terremoto M3,8 – Mýrdalsjökull"),
                       body: String(localized: "21:12, profondità 4,1 km · 28 km da Vík")),
        ]
        for event in samples.reversed() { fired[event.id] = nil; record(event, notify: true, speak: false) }
    }

    /// The bell next to a place: followed for notifications, or no more.
    func toggleFollow(_ place: Place) {
        var next = settings
        var list = next.followed
        if next.follows(place) { list.removeAll { $0.coordinate.key == place.coordinate.key } }
        else if list.count < AlertSettings.followLimit { list.append(place) }
        next.followedPlaces = list
        update(next)
        let started = next.follows(place)
        Task {
            await check()
            // A confirmation with the situation there now: the bell visibly works,
            // also when there is nothing to report.
            if started { confirmFollow(place) }
        }
    }

    private func confirmFollow(_ place: Place) {
        let now = followedStatus[place.coordinate.key] ?? []
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Ora segui \(place.name)")
        content.subtitle = String(localized: "Allerte meteo IMO, strade chiuse, terremoti")
        content.body = now.isEmpty
            ? String(localized: "Adesso lì non c'è nessuna allerta. Ti avviso quando ne arriva una nuova o se peggiora.")
            : String(localized: "Adesso: \(now.prefix(3).map(\.title).joined(separator: " · "))")
        content.sound = .default
        content.threadIdentifier = "follow"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "follow:\(place.coordinate.key):\(Date().timeIntervalSince1970)", content: content, trigger: nil))
    }

    func auroraPlace(current: Coordinate?) -> Place {
        alertPlace(current: current) ?? model?.activePlace ?? AppModel.monitoredPlace
    }

    /// "Where you are" for the notifications: where the phone really is (with the
    /// GPS outside Iceland, the trip stop of tonight), never a place only being
    /// looked at, unless asked (Settings › Allerte › "Anche il luogo scelto a mano").
    /// Nil without a position.
    func alertPlace(current: Coordinate?) -> Place? {
        let useCurrent = model?.useCurrentLocation ?? (UserDefaults.standard.object(forKey: "useCurrentLocation") as? Bool ?? true)
        if !useCurrent, settings.followsChosenPlace { return model?.activePlace ?? AppModel.storedChosenPlace }
        let now = Date()
        guard let current = current ?? LocationManager.lastKnown else {
            return TripStore.loadFromDisk().first(where: { $0.date <= now && now < $0.endDate })?.place
        }
        if !Coverage.iceland(current), let stop = TripStore.loadFromDisk().first(where: { $0.date <= now && now < $0.endDate }) { return stop.place }
        return Place(name: String(localized: "la tua posizione"), coordinate: current)
    }

    private func buildInput(position: Coordinate?) async -> AlertInput {
        let now = Date()
        var input = AlertInput()
        input.now = now

        let current = position ?? model?.location.coordinate ?? LocationManager.lastKnown
        let currentPlace = alertPlace(current: current)
        if let currentPlace {
            input.watched.append(.init(name: currentPlace.name, coordinate: currentPlace.coordinate,
                                       from: now, to: now.addingTimeInterval(12 * 3600), isCurrent: true))
        }
        // Places followed with the bell: watched for the next day, like a stop.
        for place in settings.followed where place.coordinate.key != currentPlace?.coordinate.key {
            input.watched.append(.init(name: place.name, coordinate: place.coordinate,
                                       from: now, to: now.addingTimeInterval(24 * 3600), isCurrent: false))
        }
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

        if settings.isOn(.aurora), Entitlements.allowsInBackground(.auroraAlerts) {
            // Space weather is checked at any hour (CMEs, Bz, NOAA alerts);
            // the observing conditions only matter after dark, which the engine knows.
            let state: AuroraState?
            if let model {
                await model.refreshAurora()
                state = model.aurora?.value
            } else {
                state = try? await AuroraStateService.load().value
            }
            // The sky "here" only where you really are; space weather (CMEs, NOAA, Bz) for everyone.
            if let currentPlace {
                let forecast = model?.activePlace.coordinate == currentPlace.coordinate ? model?.forecast?.value : nil
                let weather: Forecast?
                if let forecast { weather = forecast } else { weather = try? await WeatherService.forecast(currentPlace.coordinate).value }
                let inputs = AuroraInputs.make(place: currentPlace.coordinate, forecast: weather, state: state,
                                               kp: model?.kp?.value ?? [], ovation: model?.ovation?.value,
                                               horizon: model?.horizons[TerrainService.key(currentPlace.coordinate)], now: now)
                input.auroraSlots = AuroraEngine.forecast(inputs, hours: 12)
                input.auroraZone = weather?.timeZone ?? .iceland
            }
            input.auroraState = state
            if let model {
                input.sightings = model.sightings?.value.recent ?? []
            } else {
                input.sightings = (try? await SightingsFeed.loadFetched().value.recent) ?? []
            }
        }

        if settings.isOn(.wind) || settings.isOn(.weatherWarning) || settings.isOn(.road) {
            await addTravelForecast(to: &input, place: currentPlace, now: now)
        }

        if settings.isOn(.flight), !settings.followedFlights.isEmpty {
            input.flights = (try? await TransportService.kefFlights().value) ?? []
        }
        if settings.isOn(.ferry) {
            if let fetched = try? await TransportService.herjolfur() { input.ferry = fetched.value }
        }
        return input
    }

    /// Forecasts kept 30 minutes: the watch checks every few minutes.
    @ObservationIgnored private var forecastCache: [String: (date: Date, forecast: Forecast)] = [:]

    private func cachedForecast(_ c: Coordinate) async -> Forecast? {
        let key = c.key
        if let hit = forecastCache[key], Date().timeIntervalSince(hit.date) < 1800 { return hit.forecast }
        let fetched: Forecast
        do { fetched = try await WeatherService.forecast(c).value } catch {
            ErrorLog.record("Allerte · previsioni", error, detail: key)
            return forecastCache[key]?.forecast
        }
        forecastCache[key] = (Date(), fetched)
        return fetched
    }

    /// The drives between trip stops from today to the day after tomorrow, and the
    /// next hours at the place watched: the forecast along each of them.
    private func addTravelForecast(to input: inout AlertInput, place: Place?, now: Date) async {
        let calendar = Calendar.iceland
        let today = calendar.startOfDay(for: now)
        let stops = TripStore.loadFromDisk().sorted { $0.date < $1.date }
        for (previous, stop) in zip(stops, stops.dropFirst()) {
            let day = calendar.startOfDay(for: stop.date)
            guard day >= today, day <= today.addingTimeInterval(2 * 24 * 3600),
                  Geo.distanceKm(previous.place.coordinate, stop.place.coordinate) >= 15 else { continue }
            var leg = TripLegCheck(from: previous.place.name, to: stop.place.name, day: day,
                                   samples: TripLegCheck.samples(from: previous.place.coordinate, to: stop.place.coordinate))
            // Driving hours: 07–21 of the travel day.
            let start = day.addingTimeInterval(7 * 3600), end = day.addingTimeInterval(21 * 3600)
            var hours: [Date: TripLegCheck.Hour] = [:]
            for sample in leg.samples {
                if let forecast = await cachedForecast(sample) { TripLegCheck.merge(&hours, forecast, from: start, to: end) }
            }
            leg.hours = hours.values.sorted { $0.date < $1.date }
            input.legs.append(leg)
        }
        if let place, let forecast = await cachedForecast(place.coordinate) {
            var hours: [Date: TripLegCheck.Hour] = [:]
            TripLegCheck.merge(&hours, forecast, from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(7 * 3600))
            input.hereHours = hours.values.sorted { $0.date < $1.date }
            input.herePlace = place.name
        }
    }

    private func deliver(_ candidates: [AlertEvent], quiet: Bool = false) async {
        let now = Date()
        // What each alert is in its life: new or worse (a banner), the same again (the inbox only).
        var decisions: [(AlertEvent, AlertLifecycle.Decision)] = []
        for event in candidates.sorted(by: { $0.severity > $1.severity }) {
            let decision = AlertLifecycle.decide(id: event.id, group: event.lifecycleGroup, severity: event.severity, starts: event.starts,
                                                 fired: fired, seen: seen, now: now)
            if decision != .skip { decisions.append((event, decision)) }
            // Still there: remembered, its worst level and earliest start kept.
            let group = event.lifecycleGroup
            if let last = seen[group], now.timeIntervalSince(last.at) < AlertLifecycle.memory {
                seen[group] = .init(severity: max(last.severity, event.severity), starts: [last.starts, event.starts].compactMap { $0 }.min(), at: now)
            } else {
                seen[group] = .init(severity: event.severity, starts: event.starts, at: now)
            }
        }
        guard !decisions.isEmpty else { save(); return }
        for (event, _) in decisions { fired[event.id] = event.date }
        for (original, decision) in decisions {
            // Alerts quoting web text (IMO, SafeTravel, Vegagerðin, Herjólfur, NOAA) in the app language.
            var event = original
            if Self.quotesWeb(original) { event = await Translator.shared.localize(original) }
            // The previous version of the same alert gives way to this one.
            let previous = events.first { $0.lifecycleGroup == event.lifecycleGroup && $0.category == event.category }
            events.removeAll { $0.lifecycleGroup == event.lifecycleGroup && $0.category == event.category }
            if decision == .quiet, previous?.read == true { event.read = true }
            events.insert(event, at: 0)
            if quiet || decision == .quiet { continue }
            post(event)
            if (isDriving || isMoving) && settings.spoken && event.risk >= .warning {
                say(event.title)
            }
        }
        save()
    }

    /// Once an evening (from 19:30 Iceland time, at the first check), for whoever
    /// has a trip tomorrow: one notification with the drive, the weather, the
    /// roads and the aurora tonight, instead of many small ones.
    private func sendEveningSummary(_ input: AlertInput) async {
        guard settings.eveningSummary else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .iceland
        let minutes = calendar.component(.hour, from: input.now) * 60 + calendar.component(.minute, from: input.now)
        guard minutes >= 19 * 60 + 30, minutes < 23 * 60 + 30 else { return }
        guard let summary = AlertEngine.eveningSummary(input), fired[summary.id] == nil else { return }
        fired[summary.id] = summary.date
        events.insert(summary, at: 0)
        post(summary)
        save()
    }

    private static func quotesWeb(_ event: AlertEvent) -> Bool {
        let prefix = event.id.split(separator: ":").first.map(String.init) ?? ""
        // Also quakes (area names), road sections on the trip, the evening summary
        // (it quotes IMO warnings) and admin notices written in another language.
        return ["w", "s", "h", "swpc", "ri", "rh", "rwh", "rwi", "r", "rw", "q", "lr", "summary", "notice", "cme", "enlil"].contains(prefix)
    }

    private func post(_ event: AlertEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        // The summary says what it is: "Riepilogo" alone did not.
        content.subtitle = event.category == .summary ? String(localized: "Il tuo viaggio di domani, in breve") : event.category.shortLabel
        content.body = event.body
        // At night only danger rings; orange arrives silently, the rest quietly.
        let delivery = AlertLifecycle.delivery(risk: event.severity, at: Date(), quietNights: settings.quietNights)
        if delivery.sound {
            content.sound = settings.customSounds ? UNNotificationSound(named: UNNotificationSoundName(event.soundName + ".wav")) : .default
        }
        if let picture = NotificationIcon.attachment(for: event) { content.attachments = [picture] }
        content.threadIdentifier = event.category.rawValue
        content.interruptionLevel = delivery.urgent ? .timeSensitive : delivery.passive ? .passive : .active
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
        utterance.voice = AVSpeechSynthesisVoice(language: UILanguage.region.replacingOccurrences(of: "_", with: "-"))
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
        var seen: [String: AlertLifecycle.Seen]?
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        events = stored.events
        fired = stored.fired
        seen = stored.seen ?? [:]
    }

    private func save() {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        fired = fired.filter { $0.value > weekAgo }
        seen = seen.filter { now.timeIntervalSince($0.value.at) < AlertLifecycle.memory }
        // Ended alerts leave the inbox after three days.
        events.removeAll { AlertLifecycle.phase(starts: $0.starts, expires: $0.expires, noticed: $0.date, now: now) == .ended
            && now.timeIntervalSince($0.expires ?? $0.date) > 3 * 24 * 3600 }
        if events.count > 300 { events = Array(events.prefix(300)) }
        if let data = try? JSONEncoder().encode(Stored(events: events, fired: fired, seen: seen)) {
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
        // A pushed notice: into the inbox before it opens on it.
        if response.notification.request.content.userInfo["notice"] != nil { await Entitlements.shared.loadConfig() }
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

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { ErrorLog.location(error) }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if AlertCenter.shared.settings.backgroundLocation {
                manager.startMonitoringSignificantLocationChanges()
                if let last = LocationManager.lastKnown { AlertCenter.shared.recentreFence(on: last) }
            }
        }
    }
}
